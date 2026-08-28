import SwiftUI
import SceneKit
import os

private let logger = Logger(subsystem: "com.local.threedviewer", category: "SceneKitViewWrapper")

struct SceneKitViewWrapper: NSViewRepresentable {
    let scene: SCNScene

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(white: 0.13, alpha: 1.0)

        // Subtle ground grid for spatial reference
        let camera = SCNCamera()
        camera.zFar = 10_000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3)
        view.pointOfView = cameraNode

        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.scene = scene
        frameScene(in: view)
    }

    // Position camera to frame the entire model
    private func frameScene(in view: SCNView) {
        guard let root = view.scene?.rootNode else { return }

        var minX = CGFloat.infinity,  minY = CGFloat.infinity,  minZ = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity, maxZ = -CGFloat.infinity

        root.enumerateChildNodes { node, _ in
            guard node.geometry != nil else { return }
            let (lo, hi) = node.boundingBox
            let wLo = node.convertPosition(lo, to: nil)
            let wHi = node.convertPosition(hi, to: nil)
            minX = min(minX, min(wLo.x, wHi.x)); maxX = max(maxX, max(wLo.x, wHi.x))
            minY = min(minY, min(wLo.y, wHi.y)); maxY = max(maxY, max(wLo.y, wHi.y))
            minZ = min(minZ, min(wLo.z, wHi.z)); maxZ = max(maxZ, max(wLo.z, wHi.z))
        }

        guard minX.isFinite else {
            logger.warning("No finite bounding box found; skipping camera framing")
            return
        }

        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let cz = (minZ + maxZ) / 2
        let dx = maxX - minX, dy = maxY - minY, dz = maxZ - minZ
        let radius   = (dx*dx + dy*dy + dz*dz).squareRoot() / 2
        let distance = radius * 2.2 + 0.001

        let cameraNode = view.pointOfView ?? {
            let n = SCNNode(); n.camera = SCNCamera()
            view.pointOfView = n; return n
        }()
        // The scene is replaced on every file load; re-parent the camera into
        // the current scene so it participates in the node graph.
        if cameraNode.parent !== root {
            cameraNode.removeFromParentNode()
            root.addChildNode(cameraNode)
        }

        // zNear/zFar must track the model's actual scale: STL/3MF geometry is
        // normalized to a unit cube, but GLB/glTF loads through SceneKit's native
        // loader untouched, and glTF's convention is meters — a small real-world
        // model can easily fall entirely inside a fixed default near plane (1.0),
        // clipping the whole object.
        let near = max(Double(radius) * 0.01, 0.0001)
        let far  = Double(distance + radius * 4)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cameraNode.position = SCNVector3(cx, cy, cz + distance)
        cameraNode.look(at: SCNVector3(cx, cy, cz))
        cameraNode.camera?.zNear = near
        cameraNode.camera?.zFar = far
        view.defaultCameraController.target = SCNVector3(cx, cy, cz)
        SCNTransaction.commit()

        logger.debug("bbox=[\(minX),\(minY),\(minZ)]-[\(maxX),\(maxY),\(maxZ)] center=(\(cx),\(cy),\(cz)) radius=\(radius) distance=\(distance) zNear=\(near) zFar=\(far)")
    }
}
