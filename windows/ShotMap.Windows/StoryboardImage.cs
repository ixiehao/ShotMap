using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ShotMap.Core;

namespace ShotMap.Windows;

public static class StoryboardImage
{
    public static BitmapSource Render(Storyboard storyboard, CancellationToken token)
        => Render(storyboard, StoryboardOptions.Default, "", token);

    public static BitmapSource Render(Storyboard storyboard, StoryboardOptions options, string title, CancellationToken token,
        IReadOnlyList<FrameStamp?>? slots = null)
    {
        var layout = StoryboardLayout.Create(storyboard.Video.Aspect, options);
        Color color = BackgroundColor(options.Tone);
        IReadOnlyList<VideoFrame?> grid = storyboard.Frames;
        if (slots is not null)
        {
            var framesByStamp = storyboard.Frames.ToDictionary(frame => frame.Stamp);
            grid = slots.Select(stamp => stamp is null ? null : framesByStamp[stamp]).ToArray();
        }
        var canvas = new DrawingVisual();
        using (var drawing = canvas.RenderOpen())
        {
            drawing.DrawRectangle(new SolidColorBrush(color), null,
                new Rect(0, 0, layout.Width, layout.Height));
            if (options.Title)
            {
                var heading = new FormattedText(Path.GetFileNameWithoutExtension(title), CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                    new Typeface("Microsoft YaHei UI"), layout.TitleHeight * 0.48, color.R < 100 ? Brushes.White : Brushes.Black, 1)
                    { MaxTextWidth = layout.Width - 2 * layout.Margin, MaxLineCount = 1, Trimming = TextTrimming.CharacterEllipsis };
                drawing.DrawText(heading, new Point(layout.Margin, layout.Margin));
            }
            for (int index = 0; index < Math.Min(grid.Count, options.FrameCount); index++)
            {
                token.ThrowIfCancellationRequested();
                if (grid[index] is not { } frame) continue;
                var pixels = BitmapSource.Create(frame.Width, frame.Height, 96, 96, PixelFormats.Bgr24,
                    null, frame.Bgr, frame.Width * 3);
                double x = layout.Margin + index % layout.Side * (layout.CardWidth + layout.Gap);
                double y = layout.Margin + layout.TitleHeight + index / layout.Side * (layout.CardHeight + layout.Gap);
                var card = new Rect(x, y, layout.CardWidth, layout.CardHeight);
                double scale = Math.Max(card.Width / frame.Width, card.Height / frame.Height);
                double width = frame.Width * scale;
                double height = frame.Height * scale;
                drawing.PushClip(new RectangleGeometry(card));
                drawing.DrawImage(pixels, new Rect(x + (card.Width - width) / 2, y + (card.Height - height) / 2,
                    width, height));
                if (options.Timestamps)
                {
                    var label = new FormattedText(StoryboardLayout.Timecode(storyboard.DisplaySeconds(frame.Stamp)),
                        CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Segoe UI Semibold"),
                        22, Brushes.White, 1);
                    double labelX = card.Right - label.Width - 20;
                    double labelY = card.Bottom - label.Height - 16;
                    drawing.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(184, 0, 0, 0)), null,
                        new Rect(labelX - 8, labelY - 4, label.Width + 16, label.Height + 8), 4, 4);
                    drawing.DrawText(label, new Point(labelX, labelY));
                }
                drawing.Pop();
            }
            if (options.VideoDetails) DrawVideoDetails(drawing, storyboard, layout, title);
        }
        var bitmap = new RenderTargetBitmap(layout.Width, layout.Height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(canvas);
        bitmap.Freeze();
        token.ThrowIfCancellationRequested();
        return bitmap;
    }

    internal static Color BackgroundColor(CanvasTone tone) => tone switch
    {
        CanvasTone.White => Colors.White,
        CanvasTone.Mist => Color.FromRgb(210, 227, 241),
        CanvasTone.Evergreen => Color.FromRgb(24, 70, 57),
        CanvasTone.Navy => Color.FromRgb(14, 37, 65),
        CanvasTone.Cinema => Color.FromRgb(14, 16, 22),
        _ => Color.FromRgb(241, 235, 224),
    };

    private static void DrawVideoDetails(DrawingContext drawing, Storyboard storyboard, StoryboardLayout layout, string filename)
    {
        var video = storyboard.Video;
        string codec = video.Codec switch { "h264" => "H.264", "hevc" => "HEVC", _ => video.Codec.ToUpperInvariant() };
        var dimensions = storyboard.Frames.FirstOrDefault()?.Stamp;
        var top = new List<string> { filename, StoryboardLayout.Timecode(video.Duration) };
        if (video.FileBytes > 0) top.Add($"{video.FileBytes / 1048576.0:0.##} MiB");
        var bottom = new List<string> { $"{dimensions?.Width ?? video.Width} × {dimensions?.Height ?? video.Height}", codec };
        if (video.AverageFps > 0) bottom.Insert(1, $"~{video.AverageFps:0.##} fps");
        if (video.VideoBitRate > 0) bottom.Add(video.VideoBitRate >= 1_000_000
            ? $"~{video.VideoBitRate / 1_000_000:0.##} Mbps" : $"~{video.VideoBitRate / 1000:0} kbps");
        if (video.AudioCodec is { Length: > 0 } audio) bottom.Add(audio.StartsWith("pcm_", StringComparison.Ordinal) ? "PCM" : audio.ToUpperInvariant());

        double fontSize = Math.Clamp(layout.Width * 0.015, 18, 40);
        double padding = fontSize * 0.55;
        var lines = new[] { string.Join("  ·  ", top), string.Join("  ·  ", bottom) }.Select(text =>
            new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface("Microsoft YaHei UI"),
                fontSize, Brushes.White, 1)
            { MaxTextWidth = layout.Width * 0.76 - 2 * padding, MaxLineCount = 1, Trimming = TextTrimming.CharacterEllipsis }).ToArray();
        double height = lines.Sum(line => line.Height) + padding * 2;
        double width = lines.Max(line => line.Width) + padding * 2;
        double x = layout.Margin + padding;
        double y = layout.Margin + layout.TitleHeight + padding;
        drawing.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(190, 0, 0, 0)), null, new Rect(x, y, width, height), 7, 7);
        double lineY = y + padding;
        foreach (var line in lines)
        {
            drawing.DrawText(line, new Point(x + padding, lineY));
            lineY += line.Height;
        }
    }

    public static BitmapSource Load(string path, int maxEdge = 0)
    {
        using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.StreamSource = stream;
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        if (maxEdge > 0)
        {
            var metadata = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None).Frames[0];
            if (metadata.PixelWidth >= metadata.PixelHeight) bitmap.DecodePixelWidth = Math.Min(maxEdge, metadata.PixelWidth);
            else bitmap.DecodePixelHeight = Math.Min(maxEdge, metadata.PixelHeight);
            stream.Position = 0;
        }
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }

    public static void Export(BitmapSource bitmap, string source, string destination, bool overwrite, CancellationToken token)
    {
        BitmapEncoder encoder = Path.GetExtension(destination).ToLowerInvariant() switch
        {
            ".png" => new PngBitmapEncoder(),
            ".jpg" or ".jpeg" => new JpegBitmapEncoder { QualityLevel = 94 },
            _ => throw new IOException("请选择 PNG、JPG 或 WebP 扩展名。"),
        };
        WriteImage(source, destination, overwrite, token, stream =>
        {
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            encoder.Save(stream);
        });
    }

    internal static void ExportWebp(string cachedPng, string source, string destination, bool overwrite, CancellationToken token)
        => WriteImage(source, destination, overwrite, token, stream =>
            MediaTools.Locate().EncodeWebpAsync(cachedPng, stream, token).GetAwaiter().GetResult());

    private static void WriteImage(string source, string destination, bool overwrite, CancellationToken token, Action<Stream> encode)
    {
        destination = Path.GetFullPath(destination);
        source = Path.GetFullPath(source);
        if (string.Equals(source, destination, StringComparison.OrdinalIgnoreCase))
            throw new IOException("请选择与源视频不同的文件名。");
        token.ThrowIfCancellationRequested();
        // A share lock also protects the source when the destination names it via an alias.
        using var sourceGuard = File.Exists(source) ? File.OpenRead(source) : null;
        string temporary = Path.Combine(Path.GetDirectoryName(destination)!, $".shotmap-{Guid.NewGuid():N}.tmp");
        bool created = false;
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                created = true;
                encode(stream);
                if (stream.Position == 0) throw new InvalidDataException("图片编码没有输出数据。");
                stream.Flush(flushToDisk: true);
            }
            token.ThrowIfCancellationRequested();
            File.Move(temporary, destination, overwrite);
            created = false;
        }
        finally
        {
            if (created) File.Delete(temporary);
        }
    }
}
