import SwiftUI
import AppKit

@MainActor
final class Windows: NSObject, NSWindowDelegate {
    static let compartilhado = Windows()

    private var main: NSWindow?
    private var settings: NSWindow?

    private func syncDockPolicy() {
        let anyOpen = [main, settings].contains { $0?.isVisible == true }
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
