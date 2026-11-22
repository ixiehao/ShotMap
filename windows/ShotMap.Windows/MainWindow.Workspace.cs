using System.Diagnostics;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using ShotMap.Core;

namespace ShotMap.Windows;

public partial class MainWindow
{
    private (bool Queue, bool Inspector)? panelsBeforeFocus;
    private string? headerNotice;

    private void InitializeWorkspaceChoices()
    {
        for (int side = 3; side <= 8; side++)
        {
            string label = $"{side} × {side}";
            var digits = new TextBlock { Text = label, Height = 14, TextAlignment = TextAlignment.Center };
            var content = new StackPanel();
            content.Children.Add(new WorkspaceGridMark(side));
            content.Children.Add(digits);
            AddChoice(GridChoices, "GridChoice", "Grid", side, label, content, side == 3);
        }

        SetChoices(AspectSize, [("随视频", CardAspect.Source), ("横屏 16:9", CardAspect.Landscape),
            ("经典 4:3", CardAspect.Standard), ("方形 1:1", CardAspect.Square), ("竖屏 3:4", CardAspect.Vertical),
            ("竖屏 9:16", CardAspect.Portrait), ("超宽 21:9", CardAspect.UltraWide)]);
        SetChoices(ImageWidth, new[] { 1920, 2560, 3200, 3840 }.Select(width =>
            ($"{width.ToString("N0", CultureInfo.InvariantCulture)} px", width)));

        (CanvasTone Tone, string Title)[] tones = [(CanvasTone.White, "纯白色"), (CanvasTone.Ivory, "暖象牙白"),
            (CanvasTone.Mist, "雾蓝"), (CanvasTone.Evergreen, "深松绿"), (CanvasTone.Navy, "深海军蓝"), (CanvasTone.Cinema, "影院黑")];
        foreach (var (tone, title) in tones)
        {
            var swatch = AddChoice(ToneChoices, "Swatch", "Background", tone, title, null, tone == CanvasTone.Ivory);
            swatch.Background = new SolidColorBrush(StoryboardImage.BackgroundColor(tone));
            swatch.Foreground = tone is CanvasTone.White or CanvasTone.Ivory or CanvasTone.Mist
                ? (Brush)FindResource("Accent") : Brushes.White;
        }
    }

    private RadioButton AddChoice(Panel panel, string style, string group, object value, string label, object? content, bool selected)
    {
        var choice = new RadioButton
        {
            Style = (Style)FindResource(style), GroupName = group, Tag = value,
            Content = content, IsChecked = selected, ToolTip = label,
        };
        AutomationProperties.SetName(choice, label);
        panel.Children.Add(choice);
        return choice;
    }

    private static T GridChoice<T>(Panel panel)
        => (T)panel.Children.OfType<RadioButton>().Single(choice => choice.IsChecked == true).Tag;

    private void SelectFormat(object sender, RoutedEventArgs e)
    {
        if (SaveLabel is not null && sender is RadioButton { Content: string format })
            SaveLabel.Text = $"另存为 {format}";
    }

    private void TogglePanel(object sender, RoutedEventArgs e)
    {
        panelsBeforeFocus = null;
        ApplyPanelVisibility();
    }

    private void ToggleFocus(object sender, RoutedEventArgs e)
    {
        if (FocusToggle.IsChecked == true)
        {
            panelsBeforeFocus = (QueueToggle.IsChecked == true, InspectorToggle.IsChecked == true);
            QueueToggle.IsChecked = InspectorToggle.IsChecked = false;
        }
        else
        {
            var previous = panelsBeforeFocus ?? (Queue: true, Inspector: true);
            QueueToggle.IsChecked = previous.Queue;
            InspectorToggle.IsChecked = previous.Inspector;
            panelsBeforeFocus = null;
        }
        ApplyPanelVisibility();
    }

    private void ApplyPanelVisibility()
    {
        bool queueVisible = QueueToggle.IsChecked == true;
        bool inspectorVisible = InspectorToggle.IsChecked == true;
        QueueColumn.Width = new GridLength(queueVisible ? 190 : 0);
        QueueRule.Width = new GridLength(queueVisible ? 1 : 0);
        QueuePanel.Visibility = queueVisible ? Visibility.Visible : Visibility.Collapsed;
        InspectorColumn.Width = new GridLength(inspectorVisible ? 216 : 0);
        InspectorRule.Width = new GridLength(inspectorVisible ? 1 : 0);
        InspectorPanel.Visibility = inspectorVisible ? Visibility.Visible : Visibility.Collapsed;
        GenerateDock.Width = inspectorVisible ? 217 : 158;
        GenerateRule.Visibility = inspectorVisible ? Visibility.Visible : Visibility.Collapsed;
        MinWidth = queueVisible && inspectorVisible ? 736 : queueVisible || inspectorVisible ? 616 : 496;

        bool focused = !queueVisible && !inspectorVisible;
        FocusToggle.IsChecked = focused;
        FocusGlyph.Content = FindResource(focused ? "minimize" : "maximize");
        string label = focused ? "恢复面板" : "专注预览";
        FocusToggle.ToolTip = label;
        AutomationProperties.SetName(FocusToggle, label);
    }

    private void ClipSwatches(object sender, SizeChangedEventArgs e)
    {
        if (sender is Border border)
            border.Clip = new RectangleGeometry(new Rect(e.NewSize), 5, 5);
    }

    private void SizeWorkspace(object sender, SizeChangedEventArgs e)
        => BrandTitle.Visibility = e.NewSize.Width < 650 ? Visibility.Collapsed : Visibility.Visible;

    private void ReportStatus(string status)
    {
        StatusText.Text = status;
        if (operation is not null) return;
        headerNotice = status.Length == 0 ? null : status;
        UpdatePreviewHeader();
    }

    private void UpdatePreviewHeader()
    {
        var job = SelectedJob;
        var result = job?.Preview;
        var saved = job?.LastExport;
        SourceName.Text = headerNotice ?? (saved is not null ? $"已保存为 {Path.GetFileName(saved)}"
            : result is not null ? $"{job!.Name} · {result.Width} × {result.Height}" : job?.Name ?? "");
        SourceName.ToolTip = headerNotice ?? (job is null ? SourceName.Text : $"{job.Name} · {job.Status}");
        SaveButton.Visibility = operation is null && result is not null ? Visibility.Visible : Visibility.Collapsed;
        RevealButton.Visibility = operation is null && saved is not null ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RevealExport(object sender, RoutedEventArgs e)
    {
        if (SelectedJob?.LastExport is not { } saved) return;
        if (!File.Exists(saved))
        {
            SelectedJob.LastExport = null;
            ReportStatus("已保存的图片已移动或删除。");
            return;
        }
        string explorer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe");
        try { Process.Start(new ProcessStartInfo(explorer, $"/select,\"{saved}\""))?.Dispose(); }
        catch (Win32Exception error) { ReportStatus($"无法打开资源管理器 · {FirstLine(error)}"); }
    }

    private void ShowProcessingGrid()
    {
        if (activeOptions is not { } options) return;
        StageLabel.Text = "正在生成分镜图…";
        ProcessingCells.Rows = ProcessingCells.Columns = options.GridSide;
        ProcessingCells.Children.Clear();
        for (int i = 0; i < options.FrameCount; i++)
        {
            ProcessingCells.Children.Add(new Border
            {
                Background = (Brush)FindResource("ProgressTile"),
                CornerRadius = new CornerRadius(4),
                Margin = new Thickness(2.5),
                Opacity = i == 0 ? 1 : 0.60,
            });
        }
        SizeStage(null, null);
    }

    private void SizeStage(object? sender, SizeChangedEventArgs? e)
    {
        if (activeOptions is not { } options || ProcessingPanel.Visibility != Visibility.Visible) return;
        double aspect = options.ResolveAspect(activeVideo?.Aspect ?? (16.0 / 9));
        double availableWidth = Math.Max(1, Stage.ActualWidth - 24);
        double availableHeight = Math.Max(1, Stage.ActualHeight - 50);
        double gaps = options.GridSide * 5;
        double contentWidth = Math.Max(1, Math.Min(availableWidth - gaps, (availableHeight - gaps) * aspect));
        ProcessingCells.Width = contentWidth + gaps;
        ProcessingCells.Height = contentWidth / aspect + gaps;
    }

    private void PauseOrResume(object sender, RoutedEventArgs e)
    {
        if (pauseGate is { } gate)
        {
            gate.TrySetResult();
            return;
        }
        if (!canPauseBetweenJobs || pauseRequested || operation is not { IsCancellationRequested: false }) return;
        pauseRequested = true;
        ReportStatus("将在当前视频完成后暂停。");
        UpdatePauseControls();
    }

    private async Task WaitForResume(CancellationToken token)
    {
        pauseGate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        ReportStatus("已暂停 · 修改后的设置用于尚未开始的视频");
        RefreshControls();
        try { await pauseGate.Task.WaitAsync(token); }
        finally
        {
            pauseGate = null;
            pauseRequested = false;
            RefreshControls();
        }
    }

    private void UpdatePauseControls()
    {
        bool paused = pauseGate is not null;
        PauseButton.Visibility = generating && canPauseBetweenJobs ? Visibility.Visible : Visibility.Collapsed;
        PauseButton.IsEnabled = operation is { IsCancellationRequested: false } && (paused || !pauseRequested);
        PauseGlyph.Content = FindResource(paused ? "player-play" : "player-pause");
        PauseLabel.Text = paused ? "继续生成" : pauseRequested ? "将在当前视频完成后暂停" : "当前视频完成后暂停";
    }
}

internal sealed class WorkspaceGridMark : FrameworkElement
{
    private static readonly DependencyProperty SelectedProperty = DependencyProperty.Register("Selected", typeof(bool?),
        typeof(WorkspaceGridMark), new FrameworkPropertyMetadata(false, FrameworkPropertyMetadataOptions.AffectsRender));
    private readonly int side;

    public WorkspaceGridMark(int side)
    {
        this.side = side;
        Width = Height = 30;
        Margin = new Thickness(0, 0, 0, 3);
        IsHitTestVisible = false;
        SetBinding(SelectedProperty, new Binding(nameof(RadioButton.IsChecked))
        {
            RelativeSource = new RelativeSource(RelativeSourceMode.FindAncestor, typeof(RadioButton), 1),
        });
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        bool selected = GetValue(SelectedProperty) is true;
        var fill = (Brush)FindResource(selected ? "Accent" : "GridInk");
        double scale = VisualTreeHelper.GetDpi(this).DpiScaleX;
        int pixels = (int)Math.Floor(RenderSize.Width * scale);
        double desiredGap = side switch { 3 => 3, 6 => 1, 7 => 1.5, _ => 2 };
        int gap = Math.Min((int)Math.Round(desiredGap * scale, MidpointRounding.AwayFromZero), (pixels - side) / (side - 1));
        int cell = Math.Max(1, (pixels - gap * (side - 1)) / side);
        int origin = (pixels - (cell * side + gap * (side - 1))) / 2;
        double edge = cell / scale;
        double radius = Math.Min(1, edge / 4);
        for (int row = 0; row < side; row++)
        for (int column = 0; column < side; column++)
        {
            double x = (origin + column * (cell + gap)) / scale;
            double y = (origin + row * (cell + gap)) / scale;
            drawingContext.DrawRoundedRectangle(fill, null, new Rect(x, y, edge, edge), radius, radius);
        }
    }
}
