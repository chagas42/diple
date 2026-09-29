import SwiftUI

@MainActor
enum Tour {
    static var isOn: Bool { CommandLine.arguments.contains("--tour") }

    static func run(notch: NotchController, model: AppModel) async {
        model.settings.rewardsBeta = true
        if model.settings.rewardsProfile == nil {
            model.settings.rewardsProfile = RewardsProfile(role: .lead, reason: .unblock)
        }
        await until { !notch.waking }
        await pause(1)

        model.rehearse(toward: Trail.milestones[0])
        await until { notch.celebration == nil && notch.pendingCelebrations.isEmpty }
        await pause(1.2)

        notch.holdsOpen = true
        notch.open()
        await pause(2.4)
        notch.holdsOpen = false

        ClaimWindow.autoKeep = .milliseconds(2200)
        notch.claim()
        await until { !notch.claiming }
        ClaimWindow.autoKeep = nil
        await pause(0.8)

        Windows.shared.openMain(model, collection: true)
        await pause(5)
        Windows.shared.openSettings(model, tab: .rewards)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private static func until(_ done: @escaping @MainActor () -> Bool) async {
        while !done() { try? await Task.sleep(for: .milliseconds(100)) }
    }
}
