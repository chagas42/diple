import SwiftUI
import AppKit

@MainActor
final class Janelas: NSObject, NSWindowDelegate {
    static let compartilhado = Janelas()

    private var principal: NSWindow?
    private var ajustes: NSWindow?

    private func ajustarDock() {
        let abertas = [principal, ajustes].contains { $0?.isVisible == true }
        NSApp.setActivationPolicy(abertas ? .regular : .accessory)
        if abertas { NSApp.activate(ignoringOtherApps: true) }
    }

    func windowWillClose(_ notification: Notification) {
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
        j.isReleasedWhenClosed = false
        j.center()
        return j
    }
}
