using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Windows.Media;
using System.Windows.Media.Media3D;
using System.Xml;
using System.Xml.Linq;

namespace ThreeD.Importers;

/// <summary>
/// Reads the 3MF core spec (zip + XML), including build transforms, components,
/// base materials, and the production extension's p:path references used by
/// slicers like Bambu Studio that split objects into separate model parts.
/// </summary>
public class ThreeMfImporter
{
    private const string CoreNs = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02";
    private const string ProdNs = "http://schemas.microsoft.com/3dmanufacturing/production/2015/06";
    private const string ModelRelType = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel";
    private const int MaxComponentDepth = 32;

    private ZipArchive _zip = null!;
    private readonly Dictionary<string, ModelPart> _parts = new(StringComparer.OrdinalIgnoreCase);

    private sealed class ModelPart
    {
        public Dictionary<int, ObjectResource> Objects { get; } = new();
        public Dictionary<int, List<Color>> Materials { get; } = new();
        public List<ComponentRef> BuildItems { get; } = new();
    }

    private sealed class ObjectResource
    {
        public MeshGeometry3D? Mesh;
        public List<ComponentRef>? Components;
        public int? Pid;
        public int? Pindex;
    }

    private readonly record struct ComponentRef(int ObjectId, Matrix3D? Transform, string? PartPath);

    public Model3DGroup Load(string path)
    {
        using var zip = ZipFile.OpenRead(path);
        _zip = zip;
        _parts.Clear();

        var rootPath = FindRootModelPart(zip);
        var root = GetPart(rootPath);

        var group = new Model3DGroup();
        foreach (var item in root.BuildItems)
        {
            var model = BuildObject(item.PartPath ?? rootPath, item.ObjectId, item.Transform, 0);
            if (model != null) group.Children.Add(model);
        }

        // Fallback for files with no <build> section: show every mesh object.
        if (group.Children.Count == 0)
        {
            foreach (var id in root.Objects.Keys)
            {
                var model = BuildObject(rootPath, id, null, 0);
                if (model != null) group.Children.Add(model);
            }
        }
        return group;
    }

    private static string FindRootModelPart(ZipArchive zip)
    {
        var rels = zip.GetEntry("_rels/.rels");
        if (rels != null)
        {
            using var stream = rels.Open();
            var doc = XDocument.Load(stream);
            XNamespace ns = "http://schemas.openxmlformats.org/package/2006/relationships";
            var target = doc.Root?.Elements(ns + "Relationship")
                .FirstOrDefault(r => (string?)r.Attribute("Type") == ModelRelType)
                ?.Attribute("Target")?.Value;
            if (!string.IsNullOrEmpty(target))
                return target;
        }

        var entry = zip.Entries.FirstOrDefault(e =>
            e.FullName.EndsWith(".model", StringComparison.OrdinalIgnoreCase));
        return entry?.FullName
            ?? throw new InvalidDataException("Not a 3MF file: no 3D model part found in archive.");
    }

    private ModelPart GetPart(string partPath)
    {
        var key = partPath.TrimStart('/');
        if (_parts.TryGetValue(key, out var cached))
            return cached;

        var entry = _zip.GetEntry(key)
            ?? throw new InvalidDataException($"3MF archive is missing part '{partPath}'.");

        var part = ParsePart(entry);
        _parts[key] = part;
        return part;
    }

    private ModelPart ParsePart(ZipArchiveEntry entry)
    {
        var part = new ModelPart();
        using var stream = entry.Open();
        using var reader = XmlReader.Create(stream, new XmlReaderSettings
        {
            IgnoreComments = true,
            IgnoreWhitespace = true,
            IgnoreProcessingInstructions = true,
        });

        while (reader.Read())
        {
            if (reader.NodeType != XmlNodeType.Element || reader.NamespaceURI != CoreNs)
                continue;
            switch (reader.LocalName)
            {
                case "basematerials":
                    ParseBaseMaterials(reader, part);
                    break;
                case "object":
                    ParseObject(reader, part);
                    break;
                case "item":
                    var itemRef = ReadComponentRef(reader);
                    if (itemRef != null) part.BuildItems.Add(itemRef.Value);
                    break;
            }
        }
        return part;
    }

    private static void ParseBaseMaterials(XmlReader outer, ModelPart part)
    {
        if (!TryParseInt(outer.GetAttribute("id"), out int id)) return;
        var colors = new List<Color>();
        using (var reader = outer.ReadSubtree())
        {
            while (reader.Read())
            {
                if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "base")
                    colors.Add(ParseColor(reader.GetAttribute("displaycolor")));
            }
        }
        part.Materials[id] = colors;
    }

    private void ParseObject(XmlReader outer, ModelPart part)
    {
        if (!TryParseInt(outer.GetAttribute("id"), out int id)) return;

        var obj = new ObjectResource();
        if (TryParseInt(outer.GetAttribute("pid"), out int pid)) obj.Pid = pid;
        if (TryParseInt(outer.GetAttribute("pindex"), out int pindex)) obj.Pindex = pindex;

        using (var reader = outer.ReadSubtree())
        {
            while (reader.Read())
            {
                if (reader.NodeType != XmlNodeType.Element) continue;
                switch (reader.LocalName)
                {
                    case "mesh":
                        obj.Mesh = ParseMesh(reader);
                        break;
                    case "component":
                        obj.Components ??= new List<ComponentRef>();
                        var comp = ReadComponentRef(reader);
                        if (comp != null) obj.Components.Add(comp.Value);
                        break;
                }
            }
        }
        part.Objects[id] = obj;
    }

    private static MeshGeometry3D ParseMesh(XmlReader outer)
    {
        var positions = new Point3DCollection();
        var indices = new Int32Collection();

        using (var reader = outer.ReadSubtree())
        {
            while (reader.Read())
            {
                if (reader.NodeType != XmlNodeType.Element) continue;
                switch (reader.LocalName)
                {
                    case "vertex":
                        positions.Add(new Point3D(
                            ParseDouble(reader.GetAttribute("x")),
                            ParseDouble(reader.GetAttribute("y")),
                            ParseDouble(reader.GetAttribute("z"))));
                        break;
                    case "triangle":
                        if (TryParseInt(reader.GetAttribute("v1"), out int v1) &&
                            TryParseInt(reader.GetAttribute("v2"), out int v2) &&
                            TryParseInt(reader.GetAttribute("v3"), out int v3))
                        {
                            indices.Add(v1);
                            indices.Add(v2);
                            indices.Add(v3);
                        }
                        break;
                }
            }
        }

        var mesh = new MeshGeometry3D { Positions = positions, TriangleIndices = indices };
        mesh.Freeze();
        return mesh;
    }

    private static ComponentRef? ReadComponentRef(XmlReader reader)
    {
        if (!TryParseInt(reader.GetAttribute("objectid"), out int objectId))
            return null;
        Matrix3D? transform = ParseTransform(reader.GetAttribute("transform"));
        string? partPath = reader.GetAttribute("path", ProdNs);
        return new ComponentRef(objectId, transform, partPath);
    }

    private Model3D? BuildObject(string partPath, int id, Matrix3D? transform, int depth)
    {
        if (depth > MaxComponentDepth) return null;

        var part = GetPart(partPath);
        if (!part.Objects.TryGetValue(id, out var obj)) return null;

        Model3D result;
        if (obj.Mesh != null)
        {
            var material = ResolveMaterial(part, obj);
            result = new GeometryModel3D(obj.Mesh, material) { BackMaterial = material };
        }
        else if (obj.Components is { Count: > 0 })
        {
            var group = new Model3DGroup();
            foreach (var comp in obj.Components)
            {
                var child = BuildObject(comp.PartPath ?? partPath, comp.ObjectId, comp.Transform, depth + 1);
                if (child != null) group.Children.Add(child);
            }
            if (group.Children.Count == 0) return null;
            result = group;
        }
        else
        {
            return null;
        }

        if (transform.HasValue)
            result.Transform = new MatrixTransform3D(transform.Value);
        return result;
    }

    private static Material ResolveMaterial(ModelPart part, ObjectResource obj)
    {
        if (obj.Pid is int pid &&
            part.Materials.TryGetValue(pid, out var colors) &&
            colors.Count > 0)
        {
            int index = Math.Clamp(obj.Pindex ?? 0, 0, colors.Count - 1);
            return ModelLoader.CreateMaterial(colors[index]);
        }
        return ModelLoader.DefaultMaterial;
    }

    /// <summary>3MF transform: 12 numbers, rows of a 4x3 matrix (row-vector convention).</summary>
    private static Matrix3D? ParseTransform(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var p = value.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (p.Length != 12) return null;
        var m = new double[12];
        for (int i = 0; i < 12; i++) m[i] = ParseDouble(p[i]);
        return new Matrix3D(
            m[0], m[1], m[2], 0,
            m[3], m[4], m[5], 0,
            m[6], m[7], m[8], 0,
            m[9], m[10], m[11], 1);
    }

    /// <summary>displaycolor is #RRGGBB or #RRGGBBAA.</summary>
    private static Color ParseColor(string? value)
    {
        if (value is { Length: 7 or 9 } && value[0] == '#' &&
            uint.TryParse(value.AsSpan(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out uint hex))
        {
            if (value.Length == 7)
                return Color.FromRgb((byte)(hex >> 16), (byte)(hex >> 8), (byte)hex);
            return Color.FromArgb((byte)hex, (byte)(hex >> 24), (byte)(hex >> 16), (byte)(hex >> 8));
        }
        return Color.FromRgb(0xC8, 0xCC, 0xD2);
    }

    private static double ParseDouble(string? s) =>
        double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out double d) ? d : 0;

    private static bool TryParseInt(string? s, out int value) =>
        int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out value);
}
