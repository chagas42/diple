import AppKit
import SceneKit

enum StickerShape {
    static let border = 1

    static func mask(_ a: Artifact) -> [[Bool]] {
        let n = a.pixels.count
        let solid = a.pixels.map { row in row.map { a.palette[$0] != nil } }
        let size = n + 2 * border
        var out = Array(repeating: Array(repeating: false, count: size), count: size)
        for y in 0..<n {
            for x in 0..<n where solid[y][x] {
                for dy in -border...border {
                    for dx in -border...border {
                        let yy = y + border + dy, xx = x + border + dx
                        if yy >= 0, yy < size, xx >= 0, xx < size { out[yy][xx] = true }
                    }
                }
            }
        }
        return out
    }

    struct Corner: Hashable {
        let x: Int
        let y: Int
    }

    static func outline(_ mask: [[Bool]]) -> [Corner] {
        let h = mask.count, w = mask.first?.count ?? 0
        func filled(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && mask[y][x] }
        var next: [Corner: Corner] = [:]
        for y in 0..<h {
            for x in 0..<w where mask[y][x] {
                if !filled(x, y - 1) { next[Corner(x: x, y: y)] = Corner(x: x + 1, y: y) }
                if !filled(x + 1, y) { next[Corner(x: x + 1, y: y)] = Corner(x: x + 1, y: y + 1) }
                if !filled(x, y + 1) { next[Corner(x: x + 1, y: y + 1)] = Corner(x: x, y: y + 1) }
                if !filled(x - 1, y) { next[Corner(x: x, y: y + 1)] = Corner(x: x, y: y) }
            }
        }
        var best: [Corner] = []
        var seen = Set<Corner>()
        for start in next.keys where !seen.contains(start) {
            var loop: [Corner] = []
            var cur = start
            while let n = next[cur], !seen.contains(cur) {
                seen.insert(cur)
                loop.append(cur)
                cur = n
            }
            if loop.count > best.count { best = loop }
        }
        return best
    }

    static func bounds(_ m: [[Bool]]) -> (x: Int, y: Int, w: Int, h: Int) {
        let rows = m.indices.filter { m[$0].contains(true) }
        let cols = (0..<(m.first?.count ?? 0)).filter { x in m.contains { $0[x] } }
        guard let r0 = rows.first, let r1 = rows.last, let c0 = cols.first, let c1 = cols.last else { return (0, 0, 1, 1) }
        return (c0, r0, c1 - c0 + 1, r1 - r0 + 1)
    }

    static func image(_ a: Artifact, cell: CGFloat = 32) -> NSImage {
        let m = mask(a)
        let b = bounds(m)
        return NSImage(size: NSSize(width: CGFloat(b.w) * cell, height: CGFloat(b.h) * cell), flipped: true) { _ in
            NSGraphicsContext.current?.cgContext.translateBy(x: -CGFloat(b.x) * cell, y: -CGFloat(b.y) * cell)
            NSColor.white.setFill()
            for (y, row) in m.enumerated() {
                for (x, on) in row.enumerated() where on {
                    NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell).fill()
                }
            }
            for (y, row) in a.pixels.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let hex = a.palette[ch] else { continue }
                    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                            green: CGFloat((hex >> 8) & 0xFF) / 255,
                            blue: CGFloat(hex & 0xFF) / 255, alpha: 1).setFill()
                    NSRect(x: CGFloat(x + border) * cell, y: CGFloat(y + border) * cell,
                           width: cell, height: cell).fill()
                }
            }
            return true
        }
    }

    static func back(_ a: Artifact, caption: String) -> NSImage {
        let size: CGFloat = 576
        return NSImage(size: NSSize(width: size, height: size), flipped: true) { r in
            NSColor(white: 0.93, alpha: 1).setFill()
            r.fill()
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let lines: [(String, CGFloat, NSFont.Weight)] = [
                ("DIPLE", 44, .heavy), (a.name, 30, .semibold), (caption, 24, .regular),
            ]
            var y = size * 0.36
            for (text, pt, weight) in lines {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: pt, weight: weight),
                    .foregroundColor: NSColor(white: 0.45, alpha: 1),
                    .paragraphStyle: para,
                ]
                (text as NSString).draw(in: NSRect(x: 30, y: y, width: size - 60, height: pt * 1.6), withAttributes: attrs)
                y += pt * 1.7
            }
            return true
        }
    }

    static func node(_ a: Artifact, caption: String) -> SCNNode {
        let m = mask(a)
        let n = CGFloat(m.count)
        let pts = outline(m)
        let path = NSBezierPath()
        for (i, p) in pts.enumerated() {
            let q = NSPoint(x: CGFloat(p.x) - n / 2, y: n / 2 - CGFloat(p.y))
            if i == 0 { path.move(to: q) } else { path.line(to: q) }
        }
        path.close()
        path.flatness = 0.1
        let shape = SCNShape(path: path, extrusionDepth: 0.14)
        shape.chamferRadius = 0.05

        let front = SCNMaterial()
        front.diffuse.contents = image(a)
        front.diffuse.magnificationFilter = .nearest
        front.lightingModel = .physicallyBased
        front.roughness.contents = 0.55
        front.metalness.contents = 0.0
        front.clearCoat.contents = 0.7
        front.clearCoatRoughness.contents = 0.18
        if a.rarity >= .rare { front.shaderModifiers = [.fragment: holo] }

        let back = SCNMaterial()
        back.diffuse.contents = StickerShape.back(a, caption: caption)
        back.lightingModel = .physicallyBased
        back.roughness.contents = 0.8

        let edge = SCNMaterial()
        edge.diffuse.contents = NSColor(white: 0.97, alpha: 1)
        edge.lightingModel = .physicallyBased
        edge.roughness.contents = 0.6

        shape.materials = [front, back, edge, edge]
        let node = SCNNode(geometry: shape)
        node.scale = SCNVector3(0.1, 0.1, 0.1)
        return node
    }

    static let holo = """
    float3 v = normalize(_surface.view);
    float3 nn = normalize(_surface.normal);
    float f = pow(1.0 - abs(dot(v, nn)), 1.2);
    float h = fract(dot(v.xy, float2(1.7, 2.3)) + f * 1.5);
    float3 rainbow = 0.5 + 0.5 * cos(6.2831 * (h + float3(0.0, 0.33, 0.67)));
    _output.color.rgb = mix(_output.color.rgb, _output.color.rgb * (0.85 + rainbow * 0.3), 0.12 + 0.3 * f);
    """

    static func backdrop(_ rarity: Rarity) -> NSImage {
        let size: CGFloat = 1024
        let glow = NSColor(rarity.color).usingColorSpace(.sRGB) ?? .white
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            NSColor(srgbRed: 0.06, green: 0.06, blue: 0.08, alpha: 1).setFill()
            r.fill()
            let colors = [glow.withAlphaComponent(0.34).cgColor, glow.withAlphaComponent(0.08).cgColor, NSColor.clear.cgColor] as CFArray
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]),
               let ctx = NSGraphicsContext.current?.cgContext {
                let c = CGPoint(x: size / 2, y: size * 0.56)
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size * 0.55, options: [])
            }
            return true
        }
    }

    static func scene(_ a: Artifact, caption: String) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = backdrop(a.rarity)

        let floor = SCNPlane(width: 12, height: 12)
        let catcher = SCNMaterial()
        catcher.lightingModel = .shadowOnly
        floor.materials = [catcher]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, 0, -0.02)
        scene.rootNode.addChildNode(floorNode)

        let holder = SCNNode()
        let sticker = node(a, caption: caption)
        sticker.name = "sticker"
        sticker.position = SCNVector3(0, 0, 0.32)
        holder.addChildNode(sticker)
        holder.eulerAngles = SCNVector3(0, 0, CGFloat(ArtifactTile.tilt(a)) * .pi / 180)
        let sway = SCNAction.repeatForever(.sequence([
            .rotateTo(x: 0.09, y: 0.14, z: 0, duration: 2.6, usesShortestUnitArc: true),
            .rotateTo(x: -0.09, y: -0.14, z: 0, duration: 2.6, usesShortestUnitArc: true),
        ]))
        sway.timingMode = .easeInEaseOut
        sticker.runAction(sway, forKey: "idle")
        scene.rootNode.addChildNode(holder)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 32
        camera.camera?.wantsDepthOfField = false
        camera.position = SCNVector3(0, -1.5, 4.9)
        camera.look(at: SCNVector3(0, -0.42, 0))
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1100
        key.light?.castsShadow = true
        key.light?.shadowRadius = 6
        key.light?.shadowSampleCount = 16
        key.light?.shadowColor = NSColor.black.withAlphaComponent(0.6)
        key.light?.shadowMode = .deferred
        key.eulerAngles = SCNVector3(-0.5, 0.35, 0.2)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 380
        scene.rootNode.addChildNode(fill)
        return scene
    }
}
