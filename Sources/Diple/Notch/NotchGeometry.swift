import AppKit

@MainActor
struct NotchGeometry {
    let screen: NSScreen

    var hasNotch: Bool { screen.auxiliaryTopLeftArea != nil }

    var topInset: CGFloat {
        hasNotch ? screen.safeAreaInsets.top : 32
    }

    var notchWidth: CGFloat {
        guard let esq = screen.auxiliaryTopLeftArea,
              let dir = screen.auxiliaryTopRightArea else { return 185 }
        return max(0, screen.frame.width - esq.width - dir.width)
    }

    var closed: CGSize { CGSize(width: notchWidth, height: topInset) }

    var active: CGSize {
        CGSize(width: notchWidth + wings.left + wings.right, height: topInset)
    }

    var open: CGSize { CGSize(width: 680, height: 330) }

    var alert: CGSize { CGSize(width: 580, height: 196) }

    var asa: CGFloat { 42 }

    static let minWing: CGFloat = 27

    var wings: Wings { Self.wings(freeRight: freeRight, full: asa) }

    static func wings(freeRight: CGFloat, full: CGFloat) -> Wings {
        let fits = min(full, freeRight - 6)
        return fits >= minWing ? Wings(left: fits, right: fits) : Wings(left: full, right: 0)
    }

    var freeRight: CGFloat {
        if let forced = ProcessInfo.processInfo.environment["DIPLE_FREE_RIGHT"].flatMap(Double.init) {
            return forced
        }
        guard hasNotch,
              let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return asa + 6 }

        let notchRight = screen.frame.midX + notchWidth / 2
        let barTop = primary.frame.maxY - screen.frame.maxY
        let me = ProcessInfo.processInfo.processIdentifier
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        var nearest = screen.frame.maxX
        var sawStatusItem = false

        for w in list {
            guard w[kCGWindowLayer as String] as? Int == statusLevel,
                  w[kCGWindowOwnerPID as String] as? Int32 != me,
                  let d = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: d),
                  b.height <= topInset + 2
            else { continue }
            sawStatusItem = true
            guard abs(b.minY - barTop) < 2,
                  b.minX >= notchRight - 1, b.minX < nearest
            else { continue }
            nearest = b.minX
        }
        Self.statusItemsAreWindows = sawStatusItem
        if sawStatusItem { return nearest - notchRight }

        let display = CGRect(x: screen.frame.minX, y: barTop, width: screen.frame.width, height: screen.frame.height)
        guard let lefts = MenuBarItems.lefts(onDisplay: display) else { return 0 }
        return MenuBarItems.freeRight(notchRight: notchRight, screenMaxX: screen.frame.maxX, lefts: lefts)
    }

    static var statusItemsAreWindows = true

    var displayName: String? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    var isUnderFullScreen: Bool {
        guard let name = displayName else { return false }
        return Self.isUnderFullScreen(display: name, spaces: ManagedSpaces.copy())
    }

    var fullScreenSpaces: Set<Int> {
        guard let name = displayName else { return [] }
        return Self.fullScreenSpaces(display: name, spaces: ManagedSpaces.copy())
    }

    private static func entry(display: String, spaces: [[String: Any]]) -> [String: Any]? {
        spaces.count == 1 ? spaces.first
            : spaces.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(display) == .orderedSame }
    }

    static func isUnderFullScreen(display: String, spaces: [[String: Any]]) -> Bool {
        let current = entry(display: display, spaces: spaces)?["Current Space"] as? [String: Any]
        return current?["type"] as? Int == ManagedSpaces.fullScreenType
    }

    static func fullScreenSpaces(display: String, spaces: [[String: Any]]) -> Set<Int> {
        let all = entry(display: display, spaces: spaces)?["Spaces"] as? [[String: Any]] ?? []
        return Set(all.filter { $0["type"] as? Int == ManagedSpaces.fullScreenType }
            .compactMap { $0["ManagedSpaceID"] as? Int })
    }

    static func revealsMenuBar(pointer: CGPoint, screen: CGRect, barHeight: CGFloat, shown: Bool) -> Bool {
        guard pointer.x >= screen.minX, pointer.x < screen.maxX, pointer.y <= screen.maxY else { return false }
        if pointer.y >= screen.maxY - 1 { return true }
        return shown && pointer.y >= screen.maxY - barHeight
    }

    func windowFrame() -> NSRect {
        let l = max(open.width, alert.width)
        let a = max(open.height, alert.height)
        return NSRect(x: screen.frame.midX - l / 2,
                      y: screen.frame.maxY - a,
                      width: l, height: a)
    }

    func rect(_ size: CGSize, shift: CGFloat = 0) -> NSRect {
        NSRect(x: screen.frame.midX + shift - size.width / 2,
               y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }

    static func current() -> NotchGeometry {
        let notched = NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
        return NotchGeometry(screen: notched ?? NSScreen.main ?? NSScreen.screens[0])
    }
}

enum ManagedSpaces {
    static let fullScreenType = 4

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let symbols: (MainConnection, CopyDisplaySpaces)? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let main = dlsym(h, "CGSMainConnectionID"),
              let copy = dlsym(h, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return (unsafeBitCast(main, to: MainConnection.self), unsafeBitCast(copy, to: CopyDisplaySpaces.self))
    }()

    static func copy() -> [[String: Any]] {
        guard let (main, copy) = symbols else { return [] }
        return copy(main())?.takeRetainedValue() as? [[String: Any]] ?? []
    }

    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let spacesForWindows: CopySpacesForWindows? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let f = dlsym(h, "CGSCopySpacesForWindows")
        else { return nil }
        return unsafeBitCast(f, to: CopySpacesForWindows.self)
    }()

    static func spaces(of window: CGWindowID) -> Set<Int> {
        guard let (main, _) = symbols, let f = spacesForWindows else { return [] }
        let ids = [NSNumber(value: window)] as CFArray
        return Set(f(main(), 7, ids)?.takeRetainedValue() as? [Int] ?? [])
    }
}

struct Wings: Equatable {
    let left: CGFloat
    let right: CGFloat

    var countOnLeft: Bool { right == 0 }
    var shift: CGFloat { (right - left) / 2 }
}
