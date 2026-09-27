import SwiftUI
import AppKit

struct DipleApp: App {
    @StateObject private var modelo = Modelo()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(modelo: modelo)
        } label: {
            // O diple ⟩ com o contador: a marca de margem que dá nome ao app.
            Text(modelo.contador > 0 ? "⟩ \(modelo.contador)" : "⟩")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Ponto de entrada
// `Diple --probe` roda o cliente no terminal; sem argumento sobe a UI.
@main
struct Entrada {
    static func main() async {
        if CommandLine.arguments.contains("--probe") {
            await Probe.rodar()
            exit(0)
        }
        DipleApp.main()
    }
}
