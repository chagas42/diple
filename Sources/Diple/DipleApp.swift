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
        model.onReviewsPending = { [weak self] keys, count in self?.notch.expectReviews(keys, showing: count) }
        model.onNoReview = { [weak self] key in self?.notch.noReview(key) }
        model.onTick = { [weak self] t in self?.notch.tick(t) }
        model.onPreviewClaim = { [weak self] reward in self?.notch.preview(reward) }
        model.onReward = { [weak self] reward in self?.notch.reward(reward) }
        notch.onClaimed = { reward in model.claimed(reward) }
        notch.mount(model: model)
        model.start()
        checkScreen()
        Task { await Worktree.pruneStale() }

        if Bench.scenario == "notch-idle" {
            Task { @MainActor in await BenchScenarios.notchIdle(notch: notch) }
        }

        if CommandLine.arguments.contains("--rehearse-review"), Demo.isOn {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                model.rehearseReviews()
            }
        }

        if let i = CommandLine.arguments.firstIndex(of: "--nap"), i + 1 < CommandLine.arguments.count {
            let nap: Nap = switch CommandLine.arguments[i + 1] {
            case "short": .short
            case "medium": .medium
            default: .long
            }
            notch.rehearse(nap, after: .seconds(9))
        }

        if CommandLine.arguments.contains("--windowFrame") {
            Windows.shared.openMain(model)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--celebrate") {
            let wanted = CommandLine.arguments.dropFirst(i + 1).first.flatMap(Rarity.init(rawValue:))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let step = wanted.flatMap { r in Trail.rarities.firstIndex(of: r) } ?? 0
                model.rehearse(toward: Trail.milestones[step])
            }
        }

        if Tour.isOn {
            Task { @MainActor in await Tour.run(notch: notch, model: model) }
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

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.flushState()
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
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { Windows.shared.openSettings(model) }
                    .keyboardShortcut(",")
            }
        }
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

        if let i = CommandLine.arguments.firstIndex(of: "--state") {
            for path in CommandLine.arguments.dropFirst(i + 1) where !path.hasPrefix("--") {
                Probe.readState(path)
            }
            exit(0)
        }

        if CommandLine.arguments.contains("--tools") {
            Probe.tools()
            exit(0)
        }
        if let scenario = Bench.scenario, scenario != "notch-idle" {
            await BenchScenarios.runHeadless(scenario)
        }
        if CommandLine.arguments.contains("--probe") {
            await Probe.run()
            exit(0)
        }
        DipleApp.main()
    }
}
