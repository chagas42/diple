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
    @Published private(set) var hasNotch = true
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
    private var underFullScreen = false
    private var menuBarRevealed = false

    func mount(model: AppModel) {
        self.model = model
        panel.contentView = NSHostingView(rootView: Host(notch: self, model: model))
        measure()
        panel.setFrame(NotchGeometry.current().windowFrame(), display: true)
        panel.orderFrontRegardless()
        refreshIdle()
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
            Task { @MainActor in self?.refreshIdle() }
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

    private func idle() -> NotchState { underFullScreen && !menuBarRevealed ? .hidden : .active }

    func open() {
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

    func refreshIdle() {
        underFullScreen = fullScreen()
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
        wingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIdle() }
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
        guard state == .hidden || state == .active else { return }
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
                hidesByFading: !notch.hasNotch,
                eye: notch.eye,
                onClose: { notch.closeNow() }
            )
        }
    }
}
