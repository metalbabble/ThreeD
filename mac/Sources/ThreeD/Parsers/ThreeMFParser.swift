import Foundation
import SceneKit
import ZIPFoundation
import os

private let logger = Logger(subsystem: "com.local.threedviewer", category: "ThreeMFParser")

enum ThreeMFParser {
    static func parse(url: URL) throws -> SCNScene {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            logger.error("Could not open \(url.lastPathComponent, privacy: .public) as a zip archive: \(String(describing: error), privacy: .public)")
            throw ThreeMFError.cannotOpenArchive
        }

        let rootPath = try findRootPath(in: archive)
        logger.debug("Root model path: \(rootPath, privacy: .public)")

        var modelCache: [String: ParsedModel] = [:]

        func loadModel(_ path: String) throws -> ParsedModel {
            if let cached = modelCache[path] { return cached }
            let data = try extractEntry(path, from: archive)
            let delegate = ThreeMFXMLDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            guard parser.parse() else {
                logger.error("XML parse error in \(path, privacy: .public): \(parser.parserError?.localizedDescription ?? "unknown", privacy: .public)")
                throw ThreeMFError.invalidXML(parser.parserError?.localizedDescription ?? "unknown")
            }
            let model = ParsedModel(objects: delegate.objects, buildItems: delegate.buildItems)
            logger.debug("Parsed \(path, privacy: .public): \(model.objects.count) object(s), \(model.buildItems.count) build item(s)")
            modelCache[path] = model
            return model
        }

        let rootModel = try loadModel(rootPath)
        if rootModel.objects.isEmpty && rootModel.buildItems.isEmpty {
            logger.warning("\(rootPath, privacy: .public) has no objects and no build items — likely malformed")
        }

        var allVertices: [SIMD3<Float>] = []
        var allTriangles: [(Int, Int, Int)] = []

        func addMesh(_ obj: ObjectDef, transform: Transform) {
            guard !obj.vertices.isEmpty, !obj.triangles.isEmpty else { return }
            let base = allVertices.count
            for v in obj.vertices { allVertices.append(transform.apply(v)) }
            for t in obj.triangles {
                guard t.0 < obj.vertices.count, t.1 < obj.vertices.count, t.2 < obj.vertices.count else { continue }
                allTriangles.append((base + t.0, base + t.1, base + t.2))
            }
        }

        func resolve(fileKey: String, objectId: String, transform: Transform, depth: Int) {
            guard depth < 32 else {
                logger.warning("Component recursion too deep, aborting at objectid=\(objectId, privacy: .public)")
                return
            }
            let model: ParsedModel
            do {
                model = try loadModel(fileKey)
            } catch {
                logger.error("Could not load referenced part \(fileKey, privacy: .public): \(String(describing: error), privacy: .public)")
                return
            }
            guard let obj = model.objects[objectId] else {
                logger.warning("objectid=\(objectId, privacy: .public) not found in \(fileKey, privacy: .public)")
                return
            }
            let vBefore = allVertices.count, tBefore = allTriangles.count
            addMesh(obj, transform: transform)
            let pad = String(repeating: "  ", count: depth)
            logger.debug("\(pad, privacy: .public)objectid=\(objectId, privacy: .public) in \(fileKey, privacy: .public): own mesh \(obj.vertices.count)v/\(obj.triangles.count)t -> added \(allVertices.count - vBefore)v/\(allTriangles.count - tBefore)t; \(obj.components.count) component(s); row0=\(String(describing: transform.row0), privacy: .public) row1=\(String(describing: transform.row1), privacy: .public) row2=\(String(describing: transform.row2), privacy: .public) t=\(String(describing: transform.translation), privacy: .public)")
            for comp in obj.components {
                let childFile = normalizedPath(comp.path) ?? fileKey
                resolve(fileKey: childFile, objectId: comp.objectId, transform: Transform.compose(transform, comp.transform), depth: depth + 1)
            }
        }

        for item in rootModel.buildItems {
            let fileKey = normalizedPath(item.path) ?? rootPath
            logger.debug("build item -> objectid=\(item.objectId, privacy: .public) path=\(item.path ?? "(same file)", privacy: .public)")
            resolve(fileKey: fileKey, objectId: item.objectId, transform: item.transform, depth: 0)
        }

        if allTriangles.isEmpty {
            logger.warning("No geometry resolved from build items — falling back to raw objects in root model")
            for (_, obj) in rootModel.objects { addMesh(obj, transform: .identity) }
        }

        logger.debug("Total resolved: \(allVertices.count) vertices, \(allTriangles.count) triangles")
        return buildScene(vertices: allVertices, triangles: allTriangles)
    }

    // MARK: - Archive helpers

    private static func findRootPath(in archive: Archive) throws -> String {
        let candidates = ["3D/3dmodel.model", "3d/3dmodel.model"]
        for path in candidates where archive[path] != nil {
            return path
        }
        for entry in archive where entry.path.hasSuffix(".model") {
            return entry.path
        }
        throw ThreeMFError.modelNotFound
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard var p = path else { return nil }
        if p.hasPrefix("/") { p.removeFirst() }
        return p
    }

    private static func extractEntry(_ path: String, from archive: Archive) throws -> Data {
        if let entry = archive[path] {
            return try extractEntry(entry, from: archive)
        }
        for entry in archive where entry.path.caseInsensitiveCompare(path) == .orderedSame {
            return try extractEntry(entry, from: archive)
        }
        throw ThreeMFError.modelNotFound
    }

    private static func extractEntry(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return data
    }

    // MARK: - Scene construction

    // 3MF stores no normals at all (unlike STL) — they must be derived from the
    // mesh. Per-face flat normals turn any local winding inconsistency in the
    // source mesh (common after CAD boolean/union operations) into a sharp,
    // visible lighting flip; averaging into smooth per-vertex normals is both
    // the conventional way to shade this data and far more forgiving of an
    // occasional bad triangle, since neighboring correct faces dominate the average.
    private static func buildScene(vertices: [SIMD3<Float>], triangles: [(Int, Int, Int)]) -> SCNScene {
        let scene = SCNScene()
        guard !vertices.isEmpty, !triangles.isEmpty else { return scene }

        var normals = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        var validTriangles: [(Int, Int, Int)] = []
        validTriangles.reserveCapacity(triangles.count)

        for (i1, i2, i3) in triangles {
            guard i1 < vertices.count, i2 < vertices.count, i3 < vertices.count else { continue }
            let p1 = vertices[i1], p2 = vertices[i2], p3 = vertices[i3]
            let faceNormal = cross(p2 - p1, p3 - p1)
            normals[i1] += faceNormal
            normals[i2] += faceNormal
            normals[i3] += faceNormal
            validTriangles.append((i1, i2, i3))
        }

        var degenerateCount = 0
        for i in normals.indices {
            let len = length(normals[i])
            if len > 0 {
                normals[i] /= len
            } else {
                degenerateCount += 1
                normals[i] = SIMD3(0, 0, 1)
            }
        }
        if degenerateCount > 0 {
            logger.warning("\(degenerateCount) vertices with a degenerate averaged normal (surrounding faces cancel out — possible inconsistent winding in source mesh)")
        }

        let geometry = STLParser.buildIndexedGeometry(vertices: vertices, normals: normals, triangles: validTriangles)
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
        return scene
    }
}

// MARK: - Transform (3MF 4x3 affine matrix)

struct Transform {
    static let identity = Transform(row0: SIMD3(1, 0, 0), row1: SIMD3(0, 1, 0), row2: SIMD3(0, 0, 1), translation: .zero)

    var row0, row1, row2, translation: SIMD3<Float>

    func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        p.x * row0 + p.y * row1 + p.z * row2 + translation
    }

    /// Composes two transforms so that `compose(outer, inner).apply(p) == outer.apply(inner.apply(p))`.
    static func compose(_ outer: Transform, _ inner: Transform) -> Transform {
        func linear(_ t: Transform, _ v: SIMD3<Float>) -> SIMD3<Float> {
            v.x * t.row0 + v.y * t.row1 + v.z * t.row2
        }
        return Transform(
            row0: linear(outer, inner.row0),
            row1: linear(outer, inner.row1),
            row2: linear(outer, inner.row2),
            translation: linear(outer, inner.translation) + outer.translation
        )
    }

    static func parse(_ s: String) -> Transform {
        let parts = s.split(separator: " ").compactMap { Float($0) }
        guard parts.count == 12 else { return .identity }
        return Transform(
            row0: SIMD3(parts[0], parts[1], parts[2]),
            row1: SIMD3(parts[3], parts[4], parts[5]),
            row2: SIMD3(parts[6], parts[7], parts[8]),
            translation: SIMD3(parts[9], parts[10], parts[11])
        )
    }
}

// MARK: - Parsed model structures

struct ObjectDef {
    var vertices: [SIMD3<Float>] = []
    var triangles: [(Int, Int, Int)] = []
    var components: [ComponentRef] = []
}

struct ComponentRef {
    var objectId: String
    var transform: Transform
    var path: String?
}

struct BuildItem {
    var objectId: String
    var transform: Transform
    var path: String?
}

struct ParsedModel {
    var objects: [String: ObjectDef]
    var buildItems: [BuildItem]
}

// MARK: - XML delegate

/// Parses a single .model XML file into its raw resource objects and build items.
/// Cross-file references (Production Extension `path` attributes) and instancing
/// (`<build><item>` / `<components><component>` transforms) are resolved afterwards
/// in `ThreeMFParser.parse`, since an object can be referenced before or after its
/// own definition appears in the document, and referenced objects may live in a
/// different archive entry entirely.
final class ThreeMFXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var objects: [String: ObjectDef] = [:]
    private(set) var buildItems: [BuildItem] = []

    private var currentObjectId: String?
    private var objVertices: [SIMD3<Float>] = []
    private var objTriangles: [(Int, Int, Int)] = []
    private var objComponents: [ComponentRef] = []
    private var inMesh = false

    private func attrValue(_ attr: [String: String], suffix: String) -> String? {
        if let v = attr[suffix] { return v }
        for (k, v) in attr where k.hasSuffix(":" + suffix) { return v }
        return nil
    }

    func parser(_ parser: XMLParser,
                didStartElement element: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes attr: [String: String]) {
        switch element {
        case "object":
            currentObjectId = attr["id"]
            objVertices.removeAll(keepingCapacity: true)
            objTriangles.removeAll(keepingCapacity: true)
            objComponents.removeAll(keepingCapacity: true)
        case "mesh":
            inMesh = true
        case "vertex" where inMesh:
            let x = Float(attr["x"] ?? "") ?? 0
            let y = Float(attr["y"] ?? "") ?? 0
            let z = Float(attr["z"] ?? "") ?? 0
            objVertices.append(SIMD3(x, y, z))
        case "triangle" where inMesh:
            if let v1 = Int(attr["v1"] ?? ""), let v2 = Int(attr["v2"] ?? ""), let v3 = Int(attr["v3"] ?? "") {
                objTriangles.append((v1, v2, v3))
            }
        case "component":
            guard currentObjectId != nil, let objectId = attr["objectid"] else { break }
            let transform = attr["transform"].map(Transform.parse) ?? .identity
            let path = attrValue(attr, suffix: "path")
            objComponents.append(ComponentRef(objectId: objectId, transform: transform, path: path))
        case "item":
            guard let objectId = attr["objectid"] else { break }
            let transform = attr["transform"].map(Transform.parse) ?? .identity
            let path = attrValue(attr, suffix: "path")
            buildItems.append(BuildItem(objectId: objectId, transform: transform, path: path))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement element: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        switch element {
        case "mesh":
            inMesh = false
        case "object":
            if let id = currentObjectId {
                objects[id] = ObjectDef(vertices: objVertices, triangles: objTriangles, components: objComponents)
            }
            currentObjectId = nil
        default:
            break
        }
    }
}

// MARK: - Errors

enum ThreeMFError: LocalizedError {
    case cannotOpenArchive
    case modelNotFound
    case invalidXML(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenArchive:   return "Could not open 3MF archive."
        case .modelNotFound:       return "No 3D model found inside the 3MF file."
        case .invalidXML(let msg): return "3MF XML parse error: \(msg)"
        }
    }
}
