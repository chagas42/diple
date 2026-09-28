import SwiftUI
import AppKit

@MainActor
final class NotchController: ObservableObject {
    @Published private(set) var state: NotchState = .hidden
    @Published private(set) var size: CGSize = .zero
    @Published private(set) var notchWidth: CGFloat = 185
    @Published private(set) var notchHeight: CGFloat = 32
    let eye = EyeState()

    private let panel = NotchPanel()

    var panelContentView: NSView? { panel.contentView }
    private weak var model: AppModel?
    private var collapseTask: Task<Void, Never>?

    private var outsideSince: Date?

    private var pointerAnchor: CGPoint?
    private var pointerTimer: Timer?
    private var blinkTask: Task<Void, Never>?

    var pointer: @MainActor () -> CGPoint = { NSEvent.mouseLocation }

    func mount(model: AppModel) {
        self.model = model
        panel.contentView = NSHostingView(rootView: Host(notch: self, model: model))
        measure()
        panel.setFrame(NotchGeometry.current().windowFrame(), display: true)
        panel.orderFrontRegardless()
        trackPointer()
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
    }

    private func measure() {
        let g = NotchGeometry.current()
        notchWidth = g.notchWidth
        notchHeight = g.topInset
        apply()
    }

    private func apply() {
        let g = NotchGeometry.current()
        let next: CGSize = switch state {
        case .hidden:    g.closed
        case .active: g.active
        case .open:    g.open
        case .alert:    g.alert
        }
        size = next

        switch state {
        case .hidden, .active: panel.ignoresMouseEvents = true
        case .open, .alert:    panel.ignoresMouseEvents = false
        }
    }

    private func idle() -> NotchState { .active }

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
        pointerAnchor = nil
        state = idle()
        apply()
        model?.setNotchOpen(false)
    }

    func alert(_ e: Event) {
        guard e.kind.interrupts else { return }
        collapseTask?.cancel()
        pointerAnchor = pointer()
        state = .alert(e)
        apply()

        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, self.state != .open else { return }
            self.closeNow()
        }
    }

    func refreshIdle() {
        guard state == .hidden || state == .active else { return }
        state = idle()
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

    private func checkPointer() {
        if Film.isOn { return }
        let g = NotchGeometry.current()
        let shape = g.rect(size)

        let hotZone = shape.union(g.rect(g.closed))
        let m = pointer()

        let isOpen = state == .open
        let inside = isOpen ? hotZone.insetBy(dx: -16, dy: -16).contains(m)
                            : hotZone.contains(m)

        if inside {
            outsideSince = nil
            if case .alert = state, let a = pointerAnchor {
                let moved = hypot(m.x - a.x, m.y - a.y) > 8
                guard moved else { return }
            }
            pointerAnchor = nil
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
        let f = g.rect(size)
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
                eye: notch.eye,
                onClose: { notch.closeNow() }
            )
        }
    }
}
