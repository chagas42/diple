import AppKit
import SwiftUI

@MainActor
final class ClaimWindow {
    let panel: NSPanel
    private var onKept: (() -> Void)?
    private let coin: NSSound? = {
        let url = ["zipper", "coin"].lazy
            .flatMap { name in ["wav", "m4a", "mp3", "aiff"].lazy.map { (name, $0) } }
            .compactMap { Bundle.main.url(forResource: $0.0, withExtension: $0.1, subdirectory: "Sounds") }
            .first
        guard let url, let s = NSSound(contentsOf: url, byReference: false)
        else { return nil }
        s.volume = 0.35
        return s
    }()

    static let size = CGSize(width: 340, height: 600)
    static var autoKeep: Duration?

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

    var isShowing: Bool { panel.isVisible }

    func show(_ reward: Reward, under g: NotchGeometry, then kept: @escaping () -> Void) {
        onKept = kept
        let s = Self.size
        panel.setFrame(NSRect(x: g.screen.frame.midX - s.width / 2,
                              y: g.screen.frame.maxY - g.topInset - 120 - s.height,
                              width: s.width, height: s.height), display: false)
        panel.contentView = NSHostingView(rootView: Stage(
            reward: reward,
            landed: { [weak self] in self?.chime() },
            done: { [weak self] in self?.close() }
        ))
        panel.orderFrontRegardless()
    }

    private func chime() {
        coin?.stop()
        coin?.play()
    }

    private func close() {
        panel.orderOut(nil)
        panel.contentView = nil
        onKept?()
    }

    private struct Stage: View {
        let reward: Reward
        let landed: () -> Void
        let done: () -> Void

        enum Step { case showing, dropping, bagged, leaving }
        @State private var step = Step.showing
        @State private var squash = false

        var body: some View {
            VStack(spacing: 0) {
                ClaimCard(reward: reward, leaving: false)
                    .scaleEffect(step == .showing ? 1 : 0.14)
                    .offset(y: step == .showing ? 0 : 300)
                    .opacity(step == .showing || step == .dropping ? 1 : 0)
                    .frame(height: 440, alignment: .top)
                    .zIndex(1)
                Spacer(minLength: 0)
                ZStack {
                    PixelArt(artifact: Self.bag)
                        .frame(width: 78, height: 78)
                        .scaleEffect(x: squash ? 1.18 : 1, y: squash ? 0.82 : 1, anchor: .bottom)
                        .shadow(color: reward.artifact.rarity.color.opacity(step == .bagged ? 0.8 : 0), radius: 12)
                    Text("+1 · in your backpack")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(reward.artifact.rarity.color.opacity(0.9), in: Capsule())
                        .offset(y: step == .bagged ? -62 : -44)
                        .opacity(step == .bagged ? 1 : 0)
                }
                .frame(height: 120)
                .opacity(step == .showing || step == .leaving ? 0 : 1)
                .offset(y: step == .showing ? 30 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: keep)
            .task {
                guard let wait = ClaimWindow.autoKeep else { return }
                try? await Task.sleep(for: wait)
                keep()
            }
        }

        private func keep() {
            guard step == .showing else { return }
            Task { @MainActor in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step = .dropping }
                try? await Task.sleep(for: .milliseconds(380))
                landed()
                withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { step = .bagged; squash = true }
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { squash = false }
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.easeIn(duration: 0.3)) { step = .leaving }
                try? await Task.sleep(for: .milliseconds(320))
                done()
            }
        }

        static let bag = Artifact(
            id: "backpack", name: "Backpack", flavor: "", rarity: .common,
            pixels: [
                "................",
                ".....TTTTTT.....",
                "....T......T....",
                "...BBBBBBBBBB...",
                "..BBBLLLLLLBBB..",
                "..BBBLLLLLLBBB..",
                "..BBBBBBBBBBBB..",
                "..BBZZZZZZZZBB..",
                "..BBPPPPPPPPBB..",
                "..BBPPPPPPPPBB..",
                "..BBPPPKPPPPBB..",
                "..BBPPPPPPPPBB..",
                "..BBPPPPPPPPBB..",
                "..DBBBBBBBBBBD..",
                "...DD......DD...",
                "................",
            ],
            palette: ["B": 0x3B4A5C, "L": 0xC9CED6, "P": 0x4E6078, "Z": 0xE0B34A, "T": 0x2C3746, "K": 0xE0B34A, "D": 0x2A3542]
        )
    }
}
