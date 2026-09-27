import SwiftUI
import AppKit

/// A notch precisa existir desde o lançamento, e o conteúdo do MenuBarExtra
/// só é construído quando você clica nele — por isso a montagem vive aqui.
@MainActor
final class Delegate: NSObject, NSApplicationDelegate, ObservableObject {
    let notch = Notch()

    /// Com recorte, o app já aparece dentro dele — dois ícones dizendo a mesma
    /// coisa na mesma faixa é ruído.
    @Published var naBarraDeMenu = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let modelo = Modelo.compartilhado
        modelo.aoEvento = { [weak self] evento in self?.notch.alertar(evento) }
        modelo.aoContadorMudar = { [weak self] in self?.notch.revisarRepouso() }
        notch.montar(modelo: modelo)
        modelo.iniciar()
        conferirTela()

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
            // O diple ⟩ com o contador: a marca de margem que dá nome ao app.
            Text(modelo.contador > 0 ? "⟩ \(modelo.contador)" : "⟩")
        }
        .menuBarExtraStyle(.window)

        Window("Diple", id: Janela.principal) {
            JanelaView(modelo: modelo)
        }
        .defaultSize(width: 1320, height: 820)
        .windowToolbarStyle(.unified)

        Window("Ajustes do Diple", id: Janela.ajustes) {
            AjustesView(modelo: modelo)
        }
        .windowResizability(.contentSize)
    }
}

enum Janela {
    static let principal = "principal"
    static let ajustes = "ajustes"
}

// MARK: - Ponto de entrada
// `Diple --probe` roda o cliente no terminal; sem argumento sobe a UI.
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
