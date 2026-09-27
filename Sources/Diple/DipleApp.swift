import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let notch = NotchController()

    @Published var showsMenuBarItem = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.onEvent = { [weak self] event in self?.notch.alert(event) }
        model.onCountChange = { [weak self] in self?.notch.refreshIdle() }
        notch.mount(model: model)
        model.start()
        checkScreen()
        Task { await Worktree.pruneStale() }

        if CommandLine.arguments.contains("--windowFrame") {
            Windows.shared.openMain(model)
        }

        if Film.isOn {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                await Film.roll(notch: notch, model: model)
            }
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
    @ObservedObject private var model = AppModel.shared

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
        if let i = CommandLine.arguments.firstIndex(of: "--alert"),
           i + 1 < CommandLine.arguments.count {
            let wanted = CommandLine.arguments[i + 1]
            Task { @MainActor in
                guard let kind = EventKind(rawValue: wanted) else {
                    FileHandle.standardError.write(
                        "unknown alert: \(wanted)\nuse one of: \(EventKind.allCases.map(\.rawValue).joined(separator: ", "))\n"
                            .data(using: .utf8)!
                    )
                    exit(2)
                }
                await AppModel.shared.sendTestEvent(kind)
                try? await Task.sleep(for: .seconds(6))
                exit(0)
            }
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
