using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Media.Media3D;
using ThreeD.Importers;

namespace ThreeD;

/// <summary>Offscreen render of a model file to a PNG, for scripting and testing.</summary>
public static class Snapshot
{
    public static void Run(string modelPath, string outputPath, int width, int height)
    {
        var model = ModelLoader.Load(modelPath);

        var camera = new PerspectiveCamera { FieldOfView = 45, UpDirection = new Vector3D(0, 0, 1) };
        FitCamera(camera, model.Bounds);

        var lights = new Model3DGroup();
        lights.Children.Add(new AmbientLight(Color.FromRgb(60, 60, 60)));
        lights.Children.Add(new DirectionalLight(Color.FromRgb(200, 200, 195), new Vector3D(-0.5, -1, -0.6)));
        lights.Children.Add(new DirectionalLight(Color.FromRgb(90, 90, 100), new Vector3D(0.8, 0.6, 0.2)));

        var viewport = new Viewport3D { Camera = camera };
        viewport.Children.Add(new ModelVisual3D { Content = lights });
        viewport.Children.Add(new ModelVisual3D { Content = model });

        var root = new Border
        {
            Background = Brushes.White,
            Child = viewport,
            Width = width,
            Height = height,
        };
        root.Measure(new Size(width, height));
        root.Arrange(new Rect(0, 0, width, height));
        root.UpdateLayout();

        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(root);

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(outputPath);
        encoder.Save(stream);
    }

    private static void FitCamera(PerspectiveCamera camera, Rect3D bounds)
    {
        if (bounds.IsEmpty) bounds = new Rect3D(0, 0, 0, 1, 1, 1);

        var center = new Point3D(
            bounds.X + bounds.SizeX / 2,
            bounds.Y + bounds.SizeY / 2,
            bounds.Z + bounds.SizeZ / 2);
        double radius = Math.Max(
            new Vector3D(bounds.SizeX, bounds.SizeY, bounds.SizeZ).Length / 2, 1e-3);

        var direction = new Vector3D(-1, -1.3, -0.8);
        direction.Normalize();
        double distance = radius / Math.Tan(camera.FieldOfView * Math.PI / 360) * 1.15;

        camera.Position = center - direction * distance;
        camera.LookDirection = direction * distance;
    }
}
