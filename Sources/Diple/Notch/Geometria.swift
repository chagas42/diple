import AppKit

@MainActor
struct Geometria {
    let tela: NSScreen

    var temNotch: Bool { tela.auxiliaryTopLeftArea != nil }

    var alturaTopo: CGFloat {
        temNotch ? tela.safeAreaInsets.top : 32
    }

    var larguraNotch: CGFloat {
        guard let esq = tela.auxiliaryTopLeftArea,
              let dir = tela.auxiliaryTopRightArea else { return 185 }
        return max(0, tela.frame.width - esq.width - dir.width)
    }

    var fechado: CGSize { CGSize(width: larguraNotch, height: alturaTopo) }

    var atividade: CGSize {
        CGSize(width: larguraNotch + asa * 2, height: alturaTopo)
    }

    var aberto: CGSize { CGSize(width: 680, height: 330) }

    var alerta: CGSize { CGSize(width: 580, height: 196) }

    var asa: CGFloat { 42 }

    func janela() -> NSRect {
        let l = max(aberto.width, alerta.width)
        let a = max(aberto.height, alerta.height)
        return NSRect(x: tela.frame.midX - l / 2,
                      y: tela.frame.maxY - a,
                      width: l, height: a)
    }

    func retangulo(_ tamanho: CGSize) -> NSRect {
        NSRect(x: tela.frame.midX - tamanho.width / 2,
               y: tela.frame.maxY - tamanho.height,
               width: tamanho.width, height: tamanho.height)
    }

    static func atual() -> Geometria {
        let comNotch = NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
        return Geometria(tela: comNotch ?? NSScreen.main ?? NSScreen.screens[0])
    }
}
