using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Media3D;
using Microsoft.Win32;
using ThreeD.Importers;

namespace ThreeD;

public partial class MainWindow : Window
{
    private bool _loading;
    private Rect3D _modelBounds = Rect3D.Empty;

    public MainWindow()
    {
        InitializeComponent();
    }

    public void OpenFileWhenLoaded(string path)
    {
        if (IsLoaded)
            _ = OpenFileAsync(path);
        else
            Loaded += (_, _) => _ = OpenFileAsync(path);
    }

    private async Task OpenFileAsync(string path)
    {
        if (_loading) return;
        _loading = true;
        try
        {
            StatusText.Text = $"Loading {Path.GetFileName(path)}…";
            Mouse.OverrideCursor = Cursors.Wait;

            var model = await Task.Run(() => ModelLoader.Load(path));

            ModelRoot.Content = model;
            _modelBounds = model.Bounds;
            PositionGrid(model.Bounds);
            Viewport.ZoomExtents(_modelBounds, 0);

            var (vertices, triangles) = ModelLoader.CountStats(model);
            StatusText.Text = $"{Path.GetFileName(path)}  —  {triangles:N0} triangles, {vertices:N0} vertices";
            Title = $"{Path.GetFileName(path)} - ThreeD";
        }
        catch (Exception ex)
        {
            StatusText.Text = "Failed to load model.";
            MessageBox.Show(this, $"Could not load '{path}':\n\n{ex.Message}",
                "ThreeD", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            Mouse.OverrideCursor = null;
            _loading = false;
        }
    }

    private void PositionGrid(Rect3D bounds)
    {
        if (bounds.IsEmpty) return;

        double extent = Math.Max(Math.Max(bounds.SizeX, bounds.SizeY), 1e-3) * 1.6;
        double step = Math.Pow(10, Math.Floor(Math.Log10(extent / 10)));
        if (extent / step > 50) step *= 5;
        else if (extent / step > 20) step *= 2;

        double size = Math.Ceiling(extent / (step * 5)) * step * 5;
        GroundGrid.Length = size;
        GroundGrid.Width = size;
        GroundGrid.MinorDistance = step;
        GroundGrid.MajorDistance = step * 5;
        GroundGrid.Thickness = size / 2500;
        GroundGrid.Center = new Point3D(
            bounds.X + bounds.SizeX / 2,
            bounds.Y + bounds.SizeY / 2,
            bounds.Z - size / 1000);
    }

    private void OnOpenExecuted(object sender, ExecutedRoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = ModelLoader.DialogFilter };
        if (dialog.ShowDialog(this) == true)
            _ = OpenFileAsync(dialog.FileName);
    }

    private void OnResetView(object sender, RoutedEventArgs e)
    {
        if (_modelBounds.IsEmpty) Viewport.ZoomExtents(400);
        else Viewport.ZoomExtents(_modelBounds, 400);
    }

    private void OnGridToggled(object sender, RoutedEventArgs e)
    {
        if (Viewport == null || GroundGrid == null) return;
        bool show = GridToggle.IsChecked == true;
        bool present = Viewport.Children.Contains(GroundGrid);
        if (show && !present) Viewport.Children.Add(GroundGrid);
        else if (!show && present) Viewport.Children.Remove(GroundGrid);
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
            _ = OpenFileAsync(files[0]);
    }
}
