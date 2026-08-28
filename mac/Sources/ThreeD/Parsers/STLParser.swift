import Foundation
import SceneKit
import os

private let logger = Logger(subsystem: "com.local.threedviewer", category: "STLParser")

enum STLParser {
    static func parse(url: URL) throws -> SCNScene {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        logger.debug("\(url.lastPathComponent, privacy: .public): \(data.count) bytes")
        guard data.count >= 84 else { throw STLError.tooSmall }

        let binary = isBinary(data)
        logger.debug("Detected as \(binary ? "binary" : "ASCII", privacy: .public)")
        let (vertices, normals) = binary ? try parseBinary(data) : try parseASCII(data)
        guard !vertices.isEmpty else { throw STLError.noGeometry }

        var nonFiniteCount = 0
        var lo = SIMD3<Float>(repeating: Float.infinity)
        var hi = SIMD3<Float>(repeating: -Float.infinity)
        for v in vertices {
            if !v.x.isFinite || !v.y.isFinite || !v.z.isFinite {
                nonFiniteCount += 1
                continue
            }
            lo = min(lo, v); hi = max(hi, v)
        }
        if nonFiniteCount > 0 {
            logger.warning("\(nonFiniteCount) vertices with NaN/Infinite coordinates")
        }
        logger.debug("\(vertices.count) vertices, \(vertices.count / 3) triangles, bbox lo=\(String(describing: lo), privacy: .public) hi=\(String(describing: hi), privacy: .public)")

        return buildScene(vertices: vertices, normals: normals)
    }

    // MARK: - Format detection

    /// Binary files: byte 80..83 = triangle count; file size = 84 + count*50.
    /// ASCII files: start with "solid" but may also binary-start with "solid" header.
    /// Size check is the reliable discriminator.
    private static func isBinary(_ data: Data) -> Bool {
        let triangleCount = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) }
        return data.count == 84 + Int(triangleCount) * 50
    }

    // MARK: - Binary parser

    private static func parseBinary(_ data: Data) throws -> ([SIMD3<Float>], [SIMD3<Float>]) {
        let count = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) })
        var vertices: [SIMD3<Float>] = []
        var normals:  [SIMD3<Float>] = []
        vertices.reserveCapacity(count * 3)
        normals.reserveCapacity(count * 3)

        data.withUnsafeBytes { raw in
            var offset = 84
            for _ in 0..<count {
                let n = SIMD3<Float>(
                    raw.loadUnaligned(fromByteOffset: offset,      as: Float.self),
                    raw.loadUnaligned(fromByteOffset: offset + 4,  as: Float.self),
                    raw.loadUnaligned(fromByteOffset: offset + 8,  as: Float.self)
                )
                offset += 12
                for _ in 0..<3 {
                    let v = SIMD3<Float>(
                        raw.loadUnaligned(fromByteOffset: offset,      as: Float.self),
                        raw.loadUnaligned(fromByteOffset: offset + 4,  as: Float.self),
                        raw.loadUnaligned(fromByteOffset: offset + 8,  as: Float.self)
                    )
                    vertices.append(v)
                    normals.append(n)
                    offset += 12
                }
                offset += 2  // attribute byte count
            }
        }

        return (vertices, normals)
    }

    // MARK: - ASCII parser

    private static func parseASCII(_ data: Data) throws -> ([SIMD3<Float>], [SIMD3<Float>]) {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw STLError.invalidFormat
        }

        var vertices: [SIMD3<Float>] = []
        var normals:  [SIMD3<Float>] = []
        var currentNormal = SIMD3<Float>.zero

        for line in text.utf8.split(separator: UInt8(ascii: "\n")) {
            let s = String(line)!.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("facet normal") {
                currentNormal = parseVec(s, wordOffset: 2)
            } else if s.hasPrefix("vertex") {
                vertices.append(parseVec(s, wordOffset: 1))
                normals.append(currentNormal)
            }
        }

        return (vertices, normals)
    }

    private static func parseVec(_ line: String, wordOffset: Int) -> SIMD3<Float> {
        let parts = line.split(separator: " ")
        guard parts.count >= wordOffset + 3 else { return .zero }
        return SIMD3<Float>(
            Float(parts[wordOffset])     ?? 0,
            Float(parts[wordOffset + 1]) ?? 0,
            Float(parts[wordOffset + 2]) ?? 0
        )
    }

    // MARK: - Scene construction

    static func buildScene(vertices: [SIMD3<Float>], normals: [SIMD3<Float>]) -> SCNScene {
        let scene = SCNScene()
        let geometry = buildGeometry(vertices: vertices, normals: normals)
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
        return scene
    }

    static func buildGeometry(vertices: [SIMD3<Float>], normals: [SIMD3<Float>]) -> SCNGeometry {
        // Center and normalise to a unit cube
        var lo = SIMD3<Float>(repeating:  Float.infinity)
        var hi = SIMD3<Float>(repeating: -Float.infinity)
        for v in vertices where v.x.isFinite && v.y.isFinite && v.z.isFinite {
            lo = min(lo, v); hi = max(hi, v)
        }
        let center   = (lo + hi) * 0.5
        let span     = hi - lo
        let maxSpan  = max(span.x, span.y, span.z)
        let invScale = maxSpan > 0 ? 1.0 / maxSpan : 1.0

        // SIMD3<Float> is padded to 16 bytes in memory, so it must be packed
        // component-by-component to match the 12-byte stride declared below.
        let (vertexData, normalData) = packVectors(vertices: vertices, normals: normals, center: center, invScale: invScale)

        let vertexSource = SCNGeometrySource(
            data: vertexData, semantic: .vertex,
            vectorCount: vertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        let normalSource = SCNGeometrySource(
            data: normalData, semantic: .normal,
            vectorCount: normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )

        var indices = (0..<Int32(vertices.count)).map { $0 }
        let indexData = Data(bytes: &indices, count: indices.count * 4)
        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles,
            primitiveCount: vertices.count / 3, bytesPerIndex: 4
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.materials = [defaultMaterial()]
        return geometry
    }

    /// Like `buildGeometry`, but keeps the shared/indexed vertex buffer (and
    /// whatever per-vertex normals the caller already computed) instead of
    /// expanding into a flat, non-indexed triangle soup with duplicated normals.
    static func buildIndexedGeometry(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], triangles: [(Int, Int, Int)]) -> SCNGeometry {
        var lo = SIMD3<Float>(repeating:  Float.infinity)
        var hi = SIMD3<Float>(repeating: -Float.infinity)
        for v in vertices where v.x.isFinite && v.y.isFinite && v.z.isFinite {
            lo = min(lo, v); hi = max(hi, v)
        }
        let center   = (lo + hi) * 0.5
        let span     = hi - lo
        let maxSpan  = max(span.x, span.y, span.z)
        let invScale = maxSpan > 0 ? 1.0 / maxSpan : 1.0

        let (vertexData, normalData) = packVectors(vertices: vertices, normals: normals, center: center, invScale: invScale)

        let vertexSource = SCNGeometrySource(
            data: vertexData, semantic: .vertex,
            vectorCount: vertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        let normalSource = SCNGeometrySource(
            data: normalData, semantic: .normal,
            vectorCount: normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )

        var indices: [Int32] = []
        indices.reserveCapacity(triangles.count * 3)
        for (i1, i2, i3) in triangles {
            indices.append(Int32(i1)); indices.append(Int32(i2)); indices.append(Int32(i3))
        }
        let indexData = Data(bytes: &indices, count: indices.count * 4)
        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles,
            primitiveCount: triangles.count, bytesPerIndex: 4
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.materials = [defaultMaterial()]
        return geometry
    }

    /// Packs vertices (centered/scaled) and normals into tightly packed
    /// 12-byte-per-vector buffers. SIMD3<Float> has a 16-byte memory layout
    /// (padded to 4 floats), so raw memory copies of it would not match the
    /// 12-byte stride the geometry sources declare.
    private static func packVectors(
        vertices: [SIMD3<Float>], normals: [SIMD3<Float>],
        center: SIMD3<Float>, invScale: Float
    ) -> (vertexData: Data, normalData: Data) {
        var vertexFloats = [Float]()
        var normalFloats = [Float]()
        vertexFloats.reserveCapacity(vertices.count * 3)
        normalFloats.reserveCapacity(normals.count * 3)

        for (v, n) in zip(vertices, normals) {
            let scaled = (v - center) * invScale
            vertexFloats.append(scaled.x); vertexFloats.append(scaled.y); vertexFloats.append(scaled.z)
            normalFloats.append(n.x); normalFloats.append(n.y); normalFloats.append(n.z)
        }

        let vertexData = vertexFloats.withUnsafeBufferPointer { Data(buffer: $0) }
        let normalData = normalFloats.withUnsafeBufferPointer { Data(buffer: $0) }
        return (vertexData, normalData)
    }

    static func defaultMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents  = NSColor(calibratedRed: 0.72, green: 0.72, blue: 0.78, alpha: 1)
        mat.specular.contents = NSColor(white: 0.4, alpha: 1)
        mat.shininess         = 30
        mat.isDoubleSided     = true
        mat.lightingModel     = .phong
        return mat
    }
}

enum STLError: LocalizedError {
    case tooSmall, invalidFormat, noGeometry
    var errorDescription: String? {
        switch self {
        case .tooSmall:      return "File is too small to be a valid STL."
        case .invalidFormat: return "Could not decode STL file."
        case .noGeometry:    return "STL file contains no geometry."
        }
    }
}
