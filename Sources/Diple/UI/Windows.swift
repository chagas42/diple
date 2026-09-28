import SwiftUI
import AppKit

@MainActor
final class Windows: NSObject, NSWindowDelegate {
    static let shared = Windows()

    private var main: NSWindow?
    private var settings: NSWindow?
    private var map: NSWindow?

    var mainIsVisible: Bool {
        guard let main, main.isVisible, !main.isMiniaturized else { return false }
        return main.occlusionState.contains(.visible)
    }

    private func syncDockPolicy() {
        let anyOpen = [main, settings, map].contains { $0?.isVisible == true }
        NSApp.setActivationPolicy(anyOpen ? .regular : .accessory)
        if anyOpen { NSApp.activate(ignoringOtherApps: true) }
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            self.syncDockPolicy()
        }
    }

    func openMain(_ model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)
        if let j = main {
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
        j.delegate = self
        main = j
        j.makeKeyAndOrderFront(nil)
        syncDockPolicy()
    }

    func openSettings(_ model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)
        if let j = settings {
            j.makeKeyAndOrderFront(nil)
            syncDockPolicy()
            return
        }
        let j = make(
            title: "Diple Settings",
            size: NSSize(width: 620, height: 470),
            content: SettingsView(model: model),
            resizable: false
        )
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
            j.contentView = NSHostingView(rootView: content)
            j.makeKeyAndOrderFront(nil)
            syncDockPolicy()
            return
        }
        let j = make(title: "Map · \(pr.key)", size: NSSize(width: 1280, height: 820), content: content)
        j.setFrameAutosaveName("diple.map")
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
        j.titlebarAppearsTransparent = false
        j.contentView = NSHostingView(rootView: content)
        j.isReleasedWhenClosed = false
        j.center()
        return j
    }
}
