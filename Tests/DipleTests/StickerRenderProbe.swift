import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import Diple

@MainActor
@Suite struct StickerRenderProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIPLE_RENDER_STICKERS"] != nil))
    func renderEveryStickerToDisk() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DIPLE_RENDER_STICKERS"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lid = ImageRenderer(content: LidView(items: StickerSheet.everySticker.prefix(10).enumerated().map {
            LidView.Item(id: "lid-\($0.offset)", artifact: $0.element, spot: $0.offset < 8 ? LidView.placement(for: "lid-\($0.offset)") : nil)
        }) { _, _ in }
            .frame(width: 620).padding(24).background(Color(white: 0.14)))
        lid.scale = 2
        if let cg = lid.cgImage {
            try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("lid.png"))
        }
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        for (i, a) in StickerSheet.everySticker.enumerated() {
            for (j, angle) in [0.35, 2.6].enumerated() {
                let scene = StickerShape.scene(a, caption: "2026-Q3 · sticker \(i + 1)/7")
                let sticker = scene.rootNode.childNode(withName: "sticker", recursively: true)!
                sticker.removeAllActions()
                sticker.eulerAngles = SCNVector3(j == 0 ? 0.1 : 0.05, j == 0 ? 0.25 : 2.7, 0)
                renderer.scene = scene
                let img = renderer.snapshot(atTime: 0, with: CGSize(width: 360, height: 360), antialiasingMode: .multisampling4X)
                let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
                try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(a.id)-\(j).png"))
            }
            let flat = ImageRenderer(content: ArtifactTile(artifact: a, side: 140).padding(10).background(Color(white: 0.16)))
            flat.scale = 2
            if let cg = flat.cgImage {
                try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
                    .write(to: dir.appendingPathComponent("\(a.id)-2d.png"))
            }
        }
    }
}
