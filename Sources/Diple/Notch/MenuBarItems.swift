import AppKit
import ApplicationServices

@MainActor
enum MenuBarItems {
    static var measuring = false

    static var allowed: Bool { AXIsProcessTrusted() }

    static let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func askForAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private static var cache: (at: Date, origins: [CGPoint])?
    private static let cacheLife: TimeInterval = 5

    static func lefts(onDisplay display: CGRect, now: Date = Date()) -> [CGFloat]? {
        guard measuring, allowed else { return nil }
        if cache == nil || now.timeIntervalSince(cache!.at) >= cacheLife {
            cache = (now, read())
        }
        let here = cache!.origins.filter { display.contains(CGPoint(x: $0.x, y: $0.y + 1)) }
        return here.isEmpty ? nil : here.map(\.x)
    }

    static func freeRight(notchRight: CGFloat, screenMaxX: CGFloat, lefts: [CGFloat]) -> CGFloat {
        let visible = lefts.filter { $0 >= notchRight - 1 }
        return (visible.min() ?? screenMaxX) - notchRight
    }

    private static func read() -> [CGPoint] {
        let me = ProcessInfo.processInfo.processIdentifier
        var origins: [CGPoint] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != me {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.05)
            guard let bar: AXUIElement = attribute(element, "AXExtrasMenuBar"),
                  let items: [AXUIElement] = attribute(bar, kAXChildrenAttribute)
            else { continue }
            origins += items.compactMap(point)
        }
        return origins
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func point(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }
}
