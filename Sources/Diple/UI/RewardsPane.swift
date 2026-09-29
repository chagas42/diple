import SwiftUI

struct RewardsPane: View {
    @ObservedObject var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 12)]

    var body: some View {
        Form {
            Section {
                Toggle("Rewards (beta)", isOn: $model.settings.rewardsBeta)
                Text("Each review you send drops an artifact from the notch. Answering a review request within two hours makes a rare one more likely. Approving never counts more than commenting or asking for changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Collection · \(owned) of \(Artifact.catalog.count)") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Artifact.catalog) { a in cell(a) }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var owned: Int { Artifact.catalog.filter { (model.artifacts[$0.id] ?? 0) > 0 }.count }

    private func cell(_ a: Artifact) -> some View {
        let count = model.artifacts[a.id] ?? 0
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(a.rarity.color.opacity(count > 0 ? 0.18 : 0.06))
                PixelArt(artifact: a)
                    .padding(10)
                    .saturation(count > 0 ? 1 : 0)
                    .brightness(count > 0 ? 0 : -0.5)
                    .opacity(count > 0 ? 1 : 0.35)
            }
            .frame(width: 64, height: 64)
            Text(count > 0 ? a.name : "???")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(count > 1 ? "\(a.rarity.title) · ×\(count)" : a.rarity.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(a.rarity.color)
        }
        .frame(maxWidth: .infinity)
    }
}
