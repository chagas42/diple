import AppKit

func squircle(side: CGFloat, n: CGFloat = 5) -> CGPath {
    let c = CGMutablePath()
    let r = side / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = r * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = r * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        let p = CGPoint(x: x + r, y: y + r)
        i == 0 ? c.move(to: p) : c.addLine(to: p)
    }
    c.closeSubpath()
    return c
}

let source = URL(fileURLWithPath: "Resources/icon-source/master-1024.png")
guard let src = NSImage(contentsOf: source),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("could not read the master image"); exit(1)
}

let canvas: CGFloat = 1024
let artwork: CGFloat = 824
let margin = (canvas - artwork) / 2

guard let ctx = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { print("no drawing context"); exit(1) }

ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

func artworkShape() -> CGPath {
    let p = CGMutablePath()
    p.addPath(squircle(side: artwork), transform: CGAffineTransform(translationX: margin, y: margin))
    return p
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10),
              blur: 22,
              color: NSColor.black.withAlphaComponent(0.26).cgColor)
ctx.addPath(artworkShape())
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(artworkShape())
ctx.clip()
ctx.draw(cg, in: CGRect(x: margin, y: margin, width: artwork, height: artwork))
ctx.restoreGState()

guard let icon = ctx.makeImage() else { print("no image"); exit(1) }

let iconset = URL(fileURLWithPath: "/tmp/Diple.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, side) in sizes {
    guard let c = CGContext(
        data: nil, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }
    c.interpolationQuality = .high
    c.draw(icon, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let img = c.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("iconset with \(sizes.count) sizes")
