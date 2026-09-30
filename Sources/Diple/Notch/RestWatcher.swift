import AppKit

enum Nap: Equatable {
    case short, medium, long

    static let shortest: TimeInterval = 2 * 60
    static let longest: TimeInterval = 60 * 60

    init(resting seconds: TimeInterval) {
        self = seconds < Self.shortest ? .short : seconds < Self.longest ? .medium : .long
    }
}

@MainActor
final class RestWatcher {
    var onRest: () -> Void = {}
    var onBack: (TimeInterval) -> Void = { _ in }
    var clock: () -> Date = Date.init

    private var restingSince: Date?
    private var backAt: Date?
    private var locked = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        watch(workspace, NSWorkspace.willSleepNotification) { $0.rest() }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { $0.rest() }
        watch(workspace, NSWorkspace.didWakeNotification) { $0.back() }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { $0.back() }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.lock() }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.unlock() }
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ act: @escaping @MainActor @Sendable (RestWatcher) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                act(self)
            }
        }
        observers.append((center, token))
    }

    func rest() {
        backAt = nil
        guard restingSince == nil else { return }
        restingSince = clock()
        onRest()
    }

    func back() {
        guard restingSince != nil else { return }
        backAt = backAt ?? clock()
        if !locked { finish() }
    }

    func lock() {
        locked = true
    }

    func unlock() {
        locked = false
        if backAt != nil { finish() }
    }

    private func finish() {
        guard let since = restingSince, let back = backAt else { return }
        restingSince = nil
        backAt = nil
        onBack(back.timeIntervalSince(since))
    }
}
