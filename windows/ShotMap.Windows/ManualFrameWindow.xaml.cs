using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using ShotMap.Core;
using Path = System.IO.Path;

namespace ShotMap.Windows;

public partial class ManualFrameWindow : Window
{
    private static readonly Geometry PlayIcon = Geometry.Parse("M7 4v16l13 -8l-13 -8");
    private static readonly Geometry PauseIcon = Geometry.Parse(
        "M6 6a1 1 0 0 1 1 -1h2a1 1 0 0 1 1 1v12a1 1 0 0 1 -1 1h-2a1 1 0 0 1 -1 -1l0 -12 " +
        "M14 6a1 1 0 0 1 1 -1h2a1 1 0 0 1 1 1v12a1 1 0 0 1 -1 1h-2a1 1 0 0 1 -1 -1l0 -12");
    private readonly string path;
    private readonly JobPreview original;
    private readonly SortedDictionary<long, FrameStamp> selected = [];
    private readonly Dictionary<long, Card> manual = [];
    private readonly DispatcherTimer scrubTimer = new() { Interval = TimeSpan.FromMilliseconds(150) };
    private readonly DispatcherTimer playbackTimer = new() { Interval = TimeSpan.FromMilliseconds(100) };
    private Card[] overview = [];
    private Card? current;
    private CancellationTokenSource? pendingRead;
    private double? requestedPosition;
    private bool settingPosition;
    private bool closeRequested;
    private bool playing;
    private bool mediaOpened;
    private bool mediaFailed;
    private int batch;

    public static readonly DependencyProperty GalleryColumnsProperty = DependencyProperty.Register(nameof(GalleryColumns),
        typeof(int), typeof(ManualFrameWindow), new PropertyMetadata(4));
    public static readonly DependencyProperty GalleryHeightProperty = DependencyProperty.Register(nameof(GalleryHeight),
        typeof(double), typeof(ManualFrameWindow), new PropertyMetadata(164.0));
    public static readonly DependencyProperty ProgressWidthProperty = DependencyProperty.Register(nameof(ProgressWidth),
        typeof(double), typeof(ManualFrameWindow), new PropertyMetadata(6.0));

    public int GalleryColumns => (int)GetValue(GalleryColumnsProperty);
    public double GalleryHeight => (double)GetValue(GalleryHeightProperty);
    public double ProgressWidth => (double)GetValue(ProgressWidthProperty);

    internal ManualFrameWindow(string path, JobPreview original)
    {
        this.path = path;
        this.original = original;
        foreach (var stamp in original.Selected.OfType<FrameStamp>()) selected.Add(stamp.Pts, stamp);
        InitializeComponent();
        Title = Path.GetFileName(path);
        Timeline.Maximum = Math.Max(0.001, original.Video.Duration);
        EndTime.Text = StoryboardLayout.Timecode(original.Video.Duration);
        scrubTimer.Tick += CapturePosition;
        playbackTimer.Tick += PlaybackPosition;
        UpdateGallery();
    }

    internal FrameStamp?[] Selection
    {
        get
        {
            var stamps = new FrameStamp?[original.Options.FrameCount];
            int index = 0;
            foreach (var stamp in selected.Values) stamps[index++] = stamp;
            return stamps;
        }
    }

    private Brush Accent => (Brush)FindResource("Accent");
    private Brush Divider => (Brush)FindResource("Divider");
    private int Capacity => original.Options.FrameCount;
    private double Position(FrameStamp stamp) => Math.Max(0, stamp.TimeBase.Seconds(stamp.Pts - original.StartPts));
    private double Duration => original.Video.Duration;

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        LayoutChanged(sender, null);
        await LoadOverviewAsync(reset: false);
    }

    private async void Regenerate(object sender, RoutedEventArgs e)
    {
        StopPlayback();
        await LoadOverviewAsync(reset: true);
    }

    private async Task LoadOverviewAsync(bool reset)
    {
        int next = reset ? batch + 1 : batch;
        FrameStamp[] keep = reset ? [] : selected.Values.ToArray();
        await ReadAsync(
            async (service, token) => MakeCards(await service.ManualOverviewAsync(path, original.Video,
                keep, token, Capacity, next).ConfigureAwait(false), token),
            cards =>
            {
                if (reset) selected.Clear();
                batch = next;
                overview = cards;
                int count = Math.Min(12, overview.Length);
                Filmstrip.ItemsSource = Enumerable.Range(0, count)
                    .Select(i => overview[(int)((i + 0.5) * overview.Length / count)]).ToArray();
                UpdateGallery();
                if (overview.FirstOrDefault(card => selected.ContainsKey(card.Stamp.Pts)) is { } chosen) ShowFrame(chosen);
                else if (overview.FirstOrDefault() is { } first) ShowFrame(first);
                return cards.Length == 0 ? "没有可预览的画面。" : null;
            }, "正在读取候选画面…");
    }

    private async void SmartFill(object sender, RoutedEventArgs e)
    {
        StopPlayback();
        var chosen = selected.Keys.ToHashSet();
        var candidates = overview.Concat(manual.Values).Select(card => card.Frame).DistinctBy(frame => frame.Stamp.Pts).ToArray();
        await ReadAsync((_, token) => Task.FromResult(StoryboardService.SuggestManualSelection(candidates, chosen,
                original.StartPts, Duration, Capacity - chosen.Count, token)),
            stamps =>
            {
                foreach (var stamp in stamps) selected.TryAdd(stamp.Pts, stamp);
                UpdateGallery();
                return stamps.Length == 0 ? "没有更多符合条件的候选画面。" : null;
            }, "正在智能选帧…");
    }

    private void ToggleCandidate(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: Card card } || pendingRead is not null) return;
        StopPlayback();
        if (!selected.Remove(card.Stamp.Pts) && selected.Count < Capacity) selected.Add(card.Stamp.Pts, card.Stamp);
        ShowFrame(card);
        UpdateGallery();
    }

    private async void AddCurrentFrame(object sender, RoutedEventArgs e)
    {
        if (playing)
        {
            StopPlayback();
            await LoadPositionAsync(Timeline.Value, add: true);
        }
        else if (current is { } card && requestedPosition is null) RevealManualFrame(card);
    }

    private void RevealManualFrame(Card card)
    {
        var existing = (Gallery.ItemsSource as Card[])?.FirstOrDefault(c => c.Stamp.Pts == card.Stamp.Pts);
        if (existing is null)
        {
            if (manual.Count == 96) { ShowNotice("手动候选已达 96 张。当前选择仍可保存。"); return; }
            card.IsManual = true;
            manual.Add(card.Stamp.Pts, card);
            UpdateGallery();
        }
        var target = existing ?? card;
        Dispatcher.BeginInvoke(() =>
        {
            if (Gallery.ItemContainerGenerator.ContainerFromItem(target) is FrameworkElement element) element.BringIntoView();
        }, DispatcherPriority.Loaded);
    }

    private void UpdateGallery()
    {
        var gallery = overview.Concat(manual.Values).DistinctBy(card => card.Stamp.Pts).OrderBy(card => card.Stamp.Pts).ToArray();
        var numbers = selected.Keys.Select((pts, i) => (pts, i)).ToDictionary(pair => pair.pts, pair => pair.i + 1);
        foreach (var card in gallery) card.UpdateSelection(numbers.GetValueOrDefault(card.Stamp.Pts), selected.Count < Capacity);
        if (Gallery.ItemsSource is not Card[] currentGallery || !gallery.SequenceEqual(currentGallery)) Gallery.ItemsSource = gallery;
        SelectionCount.Text = $"{selected.Count} / {Capacity}";
        SelectionMarks.Visibility = selected.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        DrawTimeline();
        RefreshControls();
    }

    private void FilmstripClicked(object sender, MouseButtonEventArgs e)
        => QueuePosition(e.GetPosition(FilmstripArea).X / Math.Max(1, FilmstripArea.ActualWidth) * Duration);

    private void TimelineChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!settingPosition && IsLoaded) QueuePosition(e.NewValue);
    }

    private void QueuePosition(double seconds)
    {
        StopPlayback();
        current = null;
        requestedPosition = Math.Clamp(seconds, 0, Duration);
        pendingRead?.Cancel();
        SetPosition(requestedPosition.Value);
        if (overview.MinBy(card => Math.Abs(Position(card.Stamp) - requestedPosition.Value)) is { } nearest)
            FramePreview.Source = nearest.Image;
        scrubTimer.Stop();
        scrubTimer.Start();
        RefreshControls();
    }

    private async void CapturePosition(object? sender, EventArgs e)
    {
        scrubTimer.Stop();
        if (pendingRead is not null) return;
        if (requestedPosition is not { } seconds) return;
        requestedPosition = null;
        await LoadPositionAsync(seconds);
    }

    private Task LoadPositionAsync(double seconds, bool add = false) => ReadAsync(async (service, token) =>
    {
        long pts = StoryboardService.PtsAt(original.Video, original.StartPts, seconds);
        var frames = await service.ManualFramesFromAsync(path, original.Video, pts, token).ConfigureAwait(false);
        if (frames.Count == 0)
            frames = await service.ManualFramesBeforeAsync(path, original.Video, pts, 1, token).ConfigureAwait(false);
        return frames.Count == 0 ? null : MakeCard(frames[0], token);
    }, card =>
    {
        if (card is null) return "该时间附近没有画面。";
        ShowFrame(card);
        if (add) RevealManualFrame(card);
        return null;
    }, "正在定位…");

    private void SeekKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        e.Handled = true;
        if (!ParseTime(SeekTime.Text, out double target) || target > Duration)
        {
            ShowNotice($"请输入 00:00:00 至 {EndTime.Text} 之间的时间。");
            return;
        }
        QueuePosition(target);
    }

    private static bool ParseTime(string text, out double seconds)
    {
        seconds = 0;
        string[] pieces = text.Trim().Replace(',', '.').Split(':');
        if (pieces.Length is < 1 or > 3) return false;
        foreach (string piece in pieces)
        {
            if (!double.TryParse(piece, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out double value)
                || !double.IsFinite(value) || value < 0) return false;
            seconds = seconds * 60 + value;
        }
        return double.IsFinite(seconds);
    }

    private async void StepFrame(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string step } && int.TryParse(step, out int frames)) await StepAsync(frames);
    }

    private Task StepAsync(int step)
    {
        if (pendingRead is not null || requestedPosition is not null) return Task.CompletedTask;
        StopPlayback();
        long anchor = current?.Stamp.Pts ?? StoryboardService.PtsAt(original.Video, original.StartPts, Timeline.Value);
        return ReadAsync(async (service, token) =>
        {
            var candidates = step < 0
                ? await service.ManualFramesBeforeAsync(path, original.Video, anchor, -step, token).ConfigureAwait(false)
                : await service.ManualFramesFromAsync(path, original.Video, anchor + 1, token).ConfigureAwait(false);
            int index = step < 0 ? 0 : Math.Min(step - 1, candidates.Count - 1);
            return candidates.Count == 0 ? null : MakeCard(candidates[index], token);
        }, card =>
        {
            if (card is null) return step < 0 ? "已到视频开头。" : "已到视频末尾。";
            ShowFrame(card);
            return null;
        }, "正在读取相邻帧…");
    }

    private async Task ReadAsync<T>(Func<StoryboardService, CancellationToken, Task<T>> read,
        Func<T, string?> show, string waitingMessage)
    {
        if (pendingRead is not null) return;
        using var request = new CancellationTokenSource();
        pendingRead = request;
        RefreshControls();
        ShowNotice(waitingMessage);
        try
        {
            var result = await Task.Run(() => read(new StoryboardService(MediaTools.Locate()), request.Token), request.Token);
            request.Token.ThrowIfCancellationRequested();
            ShowNotice(show(result));
        }
        catch (OperationCanceledException) when (request.IsCancellationRequested) { }
        catch (Exception error) { ShowNotice(error.Message.Split('\n', 2)[0]); }
        finally
        {
            pendingRead = null;
            if (closeRequested) Close();
            else
            {
                if (requestedPosition is not null) scrubTimer.Start();
                RefreshControls();
            }
        }
    }

    private Card[] MakeCards(IReadOnlyList<VideoFrame> frames, CancellationToken token)
        => frames.DistinctBy(frame => frame.Stamp.Pts).Select(frame => MakeCard(frame, token)).ToArray();

    private Card MakeCard(VideoFrame frame, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var image = BitmapSource.Create(frame.Width, frame.Height, 96, 96, PixelFormats.Bgr24, null, frame.Bgr, frame.Width * 3);
        image.Freeze();
        return new Card(frame, image, Position(frame.Stamp));
    }

    private void ShowFrame(Card card)
    {
        current = card;
        FramePreview.Source = card.Image;
        SetPosition(Position(card.Stamp));
        ShowNotice(null);
    }

    private void SetPosition(double seconds)
    {
        settingPosition = true;
        Timeline.Value = Math.Clamp(seconds, 0, Timeline.Maximum);
        var time = TimeSpan.FromSeconds(Timeline.Value);
        SeekTime.Text = $"{(int)time.TotalHours:00}:{time.Minutes:00}:{time.Seconds:00}.{time.Milliseconds:000}";
        settingPosition = false;
        DrawPlayhead();
    }

    private void LayoutChanged(object sender, SizeChangedEventArgs? e)
    {
        if (Root is null || MonitorWidth is null || GalleryScroll is null) return;
        double height = Math.Clamp(Math.Floor(Root.ActualHeight * 0.4 - 22), 298, 320);
        Workspace.Height = height + 24;
        MonitorWidth.Width = new GridLength(Math.Clamp(Math.Min(height * original.Video.Aspect,
            Root.ActualWidth - 32 - 16 - 544), 220, 548));
        double width = Math.Max(1, Root.ActualWidth - 32 - SystemParameters.VerticalScrollBarWidth);
        double aspect = Math.Clamp(original.Video.Aspect, 1.0 / 3, 3);
        int columns = aspect < 0.85 ? Math.Clamp((int)((width + 12) / 192), 5, 6) : Math.Max(1, (int)((width + 12) / 272));
        SetValue(GalleryColumnsProperty, columns);
        SetValue(GalleryHeightProperty, Math.Max(1, (width - (columns - 1) * 12) / columns / aspect));
    }

    private void TimelineGeometryChanged(object sender, SizeChangedEventArgs e) => DrawTimeline();

    private void DrawTimeline()
    {
        if (SelectionMarks is null || FilmstripLines is null || Ticks is null || AddTrack is null) return;
        double width = FilmstripArea.ActualWidth;
        if (width <= 0) return;
        Ticks.Children.Clear();
        for (int i = 0; i <= 8; i++)
            Vertical(Ticks, i * (width - 1) / 8, 0, i % 2 == 0 ? 6 : 4, Divider, 1);
        DrawPlayhead();

        SelectionMarks.Children.Clear();
        var markers = selected.Values.Select((stamp, i) => new Marker(stamp, i + 1, Offset(Position(stamp), width))).ToArray();
        for (int start = 0; start < markers.Length;)
        {
            int end = start + 1;
            while (end < markers.Length && markers[end].X - markers[end - 1].X < 25) end++;
            DrawMarkerGroup(markers[start..end], width);
            start = end;
        }
    }

    private double Offset(double seconds, double width)
        => 6 + Math.Clamp(seconds / Math.Max(0.001, Duration), 0, 1) * Math.Max(0, width - 12);

    private void DrawPlayhead()
    {
        double width = FilmstripArea.ActualWidth;
        if (width <= 0) return;
        double playhead = Offset(Timeline.Value, width);
        SetValue(ProgressWidthProperty, playhead);
        double addWidth = AddButton.ActualWidth > 0 ? AddButton.ActualWidth : 85;
        Canvas.SetLeft(AddButton, Math.Clamp(playhead - addWidth / 2, 58, Math.Max(58, width - 58 - addWidth)));
        FilmstripLines.Children.Clear();
        Vertical(FilmstripLines, playhead, 0, FilmstripArea.ActualHeight, Accent, 2);
    }

    private void DrawMarkerGroup(Marker[] markers, double width)
    {
        var first = markers[0];
        string label = markers.Length == 1 ? first.Number.ToString() : $"{first.Number}–{markers[^1].Number}";
        double badgeWidth = markers.Length == 1 ? 20 : Math.Max(30, 8 + label.Length * 5);
        double center = Math.Clamp(markers.Average(marker => marker.X), badgeWidth / 2, Math.Max(badgeWidth / 2, width - badgeWidth / 2));
        foreach (var marker in markers)
            SelectionMarks.Children.Add(new Line { X1 = center, X2 = marker.X, Y1 = 17, Y2 = 24, Stroke = Accent, Opacity = 0.70 });
        var badge = new Button
        {
            Content = label, Width = badgeWidth, Height = 17, Padding = new Thickness(0),
            FontSize = 10, Style = (Style)FindResource("MarkerBadge"), BorderThickness = new Thickness(0),
            ToolTip = string.Join(" · ", markers.Select(marker => $"{marker.Number} {StoryboardLayout.Timecode(Position(marker.Stamp))}")),
        };
        badge.Click += (_, _) =>
        {
            if (markers.Length == 1) SeekMarker(first);
            else
            {
                var menu = new ContextMenu { PlacementTarget = badge };
                foreach (var marker in markers)
                {
                    var item = new MenuItem { Header = $"{marker.Number} · {StoryboardLayout.Timecode(Position(marker.Stamp))}" };
                    item.Click += (_, _) => SeekMarker(marker);
                    menu.Items.Add(item);
                }
                menu.IsOpen = true;
            }
        };
        Canvas.SetLeft(badge, center - badgeWidth / 2);
        SelectionMarks.Children.Add(badge);
    }

    private void SeekMarker(Marker marker)
    {
        if (pendingRead is not null || requestedPosition is not null) { QueuePosition(Position(marker.Stamp)); return; }
        StopPlayback();
        var card = (Gallery.ItemsSource as Card[])?.FirstOrDefault(c => c.Stamp.Pts == marker.Stamp.Pts);
        if (card is not null) ShowFrame(card);
        else QueuePosition(Position(marker.Stamp));
    }

    private static void Vertical(Canvas canvas, double x, double y, double height, Brush brush, double stroke)
        => canvas.Children.Add(new Line { X1 = x, X2 = x, Y1 = y, Y2 = y + height, Stroke = brush, StrokeThickness = stroke });

    private void ClipRoundedBorder(object sender, SizeChangedEventArgs e)
    {
        if (sender is Border border)
            border.Clip = new RectangleGeometry(new Rect(e.NewSize), border.CornerRadius.TopLeft, border.CornerRadius.TopLeft);
    }

    private void TogglePlayback(object sender, RoutedEventArgs e) => TogglePlayback();

    private void TogglePlayback()
    {
        if (playing) { StopPlayback(); QueuePosition(Timeline.Value); return; }
        if (pendingRead is not null || requestedPosition is not null || mediaFailed) return;
        playing = true;
        Player.Visibility = Visibility.Visible;
        FramePreview.Visibility = Visibility.Hidden;
        if (!mediaOpened)
        {
            Player.Source = new Uri(path);
            Player.Play();
        }
        else StartPreviewPlayer();
        PlayGlyph.Data = PauseIcon;
        AutomationProperties.SetName(PlayButton, "暂停");
        PlayButton.ToolTip = "暂停";
        RefreshControls();
    }

    private void PlaybackOpened(object sender, RoutedEventArgs e)
    {
        mediaOpened = true;
        if (playing) StartPreviewPlayer();
    }

    private void StartPreviewPlayer()
    {
        Player.Position = TimeSpan.FromSeconds(Timeline.Value >= Duration ? 0 : Timeline.Value);
        Player.Play();
        playbackTimer.Start();
    }

    private void PlaybackPosition(object? sender, EventArgs e)
    {
        if (playing && mediaOpened) SetPosition(Player.Position.TotalSeconds);
    }

    private void PlaybackEnded(object sender, RoutedEventArgs e)
    {
        StopPlayback();
        QueuePosition(Duration);
    }

    private void PlaybackFailed(object sender, ExceptionRoutedEventArgs e)
    {
        mediaFailed = true;
        StopPlayback();
        ShowNotice("系统无法播放此视频，仍可拖动时间轴或逐帧定位。");
        RefreshControls();
    }

    private void StopPlayback()
    {
        if (!playing) return;
        if (mediaOpened)
        {
            SetPosition(Player.Position.TotalSeconds);
            current = null;
        }
        Player.Pause();
        playbackTimer.Stop();
        playing = false;
        Player.Visibility = Visibility.Hidden;
        FramePreview.Visibility = Visibility.Visible;
        PlayGlyph.Data = PlayIcon;
        AutomationProperties.SetName(PlayButton, "播放");
        PlayButton.ToolTip = "播放";
        RefreshControls();
    }

    private void RefreshControls()
    {
        bool idle = pendingRead is null && requestedPosition is null;
        ShuffleButton.IsEnabled = idle;
        SmartButton.IsEnabled = idle && selected.Count < Capacity && overview.Length > 0;
        AddButton.IsEnabled = idle && (current is not null || playing);
        PlayButton.IsEnabled = idle && !mediaFailed;
        BackOne.IsEnabled = BackFive.IsEnabled = idle && Timeline.Value > 0;
        ForwardOne.IsEnabled = ForwardFive.IsEnabled = idle && Timeline.Value < Duration;
        ApplyButton.IsEnabled = idle && selected.Count > 0 && !selected.Keys.SequenceEqual(original.Selected.OfType<FrameStamp>().Select(s => s.Pts).Order());
    }

    private void ShowNotice(string? notice)
    {
        ReadStatus.Text = notice ?? "";
        Notice.Visibility = notice is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void EditorKeys(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.Control && ApplyButton.IsEnabled)
        {
            e.Handled = true;
            DialogResult = true;
        }
        else if (e.OriginalSource is TextBox || e.OriginalSource is Slider) return;
        else if (e.Key == Key.Left || e.Key == Key.Right)
        {
            e.Handled = true;
            await StepAsync((e.Key == Key.Left ? -1 : 1) * (Keyboard.Modifiers == ModifierKeys.Shift ? 5 : 1));
        }
        else if (e.Key == Key.Space && e.OriginalSource is not Button)
        {
            e.Handled = true;
            TogglePlayback();
        }
    }

    private void Apply(object sender, RoutedEventArgs e) => DialogResult = true;

    private void CancelActiveRead(object? sender, CancelEventArgs e)
    {
        scrubTimer.Stop();
        playbackTimer.Stop();
        Player.Close();
        if (pendingRead is null) return;
        e.Cancel = true;
        closeRequested = true;
        pendingRead.Cancel();
    }

    private sealed record Marker(FrameStamp Stamp, int Number, double X);

    private sealed class Card(VideoFrame frame, BitmapSource image, double position) : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler? PropertyChanged;
        public VideoFrame Frame { get; } = frame;
        public FrameStamp Stamp => Frame.Stamp;
        public BitmapSource Image { get; } = image;
        public string Timecode { get; } = StoryboardLayout.Timecode(position);
        public string AccessibilityLabel => $"{(IsManual ? "手动 · " : "")}{Timecode}{(IsSelected ? $" · 已选 {Number}" : "")}";
        public int Number { get; private set; }
        public bool IsSelected => Number > 0;
        public int BadgeFont => Number >= 10 ? 18 : 20;
        public bool IsManual { get; set; }
        public bool CanToggle { get; private set; }

        public void UpdateSelection(int number, bool available)
        {
            Number = number;
            CanToggle = available || number > 0;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));
        }
    }
}
