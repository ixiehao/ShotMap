using System.Collections.Specialized;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using ShotMap.Windows;

internal static class DesktopDragCheck
{
    public static void Run(string[] files)
    {
        var paths = files.Select(Path.GetFullPath).ToArray();
        if (paths.Length == 0 || paths.Any(path => !File.Exists(path)))
            throw new ArgumentException("Choose one or more existing files for the drag source.");
        var thread = new Thread(() =>
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            var window = new MainWindow { Title = "ShotMap 拖放验收" };
            var source = new Border
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Background = Brushes.LightGoldenrodYellow,
                Padding = new Thickness(12, 6, 12, 6),
                Cursor = Cursors.Hand,
                Child = new TextBlock { Text = $"拖动这 {paths.Length} 个测试文件到预览区" },
            };
            Point? start = null;
            source.MouseLeftButtonDown += (_, e) =>
            {
                start = e.GetPosition(source);
                source.CaptureMouse();
            };
            source.MouseLeftButtonUp += (_, _) =>
            {
                start = null;
                source.ReleaseMouseCapture();
            };
            source.MouseMove += (_, e) =>
            {
                if (start is not { } origin || e.LeftButton != MouseButtonState.Pressed) return;
                Vector distance = e.GetPosition(source) - origin;
                if (Math.Abs(distance.X) < SystemParameters.MinimumHorizontalDragDistance &&
                    Math.Abs(distance.Y) < SystemParameters.MinimumVerticalDragDistance) return;
                start = null;
                source.ReleaseMouseCapture();
                var fileList = new StringCollection();
                fileList.AddRange(paths);
                var data = new DataObject();
                data.SetFileDropList(fileList);
                var effect = DragDrop.DoDragDrop(source, data, DragDropEffects.Copy);
                Console.WriteLine($"FileDrop {paths.Length} file(s): {effect}");
            };
            ((Grid)window.Content).Children.Add(source);
            app.Run(window);
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
    }
}
