using System.ComponentModel;
using ShotMap.Core;

namespace ShotMap.Windows;

internal sealed record JobPreview(string Path, int Width, int Height, int Frames, long Bytes,
    StoryboardOptions Options, VideoInfo Video, long StartPts, FrameStamp?[] Selected)
{
    public string Label => Frames == Options.FrameCount ? $"已生成 · {Frames} 张画面"
        : $"有效画面 {Frames} / {Options.FrameCount} · 其余格子留空";
}

internal enum JobState { Queued, Processing, Completed, Failed }

internal sealed class VideoJob(string path) : INotifyPropertyChanged
{
    private int ordinal;

    public event PropertyChangedEventHandler? PropertyChanged;
    public string Path { get; } = path;
    public string Name => System.IO.Path.GetFileName(Path);
    public string BaseName => System.IO.Path.GetFileNameWithoutExtension(Path);
    public JobPreview? Preview { get; set; }

    public string? LastExport { get; set; }
    public string Status { get; private set; } = "等待处理";
    public JobState State { get; private set; }
    public bool HasLongOrdinal => Ordinal >= 100;

    public int Ordinal
    {
        get => ordinal;
        set
        {
            ordinal = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Ordinal)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(HasLongOrdinal)));
        }
    }

    public void SetStatus(string status, JobState state)
    {
        Status = status;
        State = state;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Status)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(State)));
    }
}
