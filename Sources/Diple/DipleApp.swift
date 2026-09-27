import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let notch = NotchController()

    @Published var showsMenuBarItem = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.compartilhado
        model.onEvent = { [weak self] evento in self?.notch.alertar(evento) }
        model.onCountChange = { [weak self] in self?.notch.refreshIdle() }
        notch.mount(model: model)
        model.start()
        checkScreen()
        Task { await Worktree.pruneStale() }

        if CommandLine.arguments.contains("--windowFrame") {
            Windows.compartilhado.openMain(model)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkScreen() }
        }
    }

    private func checkScreen() {
        showsMenuBarItem = !NotchGeometry.current().hasNotch
    }
}

struct DipleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.compartilhado

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { delegate.showsMenuBarItem },
            set: { _ in }
        )) {
            PopoverView(model: model)
        } label: {
            Text(model.count > 0 ? "⟩ \(model.count)" : "⟩")
        }
        .menuBarExtraStyle(.window)
    }
}

@main
struct Main {
    static func main() async {
        if CommandLine.arguments.contains("--notch") {
            await MainActor.run { NotchProbe.run() }
            exit(0)
        }
        if CommandLine.arguments.contains("--tools") {
            Probe.tools()
            exit(0)
        }
        if CommandLine.arguments.contains("--probe") {
            await Probe.run()
            exit(0)
        }
        DipleApp.main()
    }
}
