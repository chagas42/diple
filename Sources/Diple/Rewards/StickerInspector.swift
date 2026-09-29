import SceneKit
import SwiftUI

struct StickerInspector: View {
    let artifact: Artifact
    let earned: [EarnedArtifact]
    let close: () -> Void

    private var caption: String {
        guard let first = earned.first else { return artifact.rarity.title }
        return "\(Trail.season(of: first.at)) · \(artifact.rarity.title)"
    }

    var body: some View {
        VStack(spacing: 14) {
            SceneView(scene: StickerShape.scene(artifact, caption: caption),
                      options: [.allowsCameraControl])
                .frame(width: 360, height: 300)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Drag to turn it over · scroll to zoom")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(artifact.rarity.title.uppercased())
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(artifact.rarity.color)
                Text(artifact.name)
                    .font(.system(size: 17, weight: .bold))
                Text(artifact.flavor)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !earned.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(earned) { e in
                        HStack {
                            Text("> \(e.verdict.word)")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(e.verdict == .commented ? .secondary : e.verdict.color)
                            Text(e.pr ?? "")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(e.at.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Button("Done", action: close)
                .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .frame(width: 420)
    }
}
