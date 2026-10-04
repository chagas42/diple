import SwiftUI
import AppKit

@MainActor
final class Windows: NSObject, NSWindowDelegate {
    static let shared = Windows()

    private var main: NSWindow?
    private var settings: NSWindow?
    private var map: NSWindow?
    private var feedback: NSWindow?

    var mainIsVisible: Bool {
        guard let main, main.isVisible, !main.isMiniaturized else { return false }
        return main.occlusionState.contains(.visible)
    }

    private func syncDockPolicy() {
        let anyOpen = [main, settings, map, feedback].contains { $0?.isVisible == true }
        NSApp.setActivationPolicy(anyOpen ? .regular : .accessory)
        if anyOpen { NSApp.activate(ignoringOtherApps: true) }
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            self.syncDockPolicy()
        }
    }

    static func fitted(_ frame: NSRect, in visible: NSRect) -> NSRect {
        var f = frame
        f.size.width = min(f.width, visible.width)
        f.size.height = min(f.height, visible.height)
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        return f
    }

    static func host<C: View>(_ content: C) -> NSHostingController<C> {
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.minSize]
        return host
    }

    private func fit(_ j: NSWindow) {
        guard let visible = (j.screen ?? NSScreen.main)?.visibleFrame else { return }
        let f = Self.fitted(j.frame, in: visible)
        if f != j.frame { j.setFrame(f, display: false) }
    }

    func openMain(_ model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)
        if let j = main {
            fit(j)
            j.makeKeyAndOrderFront(nil)
            syncDockPolicy()
            return
        }
        let j = make(
            title: "Diple",
            size: NSSize(width: 1320, height: 820),
            content: MainWindowView(model: model)
        )
        j.setFrameAutosaveName("diple.main")
        fit(j)
        j.delegate = self
        main = j
        j.makeKeyAndOrderFront(nil)
        syncDockPolicy()
    }

    func openFeedback(_ model: AppModel, feature: FeedbackFeature) {
        NSApp.activate(ignoringOtherApps: true)
        feedback?.close()
        let j = make(
            title: "Feedback",
            size: NSSize(width: 480, height: 300),
            content: FeedbackView(model: model, feature: feature) { [weak self] in self?.feedback?.close() },
            resizable: false
        )
        j.titlebarAppearsTransparent = true
        j.titleVisibility = .hidden
        j.delegate = self
        feedback = j
        j.center()
        j.makeKeyAndOrderFront(nil)
        syncDockPolicy()
    }

    func openSettings(_ model: AppModel, pane: SettingsPane? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        if let j = settings {
            if let pane {
                let frame = j.frame
                j.contentViewController = Self.host(SettingsView(model: model, pane: pane))
                j.setFrame(frame, display: true)
            }
            j.makeKeyAndOrderFront(nil)
            syncDockPolicy()
            return
        }
        let j = make(
            title: "Diple Settings",
            size: NSSize(width: 860, height: 620),
            content: SettingsView(model: model, pane: pane ?? .general)
        )
        j.contentMinSize = SettingsView.minimum
        j.setFrameAutosaveName("diple.settings")
        fit(j)
        j.delegate = self
        settings = j
        j.makeKeyAndOrderFront(nil)
        syncDockPolicy()
    }

    func openMap(_ model: AppModel, _ pr: PR) {
        NSApp.activate(ignoringOtherApps: true)
        let content = MapWindowView(model: model, pr: pr)
        if let j = map {
            j.title = "Map · \(pr.key)"
            let frame = j.frame
            j.contentViewController = Self.host(content)
            j.setFrame(frame, display: true)
            j.makeKeyAndOrderFront(nil)
            syncDockPolicy()
            return
        }
        let j = make(title: "Map · \(pr.key)", size: NSSize(width: 1280, height: 820), content: content)
        j.setFrameAutosaveName("diple.map")
        fit(j)
        j.delegate = self
        map = j
        j.makeKeyAndOrderFront(nil)
        syncDockPolicy()
    }

    private func make<C: View>(
        title: String,
        size: NSSize,
        content: C,
        resizable: Bool = true
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }

        let j = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        j.title = title
        j.toolbarStyle = .unified
        j.contentViewController = resizable ? Self.host(content) : NSHostingController(rootView: content)
        j.setContentSize(size)
        j.isReleasedWhenClosed = false
        j.center()
        return j
    }
}
