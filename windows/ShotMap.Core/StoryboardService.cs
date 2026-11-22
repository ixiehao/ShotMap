using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ShotMap.Core;

public enum ProcessingStage { Probe, Sample, Select, ReadSelected }

public sealed partial class StoryboardService(MediaTools tools, Action<int>? processStarted = null)
{
    private const int MinimumSampleBudget = 96;
    private const long MaxExactPts = 9_007_199_254_740_991; // FFmpeg's expression evaluator uses double.

    // Restrict input to self-contained video demuxers. In particular, playlist and
    // concat demuxers can open additional inputs even with a file-only whitelist.
    private static readonly string[] LocalInput = ["-protocol_whitelist", "file", "-format_whitelist",
        "mov,mp4,m4a,3gp,3g2,mj2,matroska,webm,avi,mpeg,mpegts,flv,asf"];

    public Task<Storyboard> GenerateAsync(string path, IProgress<ProcessingStage>? progress, CancellationToken token)
        => GenerateAsync(path, StoryboardOptions.Default, progress, token);

    public Task<Storyboard> GenerateAsync(string path, StoryboardOptions options,
        IProgress<ProcessingStage>? progress, CancellationToken token)
        => GenerateAsync(path, options, progress, token, null);

    public async Task<Storyboard> GenerateAsync(string path, StoryboardOptions options,
        IProgress<ProcessingStage>? progress, CancellationToken token, IProgress<VideoInfo>? probed)
    {
        token.ThrowIfCancellationRequested();
        path = LocalPath(path);
        using var source = File.OpenRead(path);
        progress?.Report(ProcessingStage.Probe);
        VideoInfo video = await ProbeAsync(path, token).ConfigureAwait(false);
        probed?.Report(video);
        progress?.Report(ProcessingStage.Sample);
        int sampleBudget = Math.Max(MinimumSampleBudget, options.FrameCount * 4);
        double period = Math.Max(0.1, video.Duration / (sampleBudget - 1));
        string sampleFilter = $"isnan(prev_selected_t)+gte(t-prev_selected_t,{Invariant(period - 1e-8)})";
        var samples = await DecodeAsync(path, video, sampleFilter, SampleSize(video.Aspect), sampleBudget, token).ConfigureAwait(false);
        if (samples.Count == 0) throw new InvalidDataException("视频中没有可解码的画面。");

        progress?.Report(ProcessingStage.Select);
        long start = video.StartPts ?? samples[0].Stamp.Pts;
        var measured = samples.Select(frame => FrameSelection.Measure(frame, token)).ToArray();
        samples.Clear();
        var (selected, stats) = FrameSelection.Choose(measured, start, video.Duration, options.FrameCount, token);
        if (selected.Length == 0) return new(video, start, [], stats);

        progress?.Report(ProcessingStage.ReadSelected);
        var frames = await ReadExactAsync(path, video, selected, options, token).ConfigureAwait(false);
        return new(video, start, frames, stats);
    }

    public async Task<IReadOnlyList<VideoFrame>> ManualCandidatesAsync(string path, VideoInfo video,
        long startPts, double? seconds, CancellationToken token)
        => seconds is { } time
            ? await ManualFramesFromAsync(path, video, PtsAt(video, startPts, time), token).ConfigureAwait(false)
            : await ManualOverviewAsync(path, video, [], token).ConfigureAwait(false);

    public async Task<IReadOnlyList<VideoFrame>> ManualOverviewAsync(string path, VideoInfo video,
        IReadOnlyList<FrameStamp> selected, CancellationToken token, int capacity = 9, int variant = 0)
    {
        path = LocalPath(path);
        using var source = File.OpenRead(path);
        ConfirmUnchanged(path, video, source.Length);
        int sampleCount = Math.Max(32, Math.Clamp(capacity, 9, 64) + 8);
        double spacing = Math.Max(0.075, video.Duration / (sampleCount - 2));
        string period = Invariant(spacing - 1e-8);
        string phase = Invariant((variant % 5) * spacing / 5);
        // Reset the interval after any selected frame and keep original slot thumbnails in the overview.
        string filter = string.Join('+', selected.Select(stamp => $"eq(pts,{Invariant(stamp.Pts)})")
            .Append($"gte(t-start_t,{phase})*(isnan(prev_selected_t)+gte(t-prev_selected_t,{period}))"));
        return await DecodeAsync(path, video, filter, SampleSize(video.Aspect, 480), sampleCount + selected.Count, token)
            .ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<VideoFrame>> ManualFramesFromAsync(string path, VideoInfo video, long target,
        CancellationToken token)
    {
        path = LocalPath(path);
        using var source = File.OpenRead(path);
        ConfirmUnchanged(path, video, source.Length);
        string filter = $"gte(pts,{Invariant(target)})";
        var size = SampleSize(video.Aspect, 720);
        double? seek = SeekLead(video, target);
        try
        {
            return await DecodeAsync(path, video, filter, size, 12, token, seek).ConfigureAwait(false);
        }
        catch (InvalidDataException) when (seek is not null)
        {
            return await DecodeAsync(path, video, filter, size, 12, token).ConfigureAwait(false);
        }
    }

    public async Task<IReadOnlyList<VideoFrame>> ManualFramesBeforeAsync(string path, VideoInfo video, long exclusivePts,
        int count, CancellationToken token)
    {
        path = LocalPath(path);
        using var source = File.OpenRead(path);
        ConfirmUnchanged(path, video, source.Length);
        count = Math.Clamp(count, 1, 5);
        var size = SampleSize(video.Aspect, 720);
        double? seek = SeekLead(video, exclusivePts);
        if (seek is not null)
        {
            try
            {
                var nearby = await DecodeAsync(path, video, "1", size, count, token, seek, exclusivePts).ConfigureAwait(false);
                if (nearby.Count == count) return nearby;
            }
            catch (InvalidDataException) { }
        }
        return await DecodeAsync(path, video, "1", size, count, token, before: exclusivePts).ConfigureAwait(false);
    }

    public static FrameStamp[] SuggestManualSelection(IReadOnlyList<VideoFrame> frames, IReadOnlySet<long> chosen,
        long startPts, double duration, int slots, CancellationToken token)
    {
        if (slots <= 0) return [];
        var measured = frames.Where(frame => !chosen.Contains(frame.Stamp.Pts)).Select(frame => FrameSelection.Measure(frame, token)).ToArray();
        return FrameSelection.Choose(measured, startPts, duration, slots, token).Frames;
    }

    public static long PtsAt(VideoInfo video, long startPts, double seconds)
    {
        double target = Math.Ceiling(startPts + seconds * video.TimeBase.Denominator / video.TimeBase.Numerator - 1e-6);
        if (!double.IsFinite(target) || Math.Abs(target) > MaxExactPts)
            throw new InvalidDataException("定位时间超出精确回读范围。");
        return (long)target;
    }

    private static double? SeekLead(VideoInfo video, long pts)
    {
        double position = video.TimeBase.Seconds(pts) - 2;
        double start = video.StartPts is { } startPts ? video.TimeBase.Seconds(startPts) : 0;
        return position > Math.Max(0, start) ? position : null;
    }

    public async Task<Storyboard> RecomposeAsync(string path, VideoInfo video, long startPts,
        IReadOnlyList<FrameStamp> selected, StoryboardOptions options, CancellationToken token)
    {
        path = LocalPath(path);
        using var source = File.OpenRead(path);
        ConfirmUnchanged(path, video, source.Length);
        if (selected.Count == 0 || selected.Count > options.FrameCount)
            throw new ArgumentException("请至少保留一张画面，且选帧数量不能超过网格容量。");
        var frames = await ReadExactAsync(path, video, selected.OrderBy(stamp => stamp.Pts).ToArray(), options, token)
            .ConfigureAwait(false);
        return new(video, startPts, frames, new(0, 0, 0, 0));
    }

    private static string LocalPath(string path)
    {
        path = Path.GetFullPath(path);
        string root = Path.GetPathRoot(path)!;
        if (root.StartsWith("\\\\", StringComparison.Ordinal) || new DriveInfo(root).DriveType == DriveType.Network)
            throw new IOException("请选择本机磁盘上的视频文件。");
        return path;
    }

    private static void ConfirmUnchanged(string path, VideoInfo video, long length)
    {
        if (video.FileBytes != length || video.LastWriteUtc != File.GetLastWriteTimeUtc(path))
            throw new IOException("源视频已修改，请重新生成分镜后再选帧。");
    }

    private static PixelSize SampleSize(double aspect, int edge = 320) => new((int)Math.Clamp(Math.Round(edge * aspect), 2, edge),
        (int)Math.Clamp(Math.Round(edge / aspect), 2, edge));

    private async Task<List<VideoFrame>> ReadExactAsync(string path, VideoInfo video, FrameStamp[] selected,
        StoryboardOptions options, CancellationToken token)
    {
        if (selected.Any(stamp => stamp.Pts is < -MaxExactPts or > MaxExactPts || stamp.TimeBase != video.TimeBase)
            || selected.Select(stamp => stamp.Pts).Distinct().Count() != selected.Length)
            throw new InvalidDataException("视频时间戳超出精确回读范围。");
        var size = StoryboardLayout.Create(video.Aspect, options).Fit(video.Aspect);
        string exactFilter = string.Join('+', selected.Select(stamp => $"eq(pts,{Invariant(stamp.Pts)})"));
        var frames = await DecodeAsync(path, video, exactFilter, size, selected.Length, token).ConfigureAwait(false);
        if (!frames.Select(frame => frame.Stamp).SequenceEqual(selected))
            throw new InvalidDataException("高清取帧未匹配已选画面的实际时间戳或尺寸。请重试或检查源视频。");
        return frames;
    }

    private async Task<VideoInfo> ProbeAsync(string path, CancellationToken token)
    {
        string[] args = ["-v", "error", ..LocalInput,
            "-show_entries", "stream=index,codec_type,codec_name,width,height,sample_aspect_ratio,time_base,start_pts,duration,avg_frame_rate,bit_rate:stream_disposition=attached_pic:stream_side_data=rotation:format=duration",
            "-of", "json", "-i", path];
        byte[] output = await MediaTool.RunAsync(tools.FFprobe, args,
            async (stream, cancellation) =>
            {
                using var input = new MemoryStream();
                var buffer = new byte[4096];
                int bytes;
                while ((bytes = await stream.ReadAsync(buffer, cancellation).ConfigureAwait(false)) != 0)
                {
                    if (input.Length + bytes > 1024 * 1024) throw new InvalidDataException("视频元数据过大。");
                    input.Write(buffer, 0, bytes);
                }
                return input.ToArray();
            }, _ => { }, processStarted, token).ConfigureAwait(false);
        using JsonDocument json = JsonDocument.Parse(output);

        var root = json.RootElement;
        if (!root.TryGetProperty("streams", out var streams)) throw new InvalidDataException("文件中没有视频流。");
        string? audioCodec = streams.EnumerateArray().Where(stream => Value(stream, "codec_type") == "audio")
            .Select(stream => Value(stream, "codec_name")).FirstOrDefault();
        foreach (var stream in streams.EnumerateArray())
        {
            if (Value(stream, "codec_type") != "video") continue;
            if (stream.TryGetProperty("disposition", out var disposition) && Number(disposition, "attached_pic") == 1) continue;
            int width = (int)Number(stream, "width");
            int height = (int)Number(stream, "height");
            if (width <= 0 || height <= 0 || width > 16384 || height > 16384 || (long)width * height > 64_000_000)
                throw new InvalidDataException("视频尺寸无效或超出原型的解码上限。");
            var timeBase = ParseRational(Value(stream, "time_base"), '/');
            if (timeBase is null) throw new InvalidDataException("视频流缺少有效时间基。");
            double duration = Number(stream, "duration");
            if (duration <= 0 && root.TryGetProperty("format", out var format)) duration = Number(format, "duration");
            if (duration <= 0) throw new InvalidDataException("视频缺少有效时长，无法沿时间轴分布取帧。");
            double rotation = stream.TryGetProperty("side_data_list", out var sideData)
                ? sideData.EnumerateArray().Select(side => Number(side, "rotation")).FirstOrDefault(value => value != 0)
                : 0;
            var sar = ParseRational(Value(stream, "sample_aspect_ratio"), ':') ?? new TimeBase(1, 1);
            double aspect = sar.Seconds(width) / height;
            if (Math.Abs(Math.IEEERemainder(rotation, 180)) > 89.5) aspect = 1 / aspect;
            long? start = long.TryParse(Value(stream, "start_pts"), CultureInfo.InvariantCulture, out long pts) ? pts : null;
            double fps = ParseRational(Value(stream, "avg_frame_rate"), '/')?.Seconds(1) ?? 0;
            var file = new FileInfo(path);
            return new((int)Number(stream, "index"), Value(stream, "codec_name") ?? "unknown", width, height,
                rotation, aspect, timeBase.Value, start, duration, file.Length, file.LastWriteTimeUtc, fps,
                Number(stream, "bit_rate"), audioCodec);
        }
        throw new InvalidDataException("文件中没有视频流。");
    }

    private async Task<List<VideoFrame>> DecodeAsync(string path, VideoInfo video, string selection,
        PixelSize size, int limit, CancellationToken token, double? seek = null, long? before = null)
    {
        string trim = before is { } stop ? $"trim=end_pts={Invariant(stop)}," : "";
        string filter = $"{trim}select='{selection}',showinfo=checksum=0,scale={size.Width}:{size.Height}:flags=lanczos,setsar=1";
        string[] seekArgs = seek is { } at ? ["-seek_timestamp", "1", "-ss", Invariant(at)] : [];
        string[] limitArgs = before is null ? ["-frames:v", Invariant(limit)] : [];
        string[] args = ["-hide_banner", "-nostdin", "-nostats", "-loglevel", "info", "-copyts", "-xerror",
            "-filter_threads", "2", "-threads", "4", "-max_pixels", "64000000", ..LocalInput, ..seekArgs,
            "-i", path, "-map", $"0:{video.Stream}", "-vf", filter,
            "-fps_mode", "passthrough", ..limitArgs, "-threads:v", "1", "-c:v", "rawvideo",
            "-pix_fmt", "bgr24", "-f", "rawvideo", "pipe:1"];

        TimeBase? decodedTimeBase = null;
        var stamps = new List<FrameStamp>();
        int logged = 0;
        bool valid = true;
        var (buffers, decodedCount) = await MediaTool.RunAsync(tools.FFmpeg, args, ReadFrames, ReadLog, processStarted, token)
            .ConfigureAwait(false);
        if (!valid || stamps.Count < buffers.Count || decodedTimeBase != video.TimeBase || (before is not null && logged != decodedCount))
            throw new InvalidDataException("无法核对解码画面与视频流的实际时间戳。");
        return buffers.Select((buffer, index) => new VideoFrame(stamps[index], size.Width, size.Height, buffer)).ToList();

        async Task<(List<byte[]> Buffers, int Count)> ReadFrames(Stream stream, CancellationToken cancellation)
        {
            var result = new List<byte[]>(limit);
            int frameBytes = checked(size.Width * size.Height * 3);
            int count = 0;
            while (before is not null || result.Count < limit)
            {
                bool rotate = before is not null && result.Count == limit;
                var buffer = rotate ? result[0] : new byte[frameBytes];
                int bytes = await stream.ReadAtLeastAsync(buffer, frameBytes, false, cancellation)
                    .ConfigureAwait(false);
                if (bytes == 0) break;
                if (bytes != frameBytes) throw new InvalidDataException("解码器返回了不完整的画面。");
                if (rotate) result.RemoveAt(0);
                result.Add(buffer);
                count++;
            }
            if (await stream.ReadAsync(new byte[1], cancellation).ConfigureAwait(false) != 0)
                throw new InvalidDataException("解码器返回的画面数量超出限制。");
            return (result, count);
        }

        void ReadLog(string line)
        {
            if (!line.StartsWith("[Parsed_showinfo_", StringComparison.Ordinal)) return;
            var basis = FilterTimeBase().Match(line);
            if (basis.Success)
            {
                decodedTimeBase = ParseRational(basis.Groups[1].Value, '/');
                valid &= decodedTimeBase == video.TimeBase;
            }
            var match = FilterFrame().Match(line);
            if (!match.Success || (before is null && stamps.Count > limit)) return;
            if (decodedTimeBase is { } timeBase &&
                int.TryParse(match.Groups[1].Value, CultureInfo.InvariantCulture, out int index) && index == logged &&
                long.TryParse(match.Groups[2].Value, CultureInfo.InvariantCulture, out long pts) &&
                int.TryParse(match.Groups[3].Value, CultureInfo.InvariantCulture, out int w) &&
                int.TryParse(match.Groups[4].Value, CultureInfo.InvariantCulture, out int h))
            {
                logged++;
                if (before is not null && stamps.Count == limit) stamps.RemoveAt(0);
                stamps.Add(new(pts, timeBase, w, h));
            }
            else valid = false;
        }
    }

    private static string? Value(JsonElement item, string key) =>
        item.TryGetProperty(key, out var value) ? value.ToString() : null;

    private static double Number(JsonElement item, string key) =>
        double.TryParse(Value(item, key), NumberStyles.Float, CultureInfo.InvariantCulture, out double value)
            && double.IsFinite(value) ? value : 0;

    private static TimeBase? ParseRational(string? text, char separator)
    {
        var pieces = text?.Split(separator);
        return pieces is { Length: 2 } && int.TryParse(pieces[0], out int numerator) && numerator > 0
            && int.TryParse(pieces[1], out int denominator) && denominator > 0 ? new(numerator, denominator) : null;
    }

    private static string Invariant<T>(T number) where T : IFormattable => number.ToString(null, CultureInfo.InvariantCulture);

    [GeneratedRegex(@"config in time_base:\s*(\d+/\d+)")]
    private static partial Regex FilterTimeBase();

    [GeneratedRegex(@"\bn:\s*(\d+)\s+pts:\s*(\S+).*?\bs:(\d+)x(\d+)")]
    private static partial Regex FilterFrame();
}
