import SwiftUI
import AppKit

/// Janelas criadas em AppKit, não como cena do SwiftUI.
///
/// O painel da notch é um NSHostingView montado na mão, fora do grafo de
/// cenas — então `@Environment(\.openWindow)` ali é um no-op silencioso, e o
/// botão de janela não fazia nada. Com NSWindow a abertura é uma chamada de
/// método, e funciona de qualquer lugar.
@MainActor
final class Janelas: NSObject, NSWindowDelegate {
    static let compartilhado = Janelas()

    private var principal: NSWindow?
    private var ajustes: NSWindow?

    /// O app vive na notch, então normalmente não ocupa lugar no Dock. Com
    /// janela aberta ele vira app normal — e some de novo quando a última
    /// fecha. É o que faz o ⌘Tab e o Dock se comportarem como você espera.
    private func ajustarDock() {
        let abertas = [principal, ajustes].contains { $0?.isVisible == true }
        NSApp.setActivationPolicy(abertas ? .regular : .accessory)
        if abertas { NSApp.activate(ignoringOtherApps: true) }
    }

    func windowWillClose(_ notification: Notification) {
        // isVisible ainda é true durante o willClose; decide no próximo ciclo.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            self.ajustarDock()
        }
    }

    func abrirPrincipal(_ modelo: Modelo) {
        NSApp.activate(ignoringOtherApps: true)
        if let j = principal {
            j.makeKeyAndOrderFront(nil)
            ajustarDock()
            return
        }
        let j = criar(
            titulo: "Diple",
            tamanho: NSSize(width: 1320, height: 820),
            conteudo: JanelaView(modelo: modelo)
        )
        j.setFrameAutosaveName("diple.principal")
        j.delegate = self
        principal = j
        j.makeKeyAndOrderFront(nil)
        ajustarDock()
    }

    func abrirAjustes(_ modelo: Modelo) {
        NSApp.activate(ignoringOtherApps: true)
        if let j = ajustes {
            j.makeKeyAndOrderFront(nil)
            ajustarDock()
            return
        }
        let j = criar(
            titulo: "Ajustes do Diple",
            tamanho: NSSize(width: 620, height: 470),
            conteudo: AjustesView(modelo: modelo),
            redimensionavel: false
        )
        j.delegate = self
        ajustes = j
        j.makeKeyAndOrderFront(nil)
        ajustarDock()
    }

    private func criar<C: View>(
        titulo: String,
        tamanho: NSSize,
        conteudo: C,
        redimensionavel: Bool = true
    ) -> NSWindow {
        var estilo: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if redimensionavel { estilo.insert(.resizable) }

        let j = NSWindow(
            contentRect: NSRect(origin: .zero, size: tamanho),
            styleMask: estilo,
            backing: .buffered,
            defer: false
        )
        j.title = titulo
        j.titlebarAppearsTransparent = false
        j.contentView = NSHostingView(rootView: conteudo)
        j.isReleasedWhenClosed = false  // reabrir depois de fechar não pode crashar
        j.center()
        return j
    }
}
