import AppKit
import SwiftUI

@MainActor
final class ClaimWindow {
    private let panel: NSPanel
    private var onKept: (() -> Void)?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
    }

    func show(_ reward: Reward, under g: NotchGeometry, then kept: @escaping () -> Void) {
        onKept = kept
        let size = CGSize(width: 340, height: 520)
        panel.setFrame(NSRect(x: g.screen.frame.midX - size.width / 2,
                              y: g.screen.frame.maxY - g.topInset - 60 - size.height,
                              width: size.width, height: size.height), display: false)
        panel.contentView = NSHostingView(rootView: Stage(reward: reward) { [weak self] in self?.keep() })
        panel.orderFrontRegardless()
    }

    private func keep() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.contentView = nil
            self.onKept?()
        }
    }

    private struct Stage: View {
        let reward: Reward
        let keep: () -> Void
        @State private var leaving = false

        var body: some View {
            ClaimCard(reward: reward, leaving: leaving)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !leaving else { return }
                    withAnimation(.easeIn(duration: 0.4)) { leaving = true }
                    keep()
                }
        }
    }
}
