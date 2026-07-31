using System.IO;
using System.Windows.Media;
using System.Windows.Media.Media3D;

namespace ThreeD.Importers;

/// <summary>Dispatches a file to the right importer and returns a frozen model.</summary>
public static class ModelLoader
{
    public const string DialogFilter =
        "3D models|*.3mf;*.stl;*.obj;*.objz;*.glb;*.gltf;*.ply;*.off;*.3ds;*.lwo|" +
        "All files (*.*)|*.*";

    public static Model3DGroup Load(string path)
    {
        var ext = Path.GetExtension(path).ToLowerInvariant();
        Model3DGroup model = ext switch
        {
            ".3mf" => new ThreeMfImporter().Load(path),
            ".glb" or ".gltf" => GltfImporter.Load(path),
            _ => LoadWithHelix(path),
        };

        if (model.Children.Count == 0)
            throw new InvalidDataException("No geometry found in file.");

        if (model.CanFreeze) model.Freeze();
        return model;
    }

    private static Model3DGroup LoadWithHelix(string path)
    {
        var importer = new HelixToolkit.Wpf.ModelImporter
        {
            DefaultMaterial = DefaultMaterial,
        };
        return importer.Load(path, null, true)
            ?? throw new InvalidDataException("File could not be read as a 3D model.");
    }

    public static readonly Material DefaultMaterial = CreateMaterial(Color.FromRgb(0xC8, 0xCC, 0xD2));

    public static Material CreateMaterial(Color color)
    {
        var group = new MaterialGroup();
        group.Children.Add(new DiffuseMaterial(new SolidColorBrush(color)));
        group.Children.Add(new SpecularMaterial(new SolidColorBrush(Color.FromArgb(0x50, 0xFF, 0xFF, 0xFF)), 40));
        group.Freeze();
        return group;
    }

    public static (int Vertices, int Triangles) CountStats(Model3D model)
    {
        int vertices = 0, triangles = 0;
        void Visit(Model3D m)
        {
            switch (m)
            {
                case Model3DGroup g:
                    foreach (var child in g.Children) Visit(child);
                    break;
                case GeometryModel3D { Geometry: MeshGeometry3D mesh }:
                    vertices += mesh.Positions.Count;
                    triangles += mesh.TriangleIndices.Count > 0
                        ? mesh.TriangleIndices.Count / 3
                        : mesh.Positions.Count / 3;
                    break;
            }
        }
        Visit(model);
        return (vertices, triangles);
    }
}
