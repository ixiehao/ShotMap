namespace ShotMap.Core;

internal static class FrameSelection
{
    private const int FingerprintSide = 12;

    internal sealed record Metrics(FrameStamp Stamp, bool Blank, bool Blur, double Detail, float[] Colors);

    public static Metrics Measure(VideoFrame frame, CancellationToken token)
    {
        int width = frame.Width;
        int height = frame.Height;
        var gray = new byte[width * height];
        var colors = new float[FingerprintSide * FingerprintSide * 3];
        var counts = new int[FingerprintSide * FingerprintSide];
        long sum = 0;
        long squares = 0;
        int dark = 0;
        for (int y = 0; y < height; y++)
        {
            token.ThrowIfCancellationRequested();
            for (int x = 0; x < width; x++)
            {
                int pixel = y * width + x;
                int cell = y * FingerprintSide / height * FingerprintSide + x * FingerprintSide / width;
                int b = frame.Bgr[3 * pixel];
                int g = frame.Bgr[3 * pixel + 1];
                int r = frame.Bgr[3 * pixel + 2];
                colors[3 * cell] += b;
                colors[3 * cell + 1] += g;
                colors[3 * cell + 2] += r;
                counts[cell]++;
                int value = (29 * b + 150 * g + 77 * r + 128) >> 8;
                gray[pixel] = (byte)value;
                sum += value;
                squares += value * value;
                if (Math.Max(r, Math.Max(g, b)) < 24) dark++;
            }
        }
        for (int i = 0; i < colors.Length; i++)
            colors[i] /= Math.Max(1, counts[i / 3]);

        long edges = 0;
        long curvature = 0;
        int strong = 0;
        for (int y = 1; y < height - 1; y++)
        {
            for (int x = 1; x < width - 1; x++)
            {
                int p = y * width + x;
                int gradient = Math.Abs(gray[p - 1] - gray[p + 1]) + Math.Abs(gray[p - width] - gray[p + width]);
                edges += gradient;
                curvature += Math.Abs(4 * gray[p] - gray[p - 1] - gray[p + 1] - gray[p - width] - gray[p + width]);
                if (gradient >= 35) strong++;
            }
        }
        double pixels = gray.Length;
        double mean = sum / pixels;
        double contrast = Math.Sqrt(Math.Max(0, squares / pixels - mean * mean));
        bool blank = dark / pixels > 0.98 && mean < 15 && contrast < 6;
        // Require broad tonal changes before treating low edge acuity as blur.
        bool blur = contrast > 20 && edges / pixels > 0.7 && curvature / Math.Max(1.0, edges) < 0.20
            && strong / pixels < 0.008;
        return new(frame.Stamp, blank, blur, curvature / pixels, colors);
    }

    public static (FrameStamp[] Frames, SelectionStats Stats) Choose(IReadOnlyList<Metrics> measured,
        long start, double duration, int slots, CancellationToken token)
    {
        var usable = measured.Where(m => !m.Blank && !m.Blur).ToList();
        var selected = new List<Metrics>(slots);
        var remaining = new List<Metrics>(usable);
        int duplicates = 0;
        // Give each time band a first choice, then fill gaps with widely spaced survivors.
        double Relative(Metrics m) => m.Stamp.TimeBase.Seconds(m.Stamp.Pts - start);
        double span = duration / slots;
        for (int band = 0; band < slots; band++)
        {
            double center = (band + 0.5) * span;
            var candidate = remaining.Where(m => Relative(m) >= band * span
                && (band == slots - 1 || Relative(m) < (band + 1) * span))
                .MaxBy(m => Math.Min(m.Detail / 8, 1) - Math.Abs(Relative(m) - center) / span * 0.6);
            if (candidate is not null) Accept(candidate);
        }
        while (remaining.Count > 0 && selected.Count < slots)
        {
            var candidate = remaining.MaxBy(m => Math.Min(m.Detail / 8, 1) +
                (selected.Count == 0 ? 0 : selected.Min(s => Math.Abs(Relative(m) - Relative(s))) / duration * 4));
            Accept(candidate!);
        }
        return (selected.Select(m => m.Stamp).OrderBy(s => s.Pts).ToArray(),
            new(measured.Count, measured.Count(m => m.Blank), measured.Count(m => m.Blur), duplicates));

        void Accept(Metrics candidate)
        {
            token.ThrowIfCancellationRequested();
            selected.Add(candidate);
            remaining.Remove(candidate);
            duplicates += remaining.RemoveAll(m => NearDuplicate(m, candidate));
        }
    }

    private static bool NearDuplicate(Metrics left, Metrics right)
    {
        if (left.Stamp.Pts == right.Stamp.Pts) return true;
        double differences = 0;
        int changedCells = 0;
        for (int i = 0; i < left.Colors.Length; i += 3)
        {
            double cell = (Math.Abs(left.Colors[i] - right.Colors[i])
                + Math.Abs(left.Colors[i + 1] - right.Colors[i + 1])
                + Math.Abs(left.Colors[i + 2] - right.Colors[i + 2])) / 3;
            differences += cell;
            if (cell > 14) changedCells++;
        }
        return differences / (FingerprintSide * FingerprintSide) < 3.5 && changedCells < 6;
    }
}
