using System.Diagnostics;
using System.Text;

namespace ShotMap.Core;

public sealed record MediaTools(string FFmpeg, string FFprobe)
{
    public static MediaTools Locate() => new(Find("FFMPEG", "ffmpeg.exe"), Find("FFPROBE", "ffprobe.exe"));

    public Task EncodeWebpAsync(string cachedPng, Stream destination, CancellationToken token)
        => MediaTool.RunAsync(FFmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin",
                "-protocol_whitelist", "file", "-f", "png_pipe", "-i", Path.GetFullPath(cachedPng),
                "-frames:v", "1", "-c:v", "libwebp", "-lossless", "1", "-compression_level", "4",
                "-pix_fmt", "bgra", "-f", "webp", "pipe:1"],
            async (output, cancellation) =>
            {
                await output.CopyToAsync(destination, cancellation).ConfigureAwait(false);
                return true;
            }, _ => { }, null, token);

    private static string Find(string name, string executable)
    {
        string variable = $"SHOTMAP_{name}";
        string? configured = Environment.GetEnvironmentVariable(variable);
        var candidates = string.IsNullOrWhiteSpace(configured)
            ? (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
                .Select(p => p.Trim().Trim('"')).Where(Path.IsPathFullyQualified)
                .Select(p => Path.Combine(p, executable))
                .Prepend(Path.Combine(AppContext.BaseDirectory, "ffmpeg", "bin", executable))
            : [configured];
        return candidates.FirstOrDefault(p => Path.IsPathFullyQualified(p) && File.Exists(p)) is { } found
            ? Path.GetFullPath(found)
            : throw new FileNotFoundException($"找不到 {executable}。请把它放到程序目录的 ffmpeg\\bin，将其加入 PATH，或设置 {variable}。");
    }
}

internal static class MediaTool
{
    public static async Task<T> RunAsync<T>(string executable, IEnumerable<string> args,
        Func<Stream, CancellationToken, Task<T>> readOutput, Action<string> readLog,
        Action<int>? processStarted, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (!Path.IsPathFullyQualified(executable)) throw new ArgumentException("媒体工具需要绝对路径。");
        var start = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (string arg in args) start.ArgumentList.Add(arg);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("无法启动媒体工具。");
        var diagnostics = new Queue<string>(8);
        Task log = DrainLog();
        Task<T>? output = null;
        try
        {
            process.StandardInput.Close();
            processStarted?.Invoke(process.Id);
            output = readOutput(process.StandardOutput.BaseStream, token);
            T result = await output.WaitAsync(token).ConfigureAwait(false);
            await process.WaitForExitAsync(token).ConfigureAwait(false);
            await log.ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (process.ExitCode != 0)
                throw new InvalidDataException($"{Path.GetFileName(executable)} 处理失败（退出码 {process.ExitCode}）。\n"
                    + string.Join('\n', diagnostics));
            return result;
        }
        finally
        {
            if (!process.HasExited)
            {
                try { process.Kill(entireProcessTree: true); }
                catch (InvalidOperationException) when (process.HasExited) { }
            }
            await process.WaitForExitAsync().ConfigureAwait(false);
            await log.ConfigureAwait(false);
            if (output is not null)
                await ((Task)output).ConfigureAwait(ConfigureAwaitOptions.SuppressThrowing);
        }

        async Task DrainLog()
        {
            while (await process.StandardError.ReadLineAsync().ConfigureAwait(false) is { } line)
            {
                readLog(line);
                if (line.Contains("showinfo", StringComparison.Ordinal)) continue;
                if (diagnostics.Count == 8) diagnostics.Dequeue();
                diagnostics.Enqueue(line[..Math.Min(line.Length, 512)]);
            }
        }
    }
}
