import SceneKit
import SwiftUI

struct StickerInspector: View {
    let artifact: Artifact
    let earned: [EarnedArtifact]
    let close: () -> Void

    @State private var hint = true

    private var caption: String {
        guard let first = earned.first else { return artifact.rarity.title }
        return "\(Trail.season(of: first.at)) · \(artifact.rarity.title)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SceneView(scene: StickerShape.scene(artifact, caption: caption),
                      options: [.allowsCameraControl])
                .frame(width: 480, height: 560)
            details
                .padding(14)
        }
        .overlay(alignment: .topLeading) {
            Label("Drag to turn it over, scroll to zoom", systemImage: "hand.draw")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())
                .padding(14)
                .opacity(hint ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: hint)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .padding(12)
        }
        .environment(\.colorScheme, .dark)
        .task {
            try? await Task.sleep(for: .seconds(3))
            hint = false
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(artifact.rarity.title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.black.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(artifact.rarity.color, in: Capsule())
            Text(artifact.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(artifact.flavor)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            if !earned.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(earned) { e in
                        HStack(spacing: 6) {
                            Text("> \(e.verdict.word)")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(e.verdict == .commented ? .white.opacity(0.6) : e.verdict.color)
                            Text(e.pr ?? "")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer(minLength: 8)
                            Text(e.at.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
