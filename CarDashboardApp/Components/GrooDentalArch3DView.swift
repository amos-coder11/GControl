import SceneKit
import SwiftUI

struct GrooDentalArchParams: Equatable {
    var whiteness: Double = 0.82
    var alignment: Double = 0.7
    var archWidth: Double = 1.0
    var showLowerArch: Bool = true
}

struct GrooDentalArch3DView: UIViewRepresentable {
    var params: GrooDentalArchParams
    var allowsCameraControl: Bool = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = allowsCameraControl
        view.autoenablesDefaultLighting = false
        view.scene = GrooDentalArchSceneBuilder.makeScene(params: params)
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: true)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.allowsCameraControl = allowsCameraControl
        GrooDentalArchSceneBuilder.update(uiView.scene, params: params)
    }
}

enum GrooDentalArchSceneBuilder {
    private static let upperArchName = "upperArch"
    private static let lowerArchName = "lowerArch"

    static func makeScene(params: GrooDentalArchParams) -> SCNScene {
        let scene = SCNScene()

        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.01
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.15, 2.8)
        scene.rootNode.addChildNode(cameraNode)

        addLights(to: scene.rootNode)

        let upper = buildArch(isUpper: true, params: params)
        upper.name = upperArchName
        upper.position = SCNVector3(0, 0.08, 0)
        scene.rootNode.addChildNode(upper)

        let lower = buildArch(isUpper: false, params: params)
        lower.name = lowerArchName
        lower.position = SCNVector3(0, -0.12, 0)
        lower.isHidden = !params.showLowerArch
        scene.rootNode.addChildNode(lower)

        return scene
    }

    static func update(_ scene: SCNScene?, params: GrooDentalArchParams) {
        guard let scene else { return }
        scene.rootNode.childNode(withName: upperArchName, recursively: false)?.removeFromParentNode()
        scene.rootNode.childNode(withName: lowerArchName, recursively: false)?.removeFromParentNode()

        let upper = buildArch(isUpper: true, params: params)
        upper.name = upperArchName
        upper.position = SCNVector3(0, 0.08, 0)
        scene.rootNode.addChildNode(upper)

        let lower = buildArch(isUpper: false, params: params)
        lower.name = lowerArchName
        lower.position = SCNVector3(0, -0.12, 0)
        lower.isHidden = !params.showLowerArch
        scene.rootNode.addChildNode(lower)
    }

    private static func buildArch(isUpper: Bool, params: GrooDentalArchParams) -> SCNNode {
        let root = SCNNode()
        let toothCount = 14
        let spread = Float(0.62 * params.archWidth)
        let alignmentFactor = Float(1 - params.alignment * 0.35)
        let white = CGFloat(0.78 + params.whiteness * 0.2)

        for index in 0..<toothCount {
            let t = Float(index) / Float(toothCount - 1)
            let angle = (t - 0.5) * .pi * 0.92
            let radius = spread * (1 - abs(t - 0.5) * 0.18)
            let x = sin(angle) * radius
            let z = cos(angle) * radius * 0.55
            let yOffset = abs(t - 0.5) * alignmentFactor * 0.04

            let width: CGFloat = index == 6 || index == 7 ? 0.11 : (index == 5 || index == 8 ? 0.095 : 0.075)
            let height: CGFloat = index == 6 || index == 7 ? 0.14 : 0.11

            let tooth = SCNBox(width: width, height: height, length: 0.06, chamferRadius: 0.018)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: white, alpha: 1)
            material.specular.contents = UIColor.white
            material.shininess = 0.65
            tooth.materials = [material]

            let node = SCNNode(geometry: tooth)
            node.position = SCNVector3(x, isUpper ? -yOffset : yOffset, z)
            node.eulerAngles = SCNVector3(isUpper ? -0.25 : 0.25, angle * 0.35, 0)
            root.addChildNode(node)
        }

        let gum = SCNCapsule(capRadius: CGFloat(spread * 0.12), height: CGFloat(spread * 1.35))
        let gumMaterial = SCNMaterial()
        gumMaterial.diffuse.contents = UIColor(red: 0.88, green: 0.55, blue: 0.58, alpha: 1)
        gum.materials = [gumMaterial]
        let gumNode = SCNNode(geometry: gum)
        gumNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        gumNode.position = SCNVector3(0, isUpper ? -0.05 : 0.05, 0)
        gumNode.opacity = 0.35
        root.addChildNode(gumNode)

        return root
    }

    private static func addLights(to root: SCNNode) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 700
        root.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 950
        key.eulerAngles = SCNVector3(-0.6, 0.4, 0)
        root.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 650
        fill.position = SCNVector3(-1, 1, 2)
        root.addChildNode(fill)
    }
}
