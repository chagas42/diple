import AppKit
import SceneKit
import Testing
@testable import Diple

@MainActor
@Suite struct StickerRenderProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIPLE_RENDER_STICKERS"] != nil))
    func renderEveryStickerToDisk() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DIPLE_RENDER_STICKERS"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        for (i, a) in Artifact.catalog.enumerated() {
            for (j, angle) in [0.35, 2.6].enumerated() {
                let scene = StickerShape.scene(a, caption: "2026-Q3 · sticker \(i + 1)/7")
                let sticker = scene.rootNode.childNodes.first!
                sticker.removeAllActions()
                sticker.eulerAngles = SCNVector3(-0.25, angle, 0.05)
                renderer.scene = scene
                scene.background.contents = NSColor(white: 0.12, alpha: 1)
                let img = renderer.snapshot(atTime: 0, with: CGSize(width: 360, height: 360), antialiasingMode: .multisampling4X)
                let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
                try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(a.id)-\(j).png"))
            }
        }
    }
}
