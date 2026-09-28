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
        CGSize(width: notchWidth + wing * 2, height: topInset)
    }

    var open: CGSize { CGSize(width: 680, height: 330) }

    var alert: CGSize { CGSize(width: 580, height: 196) }

    var asa: CGFloat { 42 }

    static let minWing: CGFloat = 18

    var wing: CGFloat {
        let fits = min(asa, freeRight - 6)
        return fits >= Self.minWing ? fits : 0
    }

    var freeRight: CGFloat {
        guard hasNotch,
              let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return asa + 6 }

        let notchRight = screen.frame.midX + notchWidth / 2
        let barTop = primary.frame.maxY - screen.frame.maxY
        let me = ProcessInfo.processInfo.processIdentifier
        var nearest = screen.frame.maxX

        for w in list {
            guard w[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  w[kCGWindowOwnerPID as String] as? Int32 != me,
                  let d = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: d),
                  abs(b.minY - barTop) < 2, b.height <= topInset + 2,
                  b.minX >= notchRight - 1, b.minX < nearest
            else { continue }
            nearest = b.minX
        }
        return nearest - notchRight
    }

    func windowFrame() -> NSRect {
        let l = max(open.width, alert.width)
        let a = max(open.height, alert.height)
        return NSRect(x: screen.frame.midX - l / 2,
                      y: screen.frame.maxY - a,
                      width: l, height: a)
    }

    func rect(_ size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2,
               y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }

    static func current() -> NotchGeometry {
        let notched = NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
        return NotchGeometry(screen: notched ?? NSScreen.main ?? NSScreen.screens[0])
    }
}
