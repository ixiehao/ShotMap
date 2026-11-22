using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using ShotMap.Core;

namespace ShotMap.Windows;

public partial class MainWindow : Window
{
    private const long CacheLimit = 1024L * 1024 * 1024;
    private readonly ObservableCollection<VideoJob> queue = [];
    private readonly SemaphoreSlim previewReader = new(1);
    private CancellationTokenSource? operation;
    private DirectoryInfo? cache;
    private VideoJob? activeJob;
    private long cacheBytes;
    private int previewRevision;
    private bool closeAfterOperation;
    private bool editingFrames;
    private bool generating;
    private bool canPauseBetweenJobs;
    private bool pauseRequested;
    private TaskCompletionSource? pauseGate;
    private StoryboardOptions? activeOptions;
    private VideoInfo? activeVideo;

    public MainWindow()
    {
        InitializeComponent();
        QueueList.ItemsSource = queue;
        InitializeWorkspaceChoices();
        RefreshControls();
        UpdatePreviewHeader();
    }

    private static void SetChoices<T>(ComboBox control, IEnumerable<(string Label, T Value)> choices)
    {
        foreach (var (label, value) in choices) control.Items.Add(new ComboBoxItem { Content = label, Tag = value });
        control.SelectedIndex = 0;
    }

    private static T Choice<T>(ComboBox control) => (T)((ComboBoxItem)control.SelectedItem).Tag;

    private VideoJob? SelectedJob => QueueList.SelectedItem as VideoJob;

    private StoryboardOptions Options() => new(GridChoice<int>(GridChoices), Choice<int>(ImageWidth),
        Choice<CardAspect>(AspectSize), GridChoice<CanvasTone>(ToneChoices), ShowTimestamps.IsChecked == true,
        ShowTitle.IsChecked == true, ShowVideoDetails.IsChecked == true);

    private void CanOpen(object sender, CanExecuteRoutedEventArgs e) => e.CanExecute = operation is null;
    private void CanExport(object sender, CanExecuteRoutedEventArgs e) => e.CanExecute = operation is null && SelectedJob?.Preview is not null;
    private void CanCancel(object sender, CanExecuteRoutedEventArgs e) => e.CanExecute = operation is { IsCancellationRequested: false };

    private async void OpenVideo(object sender, ExecutedRoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "添加视频",
            Filter = "视频|*.mp4;*.mov;*.m4v;*.mkv;*.webm;*.avi;*.mpg;*.mpeg;*.ts;*.flv;*.wmv;*.3gp|所有文件|*.*",
            CheckFileExists = true,
            Multiselect = true,
        };
        if (dialog.ShowDialog(this) == true) await AddFilesAsync(dialog.FileNames);
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = operation is null && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        QueueDropTarget.Tag = e.Effects == DragDropEffects.Copy;
        e.Handled = true;
    }

    private void OnDragLeave(object sender, DragEventArgs e) => QueueDropTarget.Tag = false;

    private async void OnDrop(object sender, DragEventArgs e)
    {
        e.Handled = true;
        QueueDropTarget.Tag = false;
        if (operation is not null || e.Data.GetData(DataFormats.FileDrop) is not string[] { Length: > 0 } files) return;
        e.Effects = DragDropEffects.Copy;
        await AddFilesAsync(files);
    }

    private async Task AddFilesAsync(IEnumerable<string> paths)
    {
        if (operation is not null) return;
        var known = queue.Select(item => item.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
        VideoJob[] added;
        try { added = paths.Select(Path.GetFullPath).Where(known.Add).Select(path => new VideoJob(path)).ToArray(); }
        catch (Exception error) when (error is ArgumentException or IOException or NotSupportedException)
        {
            ReportStatus($"无法导入 · {FirstLine(error)}");
            return;
        }
        if (added.Length == 0) return;
        foreach (var item in added)
        {
            item.Ordinal = queue.Count + 1;
            queue.Add(item);
        }
        QueueList.SelectedItem = added[0];
        await GenerateAsync(added);
    }

    private async void GenerateQueue(object sender, RoutedEventArgs e)
    {
        if (operation is null && queue.Count > 0) await GenerateAsync(queue.ToArray());
    }

    private async Task GenerateAsync(IReadOnlyList<VideoJob> jobs)
    {
        generating = true;
        canPauseBetweenJobs = jobs.Count > 1;
        using var run = Begin("正在准备队列…");
        int ready = 0;
        int empty = 0;
        int failed = 0;
        try
        {
            var service = new StoryboardService(MediaTools.Locate());
            cache ??= Directory.CreateTempSubdirectory("ShotMap-");
            for (int index = 0; index < jobs.Count; index++)
            {
                run.Token.ThrowIfCancellationRequested();
                var item = jobs[index];
                var options = Options();
                int jobIndex = index;
                canPauseBetweenJobs = index + 1 < jobs.Count;
                activeJob = item;
                activeOptions = options;
                activeVideo = item.Preview?.Video;
                string prefix = $"{index + 1} / {jobs.Count} · {item.Name}";
                item.SetStatus("处理中", JobState.Processing);
                ReportStatus(prefix);
                UpdatePauseControls();
                if (SelectedJob == item) UpdatePreview();
                var progress = new Progress<ProcessingStage>(stage =>
                {
                    if (operation != run || activeJob != item || run.IsCancellationRequested || pauseRequested) return;
                    ReportStatus($"{prefix} · {StageText(stage)}");
                    if (SelectedJob == item) StageLabel.Text = StageText(stage);
                    ProgressBar.Value = (jobIndex + StageProgress(stage)) / jobs.Count;
                });
                var probed = new Progress<VideoInfo>(video =>
                {
                    if (operation != run || activeJob != item || run.IsCancellationRequested) return;
                    activeVideo = video;
                    SizeStage(null, null);
                });
                string next = Path.Combine(cache.FullName, $"{Guid.NewGuid():N}.png");
                try
                {
                    var result = await Task.Run(async () =>
                    {
                        var storyboard = await service.GenerateAsync(item.Path, options, progress, run.Token, probed).ConfigureAwait(false);
                        if (storyboard.Frames.Count == 0) return null;
                        var slots = new FrameStamp?[options.FrameCount];
                        for (int i = 0; i < storyboard.Frames.Count; i++) slots[i] = storyboard.Frames[i].Stamp;
                        return CachePreview(item, storyboard, options, slots, next, run.Token);
                    }, run.Token);
                    SetPreview(item, result);
                    if (result is null) empty++;
                    else ready++;
                }
                catch (OperationCanceledException) when (run.IsCancellationRequested)
                {
                    item.SetStatus(item.LastExport is not null ? "已保存" : item.Preview?.Label ?? "已取消，可重新生成",
                        item.Preview is null ? JobState.Queued : JobState.Completed);
                    throw;
                }
                catch (Exception error)
                {
                    if (!TryDelete(next) && File.Exists(next)) cacheBytes += new FileInfo(next).Length;
                    failed++;
                    item.SetStatus($"生成失败 · {FirstLine(error)}", JobState.Failed);
                }
                finally
                {
                    activeJob = null;
                    activeVideo = null;
                    if (SelectedJob == item) UpdatePreview();
                }
                ProgressBar.Value = (index + 1.0) / jobs.Count;
                if (pauseRequested && canPauseBetweenJobs) await WaitForResume(run.Token);
            }
            ReportStatus($"队列处理完成 · {ready} 个分镜 · {empty} 个无可用画面 · {failed} 个失败");
        }
        catch (OperationCanceledException) when (run.IsCancellationRequested)
        {
            ReportStatus($"已取消 · 本次已生成 {ready} 个分镜");
        }
        catch (Exception error)
        {
            ReportStatus($"无法启动队列 · {FirstLine(error)}");
        }
        finally { End(); }
    }

    private static JobPreview CachePreview(VideoJob item, Storyboard storyboard, StoryboardOptions options,
        FrameStamp?[] slots, string path, CancellationToken token)
    {
        var image = StoryboardImage.Render(storyboard, options, item.Name, token, slots);
        StoryboardImage.Export(image, item.Path, path, false, token);
        return new(path, image.PixelWidth, image.PixelHeight, storyboard.Frames.Count, new FileInfo(path).Length,
            options, storyboard.Video, storyboard.StartPts, slots);
    }

    private void SetPreview(VideoJob job, JobPreview? result)
    {
        var previous = job.Preview;
        long available = CacheLimit - cacheBytes + (previous?.Bytes ?? 0);
        if (result is not null && result.Bytes > available)
            throw new IOException("预览缓存已达 1 GiB，请先导出并移出部分已完成视频。");
        job.Preview = result;
        job.LastExport = null;
        if (previous is not null && TryDelete(previous.Path)) cacheBytes -= previous.Bytes;
        cacheBytes += result?.Bytes ?? 0;
        job.SetStatus(result?.Label ?? "没有可用画面", result is null ? JobState.Queued : JobState.Completed);
    }

    private async void EditFrames(object sender, RoutedEventArgs e)
    {
        if (editingFrames || operation is not null || SelectedJob is not { Preview: { } existing } item) return;
        FrameStamp?[] slots;
        editingFrames = true;
        RefreshControls();
        try
        {
            var dialog = new ManualFrameWindow(item.Path, existing) { Owner = this };
            if (dialog.ShowDialog() != true) return;
            slots = dialog.Selection;
        }
        catch (Exception error)
        {
            ReportStatus($"无法打开手动选帧 · {FirstLine(error)}");
            return;
        }
        finally
        {
            editingFrames = false;
            RefreshControls();
        }
        using var run = Begin("正在应用手动选帧…");
        string next = Path.Combine(cache!.FullName, $"{Guid.NewGuid():N}.png");
        try
        {
            var result = await Task.Run(async () =>
            {
                var service = new StoryboardService(MediaTools.Locate());
                var storyboard = await service.RecomposeAsync(item.Path, existing.Video, existing.StartPts,
                    slots.OfType<FrameStamp>().ToArray(), existing.Options, run.Token).ConfigureAwait(false);
                return CachePreview(item, storyboard, existing.Options, slots, next, run.Token);
            }, run.Token);
            SetPreview(item, result);
            ReportStatus($"已应用手动选帧 · {item.Name}");
            if (SelectedJob == item) UpdatePreview();
        }
        catch (OperationCanceledException) when (run.IsCancellationRequested) { ReportStatus("已取消手动选帧。"); }
        catch (Exception error)
        {
            if (!TryDelete(next) && File.Exists(next)) cacheBytes += new FileInfo(next).Length;
            ReportStatus($"无法应用选帧 · {FirstLine(error)}");
        }
        finally { End(); }
    }

    private static string StageText(ProcessingStage stage) => stage switch
    {
        ProcessingStage.Sample => "按时间采样",
        ProcessingStage.Select => "检查清晰度和画面差异",
        ProcessingStage.ReadSelected => "按实际时间戳读取画面",
        _ => "读取视频",
    };

    private static double StageProgress(ProcessingStage stage) => stage switch
    {
        ProcessingStage.Sample => 0.18,
        ProcessingStage.Select => 0.40,
        ProcessingStage.ReadSelected => 0.74,
        _ => 0.04,
    };

    private void SelectJob(object sender, SelectionChangedEventArgs e)
    {
        headerNotice = null;
        RefreshControls();
        UpdatePreview();
    }

    private void PreviousPreview(object sender, RoutedEventArgs e) => NavigatePreview(-1);
    private void NextPreview(object sender, RoutedEventArgs e) => NavigatePreview(1);

    private void NavigatePreview(int direction)
    {
        for (int index = QueueList.SelectedIndex + direction; index >= 0 && index < queue.Count; index += direction)
        {
            if (queue[index].Preview is null) continue;
            QueueList.SelectedIndex = index;
            QueueList.ScrollIntoView(queue[index]);
            break;
        }
    }

    private async void UpdatePreview()
    {
        RefreshNavigation();
        var job = SelectedJob;
        var result = job?.Preview;
        int revision = ++previewRevision;
        Preview.Source = null;
        UpdatePreviewHeader();
        bool processing = job is not null && job == activeJob;
        ProcessingPanel.Visibility = processing ? Visibility.Visible : Visibility.Collapsed;
        EmptyStage.Visibility = processing ? Visibility.Collapsed : Visibility.Visible;
        EmptyMark.Visibility = job is null ? Visibility.Visible : Visibility.Collapsed;
        EmptyTitle.Text = result is not null ? "正在载入预览…" : job?.Status ?? "把视频，编成一张分镜图";
        if (processing)
        {
            ShowProcessingGrid();
            return;
        }
        if (result is null) return;

        await previewReader.WaitAsync();
        try
        {
            if (revision != previewRevision) return;
            var image = await Task.Run(() => StoryboardImage.Load(result.Path, maxEdge: 1600));
            if (revision != previewRevision) return;
            Preview.Source = image;
            EmptyStage.Visibility = Visibility.Collapsed;
        }
        catch (Exception error)
        {
            if (revision == previewRevision) EmptyTitle.Text = $"无法载入预览 · {FirstLine(error)}";
        }
        finally { previewReader.Release(); }
    }

    private void RemoveJob(object sender, RoutedEventArgs e)
    {
        if (operation is not null || SelectedJob is not { } item) return;
        int index = QueueList.SelectedIndex;
        queue.Remove(item);
        if (item.Preview is { } result && TryDelete(result.Path)) cacheBytes -= result.Bytes;
        for (int i = index; i < queue.Count; i++) queue[i].Ordinal = i + 1;
        QueueList.SelectedIndex = Math.Min(index, queue.Count - 1);
        RefreshControls();
        ReportStatus(queue.Count > 0 ? "已移出所选视频。" : "");
    }

    private void ClearQueue(object sender, RoutedEventArgs e)
    {
        if (operation is not null || queue.Count == 0) return;
        foreach (var item in queue)
            if (item.Preview is { } result && TryDelete(result.Path)) cacheBytes -= result.Bytes;
        queue.Clear();
        RefreshControls();
        UpdatePreview();
        ReportStatus("");
    }

    private async void ExportImage(object sender, ExecutedRoutedEventArgs e)
    {
        if (operation is not null || SelectedJob is not { Preview: { } result } item) return;
        string extension = GridChoice<string>(FormatChoices);
        string? folder = Path.GetDirectoryName(item.Path);
        var dialog = new SaveFileDialog
        {
            Title = "导出分镜",
            Filter = "PNG 图片|*.png|JPG 图片|*.jpg|WebP 图片|*.webp",
            FilterIndex = extension switch { ".png" => 1, ".webp" => 3, _ => 2 },
            InitialDirectory = folder,
            FileName = Path.GetFileNameWithoutExtension(NextDestination(folder!, item.BaseName, extension)),
            AddExtension = true,
            OverwritePrompt = false,
        };
        if (dialog.ShowDialog(this) != true) return;
        string destination = dialog.FileName;
        bool overwrite = File.Exists(destination);
        if (overwrite && MessageBox.Show(this, $"替换现有文件「{Path.GetFileName(destination)}」？", "导出分镜",
            MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;

        using var run = Begin("正在导出分镜…");
        try
        {
            await Task.Run(() => Save(result, item.Path, destination, overwrite, run.Token), run.Token);
            item.LastExport = destination;
            item.SetStatus("已保存", JobState.Completed);
            ReportStatus($"已保存为 {Path.GetFileName(destination)}");
        }
        catch (OperationCanceledException) when (run.IsCancellationRequested) { ReportStatus("已取消导出，可重试。"); }
        catch (Exception error) { ReportStatus($"导出失败 · {FirstLine(error)}"); }
        finally { End(); }
    }

    private async void ExportBatch(object sender, RoutedEventArgs e)
    {
        if (operation is not null) return;
        var jobs = queue.Where(item => item.Preview is not null).ToArray();
        if (jobs.Length == 0) return;
        var dialog = new OpenFolderDialog
        {
            Title = "选择批量导出目录",
            InitialDirectory = Path.GetDirectoryName(jobs[0].Path),
        };
        if (dialog.ShowDialog(this) != true) return;

        string extension = GridChoice<string>(FormatChoices);
        using var run = Begin("正在批量导出…");
        int saved = 0;
        int failed = 0;
        try
        {
            for (int index = 0; index < jobs.Length; index++)
            {
                run.Token.ThrowIfCancellationRequested();
                var item = jobs[index];
                ReportStatus($"正在导出 {index + 1} / {jobs.Length} · {item.Name}");
                try
                {
                    string exported = await Task.Run(() =>
                    {
                        string destination = NextDestination(dialog.FolderName, item.BaseName, extension);
                        Save(item.Preview!, item.Path, destination, false, run.Token);
                        return destination;
                    }, run.Token);
                    item.LastExport = exported;
                    item.SetStatus("已保存", JobState.Completed);
                    saved++;
                }
                catch (Exception error) when (error is not OperationCanceledException)
                {
                    item.SetStatus($"导出失败 · {FirstLine(error)}", JobState.Failed);
                    failed++;
                }
                ProgressBar.Value = (index + 1.0) / jobs.Length;
            }
            ReportStatus($"批量导出完成 · 成功 {saved} 个 · 失败 {failed} 个");
        }
        catch (OperationCanceledException) when (run.IsCancellationRequested)
        {
            ReportStatus($"已取消批量导出 · 已保存 {saved} 个");
        }
        finally { End(); }
    }

    private static void Save(JobPreview result, string source, string destination, bool overwrite, CancellationToken token)
    {
        if (Path.GetExtension(destination).Equals(".webp", StringComparison.OrdinalIgnoreCase))
            StoryboardImage.ExportWebp(result.Path, source, destination, overwrite, token);
        else
            StoryboardImage.Export(StoryboardImage.Load(result.Path), source, destination, overwrite, token);
    }

    private static string NextDestination(string folder, string baseName, string extension)
    {
        string stem = baseName.Length > 200 ? baseName[..200] : baseName;
        for (int sequence = 1; ; sequence++)
        {
            string path = Path.Combine(folder, $"{stem}-shot-{sequence:000}{extension}");
            if (!File.Exists(path) && !Directory.Exists(path)) return path;
        }
    }

    private CancellationTokenSource Begin(string status)
    {
        operation = new CancellationTokenSource();
        headerNotice = null;
        ProgressBar.Value = 0;
        ReportStatus(status);
        UpdatePreviewHeader();
        RefreshControls();
        return operation;
    }

    private void End()
    {
        operation = null;
        activeOptions = null;
        generating = canPauseBetweenJobs = pauseRequested = false;
        headerNotice = StatusText.Text;
        RefreshControls();
        UpdatePreviewHeader();
        if (closeAfterOperation) Close();
    }

    private void RefreshControls()
    {
        bool idle = operation is null;
        QueueCount.Text = queue.Count.ToString();
        QueueDropTarget.Visibility = queue.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        QueueList.Visibility = ClearButton.Visibility = queue.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        GenerateLabel.Text = queue.Count > 1 ? $"生成 {queue.Count} 张分镜图" : "生成分镜图";
        GenerateButton.IsEnabled = idle && queue.Count > 0;
        BatchExportButton.IsEnabled = idle && queue.Any(item => item.Preview is not null);
        ClearButton.IsEnabled = idle;
        if (QueueList.ContextMenu.Items[0] is MenuItem remove) remove.IsEnabled = idle && SelectedJob is not null;
        ManualButton.IsEnabled = idle && !editingFrames && SelectedJob?.Preview is not null;
        Inspector.IsEnabled = idle || pauseGate is not null;
        PreviewFooter.Visibility = idle ? Visibility.Visible : Visibility.Collapsed;
        WorkFooter.Visibility = idle ? Visibility.Collapsed : Visibility.Visible;
        CancelLabel.Text = generating ? "停止本次生成" : "取消";
        UpdatePauseControls();
        RefreshNavigation();
        CommandManager.InvalidateRequerySuggested();
    }

    private void RefreshNavigation()
    {
        int selected = QueueList.SelectedIndex;
        int before = queue.Take(Math.Max(0, selected)).Count(job => job.Preview is not null);
        int after = queue.Skip(selected + 1).Count(job => job.Preview is not null);
        bool hasPreview = SelectedJob?.Preview is not null;
        int total = before + after + (hasPreview ? 1 : 0);
        PreviousButton.IsEnabled = before > 0;
        NextButton.IsEnabled = after > 0;
        PagePosition.Text = (hasPreview ? before + 1 : 0).ToString();
        PageTotal.Text = $" / {total}";
        Pager.Visibility = total > 0 ? Visibility.Visible : Visibility.Hidden;
        ManualButton.Visibility = hasPreview ? Visibility.Visible : Visibility.Hidden;
    }

    private void CancelOperation(object sender, ExecutedRoutedEventArgs e) => RequestCancellation();

    private void RequestCancellation()
    {
        if (operation is not { IsCancellationRequested: false } run) return;
        run.Cancel();
        ReportStatus("正在取消…");
        UpdatePauseControls();
        CommandManager.InvalidateRequerySuggested();
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (operation is null) return;
        e.Cancel = true;
        closeAfterOperation = true;
        RequestCancellation();
    }

    protected override void OnClosed(EventArgs e)
    {
        previewRevision++;
        if (cache is { Exists: true })
        {
            try
            {
                foreach (var file in cache.EnumerateFiles()) TryDelete(file.FullName);
                cache.Delete();
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        base.OnClosed(e);
    }

    private static bool TryDelete(string path)
    {
        try { File.Delete(path); return true; }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }

    private static string FirstLine(Exception error) => error.Message.Split('\n', 2)[0].Trim();
}
