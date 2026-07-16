import SceneKit
import SwiftUI

enum Product3DModelLoader {
    private static let bundleSubdirectories = [
        "Productos3D",
        "Productos3d",
    ]

    static func url(for resourceName: String) -> URL? {
        var candidates = [resourceName]
        if let mapped = filenameMap[resourceName] {
            candidates.append(mapped)
        }

        for name in candidates {
            for subdirectory in bundleSubdirectories {
                if let url = Bundle.main.url(
                    forResource: name,
                    withExtension: "glb",
                    subdirectory: subdirectory
                ) {
                    return url
                }
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "glb") {
                return url
            }
        }

        return Bundle.main.urls(forResourcesWithExtension: "glb", subdirectory: nil)?
            .first { $0.deletingPathExtension().lastPathComponent == resourceName }
    }

    static func preparedScene(named resourceName: String, autoRotate: Bool) -> SCNScene? {
        guard let url = url(for: resourceName),
              let sourceScene = try? SCNScene(
                url: url,
                options: [
                    SCNSceneSource.LoadingOption.checkConsistency: true,
                    SCNSceneSource.LoadingOption.createNormalsIfAbsent: true,
                ]
              )
        else {
            return nil
        }

        let scene = SCNScene()
        let modelNode = SCNNode()

        while let child = sourceScene.rootNode.childNodes.first {
            modelNode.addChildNode(child)
        }

        if modelNode.childNodes.isEmpty {
            modelNode.addChildNode(sourceScene.rootNode)
        }

        centerAndScale(modelNode)

        scene.rootNode.addChildNode(modelNode)

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 1000
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.05, 2.45)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 850
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1100
        keyLight.eulerAngles = SCNVector3(-0.55, 0.65, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .omni
        fillLight.light?.intensity = 900
        fillLight.position = SCNVector3(-1.2, 0.8, 1.8)
        scene.rootNode.addChildNode(fillLight)

        if autoRotate {
            let spin = SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 10)
            )
            modelNode.runAction(spin)
        }

        return scene
    }

    private static let filenameMap: [String: String] = [
        "TradersMarketEnergyFocus": "Traders Market Energy Focus",
        "NADPlus": "NAD +",
        "TradersRecoverySleepWellness": "Traders Recovery Sleep & Wellness",
    ]

    private static func centerAndScale(_ node: SCNNode) {
        var minVec = SCNVector3(x: .greatestFiniteMagnitude, y: .greatestFiniteMagnitude, z: .greatestFiniteMagnitude)
        var maxVec = SCNVector3(x: -.greatestFiniteMagnitude, y: -.greatestFiniteMagnitude, z: -.greatestFiniteMagnitude)
        var found = false

        node.enumerateChildNodes { child, _ in
            guard child.geometry != nil else { return }
            let (localMin, localMax) = child.boundingBox
            minVec.x = min(minVec.x, localMin.x)
            minVec.y = min(minVec.y, localMin.y)
            minVec.z = min(minVec.z, localMin.z)
            maxVec.x = max(maxVec.x, localMax.x)
            maxVec.y = max(maxVec.y, localMax.y)
            maxVec.z = max(maxVec.z, localMax.z)
            found = true
        }

        if !found {
            let (localMin, localMax) = node.boundingBox
            minVec = localMin
            maxVec = localMax
        }

        let size = SCNVector3(maxVec.x - minVec.x, maxVec.y - minVec.y, maxVec.z - minVec.z)
        let maxDimension = max(size.x, max(size.y, size.z))
        guard maxDimension > 0 else { return }

        let targetSize: Float = 1.0
        let scale = targetSize / maxDimension
        node.scale = SCNVector3(scale, scale, scale)

        let center = SCNVector3(
            minVec.x + size.x / 2,
            minVec.y + size.y / 2,
            minVec.z + size.z / 2
        )
        node.position = SCNVector3(-center.x * scale, -center.y * scale, -center.z * scale)
    }
}

struct Product3DModelView: UIViewRepresentable {
    let resourceName: String
    var allowsInteraction: Bool = false
    var autoRotate: Bool = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = allowsInteraction
        view.autoenablesDefaultLighting = true

        if let scene = Product3DModelLoader.preparedScene(
            named: resourceName,
            autoRotate: autoRotate
        ) {
            view.scene = scene
            if let camera = scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
                view.pointOfView = camera
            }
        }

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.allowsCameraControl = allowsInteraction
    }
}
