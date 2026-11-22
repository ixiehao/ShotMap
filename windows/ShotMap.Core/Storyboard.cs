namespace ShotMap.Core;

public readonly record struct TimeBase(int Numerator, int Denominator)
{
    public double Seconds(long ticks) => ticks * (double)Numerator / Denominator;
    public override string ToString() => $"{Numerator}/{Denominator}";
}

public sealed record VideoInfo(int Stream, string Codec, int Width, int Height, double Rotation,
    double Aspect, TimeBase TimeBase, long? StartPts, double Duration, long FileBytes = 0,
    DateTime LastWriteUtc = default, double AverageFps = 0, double VideoBitRate = 0, string? AudioCodec = null);

public sealed record FrameStamp(long Pts, TimeBase TimeBase, int Width, int Height);

public sealed record VideoFrame(FrameStamp Stamp, int Width, int Height, byte[] Bgr);

public sealed record Storyboard(VideoInfo Video, long StartPts, IReadOnlyList<VideoFrame> Frames,
    SelectionStats Stats)
{
    public double DisplaySeconds(FrameStamp stamp) => stamp.TimeBase.Seconds(stamp.Pts - StartPts);
}

public sealed record SelectionStats(int Sampled, int Blank, int Blur, int Duplicates);

public readonly record struct PixelSize(int Width, int Height);

public enum CardAspect { Source, Landscape, Standard, Square, Vertical, Portrait, UltraWide }
public enum CanvasTone { White, Ivory, Mist, Evergreen, Navy, Cinema }

public sealed record StoryboardOptions(int Side = 3, int Width = 1920, CardAspect Aspect = CardAspect.Source,
    CanvasTone Tone = CanvasTone.Ivory, bool Timestamps = true, bool Title = false, bool VideoDetails = false)
{
    public static StoryboardOptions Default { get; } = new();
    public int GridSide => Math.Clamp(Side, 3, 8);
    public int FrameCount => GridSide * GridSide;

    public double ResolveAspect(double source) => Math.Clamp(Aspect switch
    {
        CardAspect.Landscape => 16.0 / 9,
        CardAspect.Standard => 4.0 / 3,
        CardAspect.Square => 1,
        CardAspect.Vertical => 3.0 / 4,
        CardAspect.Portrait => 9.0 / 16,
        CardAspect.UltraWide => 21.0 / 9,
        _ => source,
    }, 1.0 / 3, 3);
}

public sealed record StoryboardLayout(int Width, int Height, int Side, int CardWidth, int CardHeight,
    int Margin, int Gap, int TitleHeight)
{
    public static StoryboardLayout Create(double aspect, StoryboardOptions? options = null)
    {
        options ??= StoryboardOptions.Default;
        int side = options.GridSide;
        int width = Math.Clamp(options.Width, 1920, 3840);
        int margin = width / 42;
        int gap = width / 190;
        int cardWidth = (width - 2 * margin - gap * (side - 1)) / side;
        int cardHeight = (int)Math.Floor(cardWidth / options.ResolveAspect(aspect));
        int titleHeight = options.Title ? width / 28 : 0;
        int height = cardHeight * side + 2 * margin + gap * (side - 1) + titleHeight;
        // At the supported widths and aspect ratios, even the tallest canvas is under 45 MP.
        return new(width, height, side, cardWidth, cardHeight, margin, gap, titleHeight);
    }

    public PixelSize Fit(double aspect)
    {
        double width = Math.Max(CardWidth, CardHeight * aspect);
        double height = width / aspect;
        // Retain aspect-fill detail without decoding a large area that will be cropped away.
        double scale = Math.Min(1, Math.Min(4096 / Math.Max(width, height),
            Math.Sqrt(2.0 * CardWidth * CardHeight / (width * height))));
        return new(Math.Max(2, (int)Math.Round(width * scale)), Math.Max(2, (int)Math.Round(height * scale)));
    }

    public static string Timecode(double seconds)
    {
        long total = (long)Math.Max(0, Math.Floor(seconds));
        return $"{total / 3600:00}:{total / 60 % 60:00}:{total % 60:00}";
    }
}
