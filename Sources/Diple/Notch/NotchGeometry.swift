import AppKit

@MainActor
struct NotchGeometry {
    let screen: NSScreen

    var hasNotch: Bool { screen.auxiliaryTopLeftArea != nil }

    var topInset: CGFloat {
        hasNotch ? screen.safeAreaInsets.top : 32
    }

    var notchWidth: CGFloat {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return 185 }
        return max(0, screen.frame.width - left.width - right.width)
    }

    var closed: CGSize { CGSize(width: notchWidth, height: topInset) }

    var active: CGSize {
        CGSize(width: notchWidth + wing * 2, height: topInset)
    }

    var open: CGSize { CGSize(width: 680, height: 330) }

    var alert: CGSize { CGSize(width: 580, height: 196) }

    var wing: CGFloat { 42 }

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
