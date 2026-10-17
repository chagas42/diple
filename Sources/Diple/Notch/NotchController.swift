import SwiftUI
import AppKit
import Combine

@MainActor
final class NotchController: ObservableObject {
    @Published private(set) var state: NotchState = .active
    @Published private(set) var size: CGSize = .zero
    @Published private(set) var notchWidth: CGFloat = 185
    @Published private(set) var notchHeight: CGFloat = 32
    @Published private(set) var wings = Wings(left: 42, right: 42)
    @Published private(set) var shift: CGFloat = 0
    @Published private(set) var shrinking = false
    let pulling = PullState()
    private var pull: Pull { pulling.pull }
    private var gravity = Gravity()
    @Published private(set) var appearing = false
    @Published private(set) var hasNotch = true
    @Published private(set) var waking = false
    @Published private(set) var asleep = false
    private(set) var fellAsleep = Date()
    @Published private(set) var dozesQuickly = false
    @Published private(set) var tick: ReviewTick?
    private(set) var tickStart = Date()
    private(set) var pendingTicks: [ReviewTick] = []
    @Published private(set) var heldCount: Int?
    private(set) var expecting: Set<String> = []
    private var holdRelease: Task<Void, Never>?
    var holdsAtMost: Duration = .seconds(20)
    let eye = EyeState()
    let glowing = GlowState()

    private let panel = NotchPanel()

    var panelContentView: NSView? { panel.contentView }
    private weak var model: AppModel?
    private var collapseTask: Task<Void, Never>?

    private var outsideSince: Date?
    private var intent = HoverIntent()

    private var holdingAlert = false
    var afterHover: Duration = .seconds(1.5)
    private var pointerTimer: Timer?
    private var blinkTask: Task<Void, Never>?
    private var wingTimer: Timer?

    var pointer: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    var pressed: @MainActor () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    var fullScreen: @MainActor () -> Bool = { NotchGeometry.current().isUnderFullScreen }
    var fullScreenArriving: (@MainActor () -> Bool)?
    var wakes = !Film.isOn && !Bench.isOn && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var nap: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    private var wakeTask: Task<Void, Never>?
    private let resting = RestWatcher()
    private var showsEye = true
    private var countOnLeft = false
    private var wingSettings: AnyCancellable?
    private var focusWatch: AnyCancellable?
    @Published private(set) var focusedSince: Date?
    @Published private(set) var focusEnded: Date?
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
        wingSettings = model.$settings
            .removeDuplicates { $0.showsEye == $1.showsEye && $0.countSide == $1.countSide }
            .sink { [weak self] s in self?.arrange(showsEye: s.showsEye, countOnLeft: s.countSide == .left) }
        focusWatch = model.focus.$byHand.combineLatest(model.focus.$system, model.focus.$setAside)
            .map { $0 || ($1 && !$2) }
            .removeDuplicates()
            .sink { [weak self] on in self?.focus(on) }
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
        watchRest()

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
        wings = g.wings(showsEye: showsEye, countOnLeft: countOnLeft)
        shift = state == .active ? wings.shift : 0
        let next: CGSize = switch state {
        case .hidden:    g.closed
        case .active: tick == nil ? g.active(wings)
            : CGSize(width: g.active(wings).width, height: g.active(wings).height + ReviewStrip.drawer)
        case .open:    g.open
        case .alert:    g.alert
        }
        shrinking = next.width < size.width || next.height < size.height
        if next != size { resizedAt = Date() }
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

    func arrange(showsEye: Bool, countOnLeft: Bool) {
        self.showsEye = showsEye
        self.countOnLeft = countOnLeft
        if !showsEye { finishWaking() }
        settleIdle()
    }

    func fallAsleep() {
        guard wakes, state == .active else { return }
        asleep = true
        dozesQuickly = false
        fellAsleep = Date()
        shutEyes()
    }

    private func shutEyes() {
        waking = true
        eye.lidSpeed = 0.4
        eye.lid = 0
    }

    private func startWaking(_ nap: Nap = .long) {
        guard waking else { return }
        wakeTask = Task { [weak self] in await self?.wake(after: nap) }
    }

    private func watchRest() {
        resting.onRest = { [weak self] in self?.restStarted() }
        resting.onBack = { [weak self] seconds in self?.back(after: seconds) }
        resting.start()
    }

    func restStarted() {
        wakeTask?.cancel()
        wakeTask = nil
        asleep = false
        guard wakes, showsEye, state == .active || state == .hidden else { return }
        shutEyes()
    }

    func back(after seconds: TimeInterval) {
        back(from: Nap(resting: seconds))
    }

    func back(from nap: Nap) {
        guard waking else { return }
        refreshIdle()
        guard state == .active else { return finishWaking() }
        asleep = true
        fellAsleep = Date()
        dozesQuickly = nap == .short
        startWaking(nap)
    }

    private var hiddenForOnboarding = false

    func setOnboarding(_ on: Bool) {
        guard on != hiddenForOnboarding else { return }
        hiddenForOnboarding = on
        if on {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            rehearse(.long, after: .milliseconds(400))
        }
    }

    func rehearse(_ nap: Nap, after delay: Duration = .seconds(1)) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            for _ in 0..<100 where self?.state != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, self.state == .active else { return }
            self.restStarted()
            try? await Task.sleep(for: .seconds(1.5))
            self.back(from: nap)
        }
    }

    func wake(after nap: Nap = .long) async {
        guard waking else { return }
        let woke = switch nap {
        case .short: await wakeShort()
        case .medium: await wakeMedium()
        case .long: await wakeLong()
        }
        guard woke else { return }
        finishWaking()
    }

    private func wakeShort() async -> Bool {
        guard await rest(1000) else { return false }
        asleep = false
        guard state == .active else { finishWaking(); return false }
        eye.lidSpeed = 0.25
        eye.lid = 1
        guard await rest(450), await slowBlink(), await rest(200) else { return false }
        return true
    }

    private func wakeMedium() async -> Bool {
        guard await rest(1600) else { return false }
        asleep = false
        guard state == .active else { finishWaking(); return false }
        eye.lid = 0.45
        guard await rest(500), await slowBlink(), await rest(250) else { return false }
        eye.lid = 1
        guard await rest(350) else { return false }
        return await lookAround()
    }

    private func wakeLong() async -> Bool {
        guard await rest(3200) else { return false }
        asleep = false
        guard state == .active else { finishWaking(); return false }
        eye.lid = 0.45
        guard await rest(600), await slowBlink(), await rest(300),
              await slowBlink(), await rest(350) else { return false }
        for (lid, ms) in [(0.12, 450), (0.18, 500), (0.6, 350), (1, 0)] as [(CGFloat, Int)] {
            eye.lid = lid
            guard await rest(ms) else { return false }
        }
        guard await rest(400), await slowBlink(), await rest(250) else { return false }
        return await lookAround()
    }

    private func lookAround() async -> Bool {
        if Motion.reduced { return true }
        for (gaze, ms) in [(CGPoint(x: -0.8, y: 0.1), 350), (CGPoint(x: 0.8, y: 0.1), 350), (.zero, 200)] {
            eye.look(at: gaze)
            guard await rest(ms) else { return false }
        }
        return true
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
        showPendingTick()
    }

    func expectReviews(_ keys: [String], showing count: Int) {
        if heldCount == nil { heldCount = count }
        expecting.formUnion(keys)
        holdRelease?.cancel()
        let most = holdsAtMost
        holdRelease = Task { [weak self] in
            try? await Task.sleep(for: most)
            guard !Task.isCancelled, let self else { return }
            self.expecting = []
            self.releaseCount()
        }
    }

    func noReview(_ key: String) {
        expecting.remove(key)
        releaseCount()
    }

    func tick(_ t: ReviewTick) {
        expecting.remove(t.pr)
        pendingTicks.append(t)
        showPendingTick()
    }

    private func releaseCount() {
        guard expecting.isEmpty, tick == nil, pendingTicks.isEmpty else { return }
        holdRelease?.cancel()
        holdRelease = nil
        heldCount = nil
    }

    private func showPendingTick() {
        guard state == .active, !waking, tick == nil, !pendingTicks.isEmpty else { return }
        let t = pendingTicks.removeFirst()
        tick = t
        tickStart = Date()
        apply()
        Task { [weak self] in
            await self?.nap(.milliseconds(Int(ReviewStrip.paperLeaves * 1000)))
            guard let self else { return }
            if let h = self.heldCount { self.heldCount = max(self.model?.count ?? 0, h - 1) }
            await self.nap(.milliseconds(Int((ReviewStrip.length - ReviewStrip.paperLeaves) * 1000)))
            self.tick = nil
            self.apply()
            self.releaseCount()
            self.showPendingTick()
        }
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
        if next != state || NotchGeometry.current().wings(showsEye: showsEye, countOnLeft: countOnLeft) != wings {
            state = next
            apply()
        }
        showPendingTick()
    }

    private func trackPointer() {
        if Film.isOn { return }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.followPointer() }
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

    func followPointer() {
        checkPointer()
        aim()
        pullTowardPointer()
        trackGlow()
    }

    func trackGlow() {
        let g = NotchGeometry.current()
        guard state == .open, g.hasNotch else {
            glowing.show(.off)
            return
        }
        glowing.show(Glow.target(pointer: pointer(), cutout: g.rect(g.closed)))
    }

    func checkPointer() {
        let g = NotchGeometry.current()
        let shape = g.rect(size, shift: shift)

        let stretch = Blob.maxStretch * pull.strength
        let hotZone = shape.union(g.rect(g.closed)).union(shape.insetBy(dx: -stretch, dy: -stretch))
        let m = pointer()

        let revealed = underFullScreen
            && NotchGeometry.revealsMenuBar(pointer: m, screen: g.screen.frame, barHeight: g.topInset, shown: menuBarRevealed)
        if revealed != menuBarRevealed {
            menuBarRevealed = revealed
            settleIdle()
        }
        checkArriving()

        intent.opening = opensOnHover()
        let opens = intent.feed(
            at: clock(), pointer: m,
            zone: HoverIntent.zone(notch: g.rect(g.closed), shape: shape),
            pressed: pressed()
        ) == .open

        if case .alert = state {
            let inside = hotZone.contains(m)
            if inside, !holdingAlert {
                holdingAlert = true
                collapseTask?.cancel()
            } else if !inside, holdingAlert {
                holdingAlert = false
                collapse(after: afterHover)
            }
            return
        }

        guard state == .open else {
            outsideSince = nil
            if opens { open() }
            return
        }

        if hotZone.insetBy(dx: -16, dy: -16).contains(m) {
            outsideSince = nil
            return
        }

        let now = clock()
        if outsideSince == nil { outsideSince = now }
        if now.timeIntervalSince(outsideSince!) >= 0.18 {
            closeNow()
        }
    }

    lazy var opensOnHover: @MainActor () -> HoverOpening = { [weak self] in
        self?.model?.settings.hoverOpening ?? .afterPause
    }

    static let openEyeX: CGFloat = 14 + 16 + 11

    lazy var leans: @MainActor () -> Bool = { [weak self] in
        (self?.model?.settings.liquidNotch ?? false) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private var resizedAt = Date.distantPast
    static let settleAfterResize: TimeInterval = 0.45

    private var pulls: Bool {
        leans() && Date().timeIntervalSince(resizedAt) > Self.settleAfterResize
    }

    func pullTowardPointer() {
        guard pulls, !waking, state == .active else {
            if !pull.isNone { gravity = Gravity(); pulling.show(.none) }
            return
        }
        let g = NotchGeometry.current()
        let next = gravity.follow(gravity.target(pointer: pointer(), shape: g.rect(size, shift: shift)))
        if pulling.snaps {
            pulling.show(next)
        } else if next.isNone != pull.isNone || (!next.isNone && (next - pull).magnitudeSquared > 0.01) {
            pulling.show(next)
        }
    }

    private func aim() {
        guard showsEye, !waking, !eye.sore else { return }
        let g = NotchGeometry.current()
        let f = g.rect(size, shift: shift)
        let m = pointer()
        let from: CGPoint
        let range: CGFloat
        switch state {
        case .hidden, .active:
            from = CGPoint(x: f.midX, y: f.midY)
            range = 300
        case .open:
            from = CGPoint(x: f.minX + Self.openEyeX, y: f.maxY - notchHeight / 2)
            range = 160
        case .alert:
            return
        }
        let dx = max(-1, min(1, (m.x - from.x) / range))
        let dy = max(-1, min(1, (from.y - m.y) / range))
        eye.look(at: Motion.reduced ? .zero : CGPoint(x: dx, y: dy))
    }

    private var blinks: Bool {
        guard let s = model?.settings else { return true }
        return s.showsEye && s.eyeBlinks && !eye.focused && !Motion.reduced
    }

    func focus(_ on: Bool) {
        eye.focused = on
        if on {
            focusEnded = nil
            focusedSince = Date()
            return
        }
        guard focusedSince != nil else { return }
        let ended = Date()
        focusEnded = ended
        Task { [weak self] in
            try? await Task.sleep(for: FocusCover.lingers)
            guard let self, self.focusEnded == ended else { return }
            self.focusedSince = nil
            self.focusEnded = nil
        }
    }

    func poke() {
        Task { [weak self] in await self?.ouch() }
    }

    func ouch() async {
        guard !eye.sore else { return }
        finishWaking()
        eye.pokes += 1
        eye.complaining = true
        eye.sore = true
        eye.lidSpeed = 0.05
        eye.lid = 0.1
        await nap(.milliseconds(480))
        model?.focus.toggle()
        eye.lidSpeed = 0.3
        eye.lid = 1
        eye.sore = false
        await nap(.milliseconds(450))
        eye.complaining = false
        eye.lidSpeed = 0.4
    }

    private func blinkOccasionally() {
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 4...9)))
                guard let self, !Task.isCancelled else { return }
                guard self.blinks else { continue }
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
                wings: notch.wings,
                shift: notch.shift,
                shrinking: notch.shrinking,
                pulling: notch.pulling,
                appearing: notch.appearing,
                hidesByFading: !notch.hasNotch,
                waking: notch.waking,
                sleepingSince: notch.asleep ? notch.fellAsleep : nil,
                dozesQuickly: notch.dozesQuickly,
                tick: notch.tick,
                tickStart: notch.tickStart,
                heldCount: notch.heldCount,
                onEyeTap: { notch.poke() },
                onFocusToggle: { model.focus.toggle() },
                focusedSince: notch.focusedSince,
                focusEnded: notch.focusEnded,
                focusLook: model.settings.focusLook,
                eye: notch.eye,
                glowing: notch.glowing,
                onNap: DevBuild.isOn ? { notch.rehearse($0) } : nil,
                onClose: { notch.closeNow() }
            )
        }
    }
}
