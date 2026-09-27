import SwiftUI
import AppKit

@MainActor
final class Delegate: NSObject, NSApplicationDelegate, ObservableObject {
    let notch = Notch()

    @Published var naBarraDeMenu = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let modelo = Modelo.compartilhado
        modelo.aoEvento = { [weak self] evento in self?.notch.alertar(evento) }
        modelo.aoContadorMudar = { [weak self] in self?.notch.revisarRepouso() }
        notch.montar(modelo: modelo)
        modelo.iniciar()
        conferirTela()
        Task { await Worktree.limparOrfaos() }

        if CommandLine.arguments.contains("--janela") {
            Janelas.compartilhado.abrirPrincipal(modelo)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.conferirTela() }
        }
    }

    private func conferirTela() {
        naBarraDeMenu = !Geometria.atual().temNotch
    }
}

struct DipleApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) private var delegate
    @ObservedObject private var modelo = Modelo.compartilhado

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { delegate.naBarraDeMenu },
            set: { _ in }
        )) {
            PopoverView(modelo: modelo)
        } label: {
            Text(modelo.contador > 0 ? "⟩ \(modelo.contador)" : "⟩")
        }
        .menuBarExtraStyle(.window)
    }
}

@main
struct Entrada {
    static func main() async {
        if CommandLine.arguments.contains("--notch") {
            await MainActor.run { ProbeNotch.rodar() }
            exit(0)
        }
        if CommandLine.arguments.contains("--probe") {
            await Probe.rodar()
            exit(0)
        }
        DipleApp.main()
    }
}
