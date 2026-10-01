import AppKit

final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar

        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = false
        appearance = NSAppearance(named: .darkAqua)
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true

        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
