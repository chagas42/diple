import SwiftUI
import AppKit

@MainActor
final class NotchController: ObservableObject {
    @Published private(set) var state: NotchState = .active
    @Published private(set) var size: CGSize = .zero
    @Published private(set) var notchWidth: CGFloat = 185
    @Published private(set) var notchHeight: CGFloat = 32
    @Published private(set) var wings = Wings(left: 42, right: 42)
    @Published private(set) var shift: CGFloat = 0
    @Published private(set) var shrinking = false
    @Published private(set) var appearing = false
    @Published private(set) var hasNotch = true
    @Published private(set) var waking = false
    @Published private(set) var asleep = false
    private(set) var fellAsleep = Date()
    let eye = EyeState()

    private let panel = NotchPanel()

    var panelContentView: NSView? { panel.contentView }
    private weak var model: AppModel?
    private var collapseTask: Task<Void, Never>?

    private var outsideSince: Date?

    private var holdingAlert = false
    var afterHover: Duration = .seconds(1.5)
    private var pointerTimer: Timer?
    private var blinkTask: Task<Void, Never>?
    private var wingTimer: Timer?

    var pointer: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    var fullScreen: @MainActor () -> Bool = { NotchGeometry.current().isUnderFullScreen }
    var fullScreenArriving: (@MainActor () -> Bool)?
    var wakes = !Film.isOn && !Bench.isOn && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var nap: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    private var wakeTask: Task<Void, Never>?
    var clock: @MainActor () -> Date = Date.init
    static let longestSwitch: TimeInterval = 1.5
    private var arrivingSince: Date?
    private var underFullScreen = false
    private var arriving = false
    private var menuBarRevealed = false
    private var fullScreenSpaces: Set<Int> = []
    private var fullScreenWindows: [CGWindowID] = []

    func mount(model: AppModel) {
        self.model = model
        settleBeforeFirstFrame()
        fallAsleep()
        measure()
        startFromTheNotch()
        panel.setFrame(NotchGeometry.current().windowFrame(), display: false)
        panel.contentView = NSHostingView(rootView: Host(notch: self, model: model))
        panel.orderFrontRegardless()
        spreadWings()
        startWaking()
        trackPointer()
        watchMenuBar()
        blinkOccasionally()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.measure()
                self.panel.setFrame(NotchGeometry.current().windowFrame(), display: true)
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIdle()
                self?.mapFullScreenWindows(force: true)
            }
        }
    }

    private func measure() {
        let g = NotchGeometry.current()
        hasNotch = g.hasNotch
        notchWidth = g.notchWidth
        notchHeight = g.topInset
        apply()
    }

    private func apply() {
        let g = NotchGeometry.current()
        wings = g.wings
        shift = state == .active ? wings.shift : 0
        let next: CGSize = switch state {
        case .hidden:    g.closed
        case .active: g.active
        case .open:    g.open
        case .alert:    g.alert
        }
        shrinking = next.width < size.width || next.height < size.height
        size = next

        switch state {
        case .hidden, .active: panel.ignoresMouseEvents = true
        case .open, .alert:    panel.ignoresMouseEvents = false
        }
    }

    static let spread: Duration = .milliseconds(550)

    private func startFromTheNotch() {
        guard state == .active else { return }
        size = NotchGeometry.current().closed
        shift = 0
    }

    private func spreadWings() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self else { return }
            self.appearing = true
            self.refreshIdle()
            self.apply()
            try? await Task.sleep(for: Self.spread)
            self.appearing = false
        }
    }

    private func idle() -> NotchState {
        (underFullScreen || arriving) && !menuBarRevealed ? .hidden : .active
    }

    func fallAsleep() {
        guard wakes, state == .active else { return }
        asleep = true
        fellAsleep = Date()
        waking = true
        eye.lid = 0
    }

    private func startWaking() {
        guard waking else { return }
        wakeTask = Task { [weak self] in await self?.wake() }
    }

    func wake() async {
        guard waking else { return }
        guard await rest(3200) else { return }
        asleep = false
        guard state == .active else { return finishWaking() }
        eye.lid = 0.45
        guard await rest(600), await slowBlink(), await rest(300),
              await slowBlink(), await rest(350) else { return }
        for (lid, ms) in [(0.12, 450), (0.18, 500), (0.6, 350), (1, 0)] as [(CGFloat, Int)] {
            eye.lid = lid
            guard await rest(ms) else { return }
        }
        guard await rest(400), await slowBlink(), await rest(250) else { return }
        for (gaze, ms) in [(CGPoint(x: -0.8, y: 0.1), 350), (CGPoint(x: 0.8, y: 0.1), 350), (.zero, 200)] {
            eye.look(at: gaze)
            guard await rest(ms) else { return }
        }
        finishWaking()
    }

    private func rest(_ ms: Int) async -> Bool {
        await nap(.milliseconds(ms))
        return waking
    }

    private func slowBlink() async -> Bool {
        let open = eye.lid
        eye.lidSpeed = 0.12
        eye.lid = 0.05
        guard await rest(300) else { return false }
        eye.lidSpeed = 0.35
        eye.lid = open
        guard await rest(350) else { return false }
        eye.lidSpeed = 0.4
        return true
    }

    private func finishWaking() {
        wakeTask?.cancel()
        wakeTask = nil
        guard waking || asleep else { return }
        asleep = false
        waking = false
        eye.lidSpeed = 0.4
        eye.lid = 1
        settleIdle()
    }

    func open() {
        finishWaking()
        collapseTask?.cancel()
        guard state != .open else { return }
        state = .open
        apply()
        model?.setNotchOpen(true)
    }

    func closeNow() {
        collapseTask?.cancel()
        collapseTask = nil
        outsideSince = nil
        holdingAlert = false
        state = idle()
        apply()
        model?.setNotchOpen(false)
    }

    func alert(_ e: Event) {
        guard e.kind.interrupts else { return }
        finishWaking()
        holdingAlert = false
        state = .alert(e)
        apply()
        collapse(after: .seconds(6))
    }

    private func collapse(after delay: Duration) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.state != .open else { return }
            self.closeNow()
        }
    }

    func settleBeforeFirstFrame() {
        underFullScreen = fullScreen()
        state = idle()
    }

    func refreshIdle() {
        underFullScreen = fullScreen()
        if underFullScreen { arriving = false }
        settleIdle()
    }

    private func mapFullScreenWindows(force: Bool = false) {
        guard fullScreenArriving == nil else { return }
        let spaces = NotchGeometry.current().fullScreenSpaces
        guard force || spaces != fullScreenSpaces else { return }
        fullScreenSpaces = spaces
        let mapping = Task.detached(priority: .utility) { FullScreenWindows.ids(in: spaces) }
        Task { [weak self] in
            let ids = await mapping.value
            self?.fullScreenWindows = ids
        }
    }

    private func checkArriving() {
        let seen = !underFullScreen && (fullScreenArriving?() ?? FullScreenWindows.anyOnScreen(fullScreenWindows))
        if seen { arrivingSince = arrivingSince ?? clock() } else { arrivingSince = nil }
        let now = arrivingSince.map { clock().timeIntervalSince($0) < Self.longestSwitch } ?? false
        guard now != arriving else { return }
        arriving = now
        settleIdle()
    }

    private func settleIdle() {
        guard state == .hidden || state == .active else { return }
        let next = idle()
        guard next != state || NotchGeometry.current().wings != wings else { return }
        state = next
        apply()
    }

    private func trackPointer() {
        if Film.isOn { return }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.checkPointer()
                self.aim()
            }
        }
    }

    private func watchMenuBar() {
        if Film.isOn { return }
        mapFullScreenWindows(force: true)
        wingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIdle()
                self?.mapFullScreenWindows()
            }
        }
    }

    func checkPointer() {
        if Film.isOn { return }
        let g = NotchGeometry.current()
        let shape = g.rect(size, shift: shift)

        let hotZone = shape.union(g.rect(g.closed))
        let m = pointer()

        let revealed = underFullScreen
            && NotchGeometry.revealsMenuBar(pointer: m, screen: g.screen.frame, barHeight: g.topInset, shown: menuBarRevealed)
        if revealed != menuBarRevealed {
            menuBarRevealed = revealed
            settleIdle()
        }
        checkArriving()

        let isOpen = state == .open
        let inside = isOpen ? hotZone.insetBy(dx: -16, dy: -16).contains(m)
                            : hotZone.contains(m)

        if case .alert = state {
            if inside, !holdingAlert {
                holdingAlert = true
                collapseTask?.cancel()
            } else if !inside, holdingAlert {
                holdingAlert = false
                collapse(after: afterHover)
            }
            return
        }

        if inside {
            outsideSince = nil
            open()
            return
        }

        guard isOpen else { outsideSince = nil; return }

        let now = Date()
        if outsideSince == nil { outsideSince = now }
        if now.timeIntervalSince(outsideSince!) >= 0.18 {
            closeNow()
        }
    }

    private func aim() {
        guard !waking, state == .hidden || state == .active else { return }
        let g = NotchGeometry.current()
        let f = g.rect(size, shift: shift)
        let m = pointer()
        let range: CGFloat = 300
        let dx = max(-1, min(1, (m.x - f.midX) / range))
        let dy = max(-1, min(1, (f.midY - m.y) / range))
        let next = CGPoint(x: dx, y: dy)
        eye.look(at: next)
    }

    private func blinkOccasionally() {
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 4...9)))
                guard let self, !Task.isCancelled else { return }
                self.eye.blinking = true
                try? await Task.sleep(for: .milliseconds(110))
                self.eye.blinking = false
            }
        }
    }

    private struct Host: View {
        @ObservedObject var notch: NotchController
        @ObservedObject var model: AppModel

        var body: some View {
            NotchView(
                model: model,
                state: notch.state,
                size: notch.size,
                notchWidth: notch.notchWidth,
                notchHeight: notch.notchHeight,
                countOnLeft: notch.wings.countOnLeft,
                shift: notch.shift,
                shrinking: notch.shrinking,
                appearing: notch.appearing,
                hidesByFading: !notch.hasNotch,
                waking: notch.waking,
                sleepingSince: notch.asleep ? notch.fellAsleep : nil,
                eye: notch.eye,
                onClose: { notch.closeNow() }
            )
        }
    }
}
