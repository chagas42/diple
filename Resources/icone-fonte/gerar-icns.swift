// Gera Resources/Diple.icns a partir do mestre. Rode com `make icone`,
// da raiz do repositório.
import AppKit

// Grade oficial do ícone de macOS: obra de 824 num canvas de 1024.
// O canto da Apple é uma superelipse, não arco de círculo — com arco o
// ícone fica visivelmente "mais quadrado" do lado dos vizinhos no Dock.
func squircle(lado: CGFloat, n: CGFloat = 5) -> CGPath {
    let c = CGMutablePath()
    let r = lado / 2
    let passos = 720
    for i in 0...passos {
        let t = CGFloat(i) / CGFloat(passos) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = r * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = r * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        let p = CGPoint(x: x + r, y: y + r)
        i == 0 ? c.move(to: p) : c.addLine(to: p)
    }
    c.closeSubpath()
    return c
}

let origem = URL(fileURLWithPath: "Resources/icone-fonte/mestre-1024.png")
guard let src = NSImage(contentsOf: origem),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("não consegui ler a origem"); exit(1)
}

let canvas: CGFloat = 1024
let obra: CGFloat = 824
let margem = (canvas - obra) / 2

guard let ctx = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { print("sem contexto"); exit(1) }

ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

// Sombra sutil, como os ícones do sistema têm.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10),
              blur: 22,
              color: NSColor.black.withAlphaComponent(0.26).cgColor)
ctx.addPath({
    let p = CGMutablePath()
    p.addPath(squircle(lado: obra), transform: CGAffineTransform(translationX: margem, y: margem))
    return p
}())
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()

// A arte, recortada no squircle.
ctx.saveGState()
ctx.addPath({
    let p = CGMutablePath()
    p.addPath(squircle(lado: obra), transform: CGAffineTransform(translationX: margem, y: margem))
    return p
}())
ctx.clip()
ctx.draw(cg, in: CGRect(x: margem, y: margem, width: obra, height: obra))
ctx.restoreGState()

guard let saida = ctx.makeImage() else { print("sem imagem"); exit(1) }

// Gera o iconset inteiro a partir do mestre.
let pasta = URL(fileURLWithPath: "/tmp/Diple.iconset")
try? FileManager.default.removeItem(at: pasta)
try! FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)

let tamanhos: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (nome, lado) in tamanhos {
    guard let c = CGContext(
        data: nil, width: lado, height: lado,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }
    c.interpolationQuality = .high
    c.draw(saida, in: CGRect(x: 0, y: 0, width: lado, height: lado))
    guard let img = c.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: pasta.appendingPathComponent("\(nome).png"))
}
print("iconset com \(tamanhos.count) tamanhos")
