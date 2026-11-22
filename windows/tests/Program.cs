using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows.Media.Imaging;
using ShotMap.Core;
using ShotMap.Windows;

Console.OutputEncoding = Encoding.UTF8;
CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
if (args.FirstOrDefault() == "--desktop-drag")
{
    DesktopDragCheck.Run(args[1..]);
    return;
}
bool phoneTest = args is ["--phone", _, _];
if (!phoneTest && args.Length != 2)
    throw new ArgumentException("Usage: ShotMap.Verify <fixture directory> <output directory> | --phone <VFR HEVC video> <output directory> | --desktop-drag <video> [...] ");
string input = Path.GetFullPath(args[phoneTest ? 1 : 0]);
string output = Directory.CreateDirectory(args[phoneTest ? 2 : 1]).FullName;
var tools = MediaTools.Locate();
using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(3));
var token = deadline.Token;
using var measurement = new WorkingSetMonitor();
var service = new StoryboardService(tools, measurement.Observe);
if (phoneTest)
{
    string beforePhone = Hash(input);
    await ExportCase("Phone VFR HEVC", input, "手机实拍 分镜", expectedPortrait: null, verifyVfr: true);
    Check(Hash(input) == beforePhone, "phone source SHA-256 is unchanged");
    return;
}
string h264 = Directory.GetFiles(input, "* H264.mp4").Single();
string vfr = Directory.GetFiles(input, "* VFR.mp4").Single();
var hashes = Directory.GetFiles(input, "*.mp4").Where(file => Path.GetFileName(file) != "cancel.mp4")
    .Concat(Directory.GetFiles(input, "*.mov")).ToDictionary(file => file, Hash);

await ExportCase("H264", h264, "横屏 分镜", expectedPortrait: false);
await ExportCase("VFR", vfr, "可变帧率 分镜", expectedPortrait: false, verifyVfr: true);
await ExportCase("Rotated MOV", Fixture("rotation VFR.mov"), "旋转竖屏 分镜", expectedPortrait: true, verifyVfr: true);
await ExportCase("HEVC", Fixture("HEVC.mp4"), "HEVC 分镜", expectedPortrait: false);

var quality = await service.GenerateAsync(Fixture("quality.mp4"), null, token);
Check(quality.Stats is { Blank: > 0, Blur: > 0, Duplicates: > 0 }, $"quality gates {quality.Stats}");
Check(quality.Frames.All(f => quality.DisplaySeconds(f.Stamp) >= 2), "black and blur segments excluded");
Check(quality.Frames.Count(f => quality.DisplaySeconds(f.Stamp) >= 6) <= 1, "repeated segment is represented at most once");
var still = await service.GenerateAsync(Fixture("static.mp4"), null, token);
Check(still.Frames.Count == 1 && still.Stats.Duplicates > 0, "sharp static clip yields one valid frame");
StoryboardImage.Export(StoryboardImage.Render(still, token), Fixture("static.mp4"), Out("静态 不足九格.png"), false, token);
Console.WriteLine($"PASS quality {quality.Stats}; static {still.Frames.Count}/9 {still.Stats}");

var custom = new StoryboardOptions(4, 2560, CardAspect.Square, CanvasTone.Mist, Timestamps: false, Title: true);
var customBoard = await service.GenerateAsync(h264, custom, null, token);
var customImage = StoryboardImage.Render(customBoard, custom, "横屏 测试", token);
Check(customBoard.Frames.Count == 16 && customImage.PixelWidth == 2560 && customImage.PixelHeight == 2650,
    "custom 4 x 4 grid, width, square tiles and title band");
var background = new byte[4];
customImage.CopyPixels(new System.Windows.Int32Rect(0, 0, 1, 1), background, 4, 0);
Check(background.SequenceEqual(new byte[] { 241, 227, 210, 255 }), "custom mist canvas color");
StoryboardImage.Export(customImage, h264, Out("4x4 方形 雾蓝.png"), false, token);
Console.WriteLine("PASS custom 4 x 4, 2560 x 2650, square, mist, title, timestamps disabled");

var originalBoard = await service.GenerateAsync(vfr, null, token);
var overview = await service.ManualOverviewAsync(vfr, originalBoard.Video,
    originalBoard.Frames.Select(frame => frame.Stamp).ToArray(), token);
Check(originalBoard.Frames.All(chosen => overview.Any(frame => frame.Stamp == chosen.Stamp)), "gallery includes already-selected exact frames");
var seeked = await service.ManualCandidatesAsync(vfr, originalBoard.Video, originalBoard.StartPts, 5.2, token);
var previous = await service.ManualFramesBeforeAsync(vfr, originalBoard.Video, seeked[0].Stamp.Pts, 5, token);
Check(previous.Count == 5 && previous[^1].Stamp.Pts < seeked[0].Stamp.Pts, "step backward reads the five preceding frames");
var forward = await service.ManualFramesFromAsync(vfr, originalBoard.Video, previous[0].Stamp.Pts + 1, token);
Check(forward.Take(5).Select(frame => frame.Stamp).SequenceEqual(previous.Skip(1).Append(seeked[0]).Select(frame => frame.Stamp)),
    "forward and backward steps resolve the same VFR frame sequence");
var nearby = await service.ManualCandidatesAsync(vfr, originalBoard.Video, originalBoard.StartPts, 1.4, token);
Check(nearby.Count == 12 && originalBoard.DisplaySeconds(nearby[0].Stamp) >= 1.4, "manual time lookup reads nearby frames");
var edits = originalBoard.Frames.Select(frame => (FrameStamp?)frame.Stamp).ToArray();
var replacement = nearby.First(frame => !edits.Contains(frame.Stamp)).Stamp;
edits[0] = replacement;
edits[1] = null;
var manualOptions = StoryboardOptions.Default with { VideoDetails = true };
var editedBoard = await service.RecomposeAsync(vfr, originalBoard.Video, originalBoard.StartPts,
    edits.OfType<FrameStamp>().ToArray(), manualOptions, token);
Check(editedBoard.Frames.Count == 8 && editedBoard.Frames.Any(frame => frame.Stamp == replacement), "manual PTS is retained");
await VerifyFrameIdentity(vfr, editedBoard);
var editedImage = StoryboardImage.Render(editedBoard, manualOptions, Path.GetFileName(vfr), token, edits);
var emptySlot = new byte[4];
editedImage.CopyPixels(new System.Windows.Int32Rect(950, 200, 1, 1), emptySlot, 4, 0);
Check(emptySlot.SequenceEqual(new byte[] { 224, 235, 241, 255 }), "cleared manual slot remains ivory");
var infoPixel = new byte[4];
var cleanPixel = new byte[4];
var infoArea = new System.Windows.Int32Rect(100, 80, 1, 1);
editedImage.CopyPixels(infoArea, infoPixel, 4, 0);
StoryboardImage.Render(editedBoard, StoryboardOptions.Default, "", token, edits).CopyPixels(infoArea, cleanPixel, 4, 0);
Check(!infoPixel.SequenceEqual(cleanPixel), "video detail overlay changes rendered pixels");
StoryboardImage.Export(editedImage, vfr, Out("手动选帧 视频信息.png"), false, token);
Console.WriteLine($"PASS manual: selected overview, VFR seek and ±5 frames, replacement PTS {replacement.Pts}, empty slot and video details");

try
{
    await service.GenerateAsync(Fixture("broken.mp4"), null, token);
    throw new Exception("Expected corrupt input to fail.");
}
catch (InvalidDataException error) { Console.WriteLine($"PASS corrupt input {error.Message.Split('\n')[0]}"); }

using (var cancel = CancellationTokenSource.CreateLinkedTokenSource(token))
{
    int decoderPid = 0;
    int launches = 0;
    var cancelDuringDecode = new StoryboardService(tools, pid =>
    {
        if (++launches != 2) return;
        decoderPid = pid;
        Check(IsAlive(pid), "FFmpeg is active before cancellation");
        cancel.CancelAfter(100);
    });
    var clock = Stopwatch.StartNew();
    try
    {
        await cancelDuringDecode.GenerateAsync(Fixture("cancel.mp4"), null, cancel.Token);
        throw new Exception("Expected cancellation.");
    }
    catch (OperationCanceledException) when (cancel.IsCancellationRequested)
    {
        Check(decoderPid != 0 && !IsAlive(decoderPid), "cancel waits for decoder exit");
        Console.WriteLine($"PASS cancelled FFmpeg PID {decoderPid} exited; {clock.Elapsed.TotalMilliseconds:F0} ms including probe");
    }
}

var retry = await service.GenerateAsync(h264, null, token);
Check(retry.Frames.Count == 9, "retry after error and cancellation");
var bitmap = StoryboardImage.Render(retry, token);
string denied = Out("protected");
Directory.CreateDirectory(denied);
// Install a deny ACE on this fixture directory only, then restore its original ACL.
var directory = new DirectoryInfo(denied);
var blockedAcl = directory.GetAccessControl();
using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
var denyCreate = new System.Security.AccessControl.FileSystemAccessRule(identity.User!,
    System.Security.AccessControl.FileSystemRights.CreateFiles, System.Security.AccessControl.AccessControlType.Deny);
blockedAcl.AddAccessRule(denyCreate);
directory.SetAccessControl(blockedAcl);
try
{
    try
    {
        StoryboardImage.Export(bitmap, h264, Path.Combine(denied, "blocked.jpg"), false, token);
        throw new Exception("Expected export to fail in the denied directory.");
    }
    catch (UnauthorizedAccessException) { Check(!Directory.EnumerateFileSystemEntries(denied).Any(), "no denied output or temporary file"); }
}
finally
{
    blockedAcl.RemoveAccessRuleSpecific(denyCreate);
    directory.SetAccessControl(blockedAcl);
}
StoryboardImage.Export(bitmap, h264, Path.Combine(denied, "retry.jpg"), false, token);
Check(File.Exists(Path.Combine(denied, "retry.jpg")), "export retry succeeds after restoring permission");
string existing = Out("横屏 分镜.jpg");
string before = Hash(existing);
try
{
    StoryboardImage.Export(bitmap, h264, existing, false, token);
    throw new Exception("Expected no-overwrite export to fail.");
}
catch (IOException) { Check(Hash(existing) == before, "existing export is preserved"); }
using (var stopExport = new CancellationTokenSource())
{
    stopExport.Cancel();
    try
    {
        StoryboardImage.Export(bitmap, h264, Out("cancelled.png"), false, stopExport.Token);
        throw new Exception("Expected export cancellation.");
    }
    catch (OperationCanceledException) { Check(!File.Exists(Out("cancelled.png")), "cancelled export is absent"); }
}
Check(hashes.All(pair => Hash(pair.Key) == pair.Value), "source SHA-256 hashes are unchanged");
Check(!Directory.EnumerateFiles(output, ".shotmap-*.tmp", SearchOption.AllDirectories).Any(), "no temporary export files retained");
Console.WriteLine("PASS ACL denial, export retry, no overwrite, cancelled export, source hashes and temporary-file cleanup");

async Task ExportCase(string label, string source, string basename, bool? expectedPortrait, bool verifyVfr = false)
{
    measurement.Reset();
    var elapsed = Stopwatch.StartNew();
    var storyboard = await service.GenerateAsync(source, null, token);
    Check(phoneTest ? storyboard.Video.Codec == "hevc" && storyboard.Frames.Count > 0 : storyboard.Frames.Count == 9,
        $"{label}: {storyboard.Video.Codec}, {storyboard.Frames.Count}/9 {storyboard.Stats}");
    var preview = StoryboardImage.Render(storyboard, token);
    double previewMs = elapsed.Elapsed.TotalMilliseconds;
    foreach (string extension in new[] { ".png", ".jpg" })
        StoryboardImage.Export(preview, source, Out(basename + extension), false, token);
    double totalMs = elapsed.Elapsed.TotalMilliseconds;
    double peakMiB = measurement.PeakMiB;
    bool portrait = expectedPortrait ?? storyboard.Video.Aspect < 1;
    Check(preview.PixelWidth == 1920 && (preview.PixelHeight > preview.PixelWidth) == portrait, $"{label} canvas direction");
    foreach (string extension in new[] { ".png", ".jpg" })
    {
        using var file = File.OpenRead(Out(basename + extension));
        var decoded = BitmapDecoder.Create(file, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        Check(decoded.Frames[0].PixelWidth == 1920 && decoded.Frames[0].PixelHeight == preview.PixelHeight, "encoded dimensions");
        Check(extension == ".png" ? decoded is PngBitmapDecoder : decoded is JpegBitmapDecoder, "encoded image format");
    }
    if (expectedPortrait == true)
    {
        Check(storyboard.Video.Rotation == 90 && storyboard.Video.Width == 640 && storyboard.Video.Height == 360,
            "90-degree display matrix on landscape-coded stream");
        Check(storyboard.Frames.All(f => f.Stamp is { Width: 360, Height: 640 }), "rotated decoded dimensions");
        var frame = storyboard.Frames[0];
        Check(Corner(frame, 0, 0) == "yellow" && Corner(frame, 1, 0) == "green" &&
            Corner(frame, 0, 1) == "red" && Corner(frame, 1, 1) == "blue", "rotated pixel orientation");
    }
    if (verifyVfr) await VerifyFrameIdentity(source, storyboard);

    using var trace = new StreamWriter(Out(basename + ".csv"), false, Encoding.UTF8);
    trace.WriteLine("stream,codec,coded_width,coded_height,rotation,pts,time_base,display_seconds,decoded_width,decoded_height,scaled_width,scaled_height,bgr_sha256");
    foreach (var frame in storyboard.Frames)
        trace.WriteLine($"{storyboard.Video.Stream},{storyboard.Video.Codec},{storyboard.Video.Width},{storyboard.Video.Height},{storyboard.Video.Rotation},{frame.Stamp.Pts},{frame.Stamp.TimeBase},{storyboard.DisplaySeconds(frame.Stamp):F6},{frame.Stamp.Width},{frame.Stamp.Height},{frame.Width},{frame.Height},{Convert.ToHexString(SHA256.HashData(frame.Bgr))}");
    Console.WriteLine($"PASS {label}: {storyboard.Frames.Count}/9; {preview.PixelWidth}x{preview.PixelHeight}; preview {previewMs:F0} ms; both exports {totalMs:F0} ms; combined peak {peakMiB:F1} MiB; PTS {string.Join(',', storyboard.Frames.Select(f => f.Stamp.Pts))} @ {storyboard.Video.TimeBase}");
}

async Task VerifyFrameIdentity(string source, Storyboard storyboard)
{
    // Independent reference: ffprobe's decoded frame table maps PTS to ordinal.
    byte[] json = await Capture(tools.FFprobe, "-v", "error", "-select_streams", storyboard.Video.Stream.ToString(), "-show_frames",
        "-show_entries", "frame=pts,key_frame", "-of", "json", "-i", source);
    using var report = JsonDocument.Parse(json);
    var decoded = report.RootElement.GetProperty("frames").EnumerateArray()
        .Select(f => (Pts: f.GetProperty("pts").GetInt64(), Key: f.GetProperty("key_frame").GetInt32())).ToArray();
    long[] intervals = decoded.Skip(1).Zip(decoded).Select(pair => pair.First.Pts - pair.Second.Pts).Distinct().Order().ToArray();
    Check(phoneTest ? intervals.Length > 1 && intervals[0] > 0 : decoded.Length == 80 && intervals.Length == 2,
        "source has positive, unequal frame intervals");
    if (phoneTest)
        Console.WriteLine($"Source: {decoded.Length} frames, {intervals.Length} distinct PTS intervals, {intervals[0]} to {intervals[^1]} ticks @ {storyboard.Video.TimeBase}, rotation {storyboard.Video.Rotation}");
    int[] indexes = storyboard.Frames.Select(frame => Array.FindIndex(decoded, f => f.Pts == frame.Stamp.Pts)).ToArray();
    Check(indexes.All(index => index >= 0) && indexes.SequenceEqual(indexes.Order().Distinct()), "selected timestamps are real and ordered");
    Check(indexes.Count(index => decoded[index].Key == 0) >= (phoneTest ? 1 : 8), "selected frames include non-keyframes");
    var first = storyboard.Frames[0];
    string filter = $"select='{string.Join('+', indexes.Select(index => $"eq(n,{index})"))}',scale={first.Width}:{first.Height}:flags=lanczos,setsar=1";
    byte[] reference = await Capture(tools.FFmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-filter_threads", "2",
        "-i", source, "-map", $"0:{storyboard.Video.Stream}", "-vf", filter, "-fps_mode", "passthrough", "-threads:v", "1", "-c:v", "rawvideo",
        "-pix_fmt", "bgr24", "-f", "rawvideo", "pipe:1");
    Check(reference.Length == first.Bgr.Length * indexes.Length, "reference frame count");
    for (int i = 0; i < indexes.Length; i++)
        Check(reference.AsSpan(i * first.Bgr.Length, first.Bgr.Length).SequenceEqual(storyboard.Frames[i].Bgr),
            $"PTS {storyboard.Frames[i].Stamp.Pts} matches independent frame #{indexes[i]} pixel-for-pixel");
    Console.WriteLine($"PASS VFR pixel identity at source ordinals {string.Join(',', indexes)}");
}

async Task<byte[]> Capture(string executable, params string[] arguments)
{
    var start = new ProcessStartInfo(executable) { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true };
    foreach (string arg in arguments) start.ArgumentList.Add(arg);
    using var process = Process.Start(start)!;
    using var result = new MemoryStream();
    await process.StandardOutput.BaseStream.CopyToAsync(result, token);
    await process.WaitForExitAsync(token);
    Check(process.ExitCode == 0, $"reference tool {Path.GetFileName(executable)} exited 0");
    return result.ToArray();
}

string Fixture(string file) => Path.Combine(input, file);
string Out(string file) => Path.Combine(output, file);
static string Hash(string file) { using var stream = File.OpenRead(file); return Convert.ToHexString(SHA256.HashData(stream)); }
static void Check(bool condition, string detail) { if (!condition) throw new InvalidOperationException(detail); }
static bool IsAlive(int pid)
{
    try { using var child = Process.GetProcessById(pid); return !child.HasExited; }
    catch (ArgumentException) { return false; }
}
static string Corner(VideoFrame frame, int side, int end)
{
    int x = side == 0 ? 10 : frame.Width - 11;
    int y = end == 0 ? 10 : frame.Height - 11;
    var pixel = frame.Bgr.AsSpan(3 * (y * frame.Width + x), 3);
    return (pixel[0] > 180, pixel[1] > 180, pixel[2] > 180) switch
    {
        (false, true, true) => "yellow",
        (false, true, false) => "green",
        (false, false, true) => "red",
        (true, false, false) => "blue",
        _ => $"BGR({pixel[0]}, {pixel[1]}, {pixel[2]})",
    };
}

sealed class WorkingSetMonitor : IDisposable
{
    private readonly Process app = Process.GetCurrentProcess();
    private readonly Timer timer;
    private readonly object gate = new();
    private int childPid;
    private long peak;

    public WorkingSetMonitor() => timer = new(_ => Sample(), null, 0, 20);
    public void Reset() { lock (gate) { peak = 0; childPid = 0; } }
    public void Observe(int pid) { lock (gate) childPid = pid; }
    public double PeakMiB { get { Sample(); lock (gate) return peak / 1048576.0; } }

    private void Sample()
    {
        lock (gate)
        {
            app.Refresh();
            long bytes = app.WorkingSet64;
            try
            {
                if (childPid != 0)
                {
                    using var child = Process.GetProcessById(childPid);
                    bytes += child.WorkingSet64;
                }
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception) { }
            peak = Math.Max(peak, bytes);
        }
    }

    public void Dispose() => timer.DisposeAsync().AsTask().GetAwaiter().GetResult();
}
