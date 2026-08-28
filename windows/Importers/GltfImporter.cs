using System.Windows.Media;
using System.Windows.Media.Media3D;
using SharpGLTF.Schema2;

namespace ThreeD.Importers;

/// <summary>Converts a glTF/GLB scene (via SharpGLTF) into WPF 3D models.</summary>
public static class GltfImporter
{
    public static Model3DGroup Load(string path)
    {
        var root = ModelRoot.Load(path);
        var scene = root.DefaultScene ?? root.LogicalScenes.FirstOrDefault();

        var group = new Model3DGroup();
        if (scene != null)
        {
            foreach (var node in scene.VisualChildren)
                Visit(node, group);
        }

        // glTF is Y-up; the viewer is Z-up like 3MF/STL.
        group.Transform = new RotateTransform3D(
            new AxisAngleRotation3D(new Vector3D(1, 0, 0), 90));

        var result = new Model3DGroup();
        result.Children.Add(group);
        return result;
    }

    private static void Visit(Node node, Model3DGroup group)
    {
        if (node.Mesh != null)
        {
            var transform = new MatrixTransform3D(ToMatrix3D(node.WorldMatrix));
            foreach (var primitive in node.Mesh.Primitives)
            {
                var model = ConvertPrimitive(primitive);
                if (model != null)
                {
                    model.Transform = transform;
                    group.Children.Add(model);
                }
            }
        }
        foreach (var child in node.VisualChildren)
            Visit(child, group);
    }

    private static GeometryModel3D? ConvertPrimitive(MeshPrimitive primitive)
    {
        var positionAccessor = primitive.GetVertexAccessor("POSITION");
        if (positionAccessor == null) return null;

        var mesh = new MeshGeometry3D();
        foreach (var p in positionAccessor.AsVector3Array())
            mesh.Positions.Add(new Point3D(p.X, p.Y, p.Z));

        var normalAccessor = primitive.GetVertexAccessor("NORMAL");
        if (normalAccessor != null)
        {
            foreach (var n in normalAccessor.AsVector3Array())
                mesh.Normals.Add(new Vector3D(n.X, n.Y, n.Z));
        }

        foreach (var (a, b, c) in primitive.GetTriangleIndices())
        {
            mesh.TriangleIndices.Add(a);
            mesh.TriangleIndices.Add(b);
            mesh.TriangleIndices.Add(c);
        }
        if (mesh.TriangleIndices.Count == 0) return null;
        mesh.Freeze();

        var material = ModelLoader.CreateMaterial(GetBaseColor(primitive.Material));
        return new GeometryModel3D(mesh, material) { BackMaterial = material };
    }

    private static Color GetBaseColor(SharpGLTF.Schema2.Material? material)
    {
        var channel = material?.FindChannel("BaseColor");
        if (channel.HasValue)
        {
            var c = channel.Value.Color;
            return Color.FromArgb(
                (byte)Math.Clamp(c.W * 255, 0, 255),
                (byte)Math.Clamp(c.X * 255, 0, 255),
                (byte)Math.Clamp(c.Y * 255, 0, 255),
                (byte)Math.Clamp(c.Z * 255, 0, 255));
        }
        return Color.FromRgb(0xC8, 0xCC, 0xD2);
    }

    private static Matrix3D ToMatrix3D(System.Numerics.Matrix4x4 m) => new(
        m.M11, m.M12, m.M13, m.M14,
        m.M21, m.M22, m.M23, m.M24,
        m.M31, m.M32, m.M33, m.M34,
        m.M41, m.M42, m.M43, m.M44);
}
