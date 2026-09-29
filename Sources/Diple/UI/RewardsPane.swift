import SwiftUI

struct RewardsPane: View {
    @ObservedObject var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 12)]

    var body: some View {
        Form {
            Section {
                Toggle("Rewards (beta)", isOn: $model.settings.rewardsBeta)
                if model.settings.rewardsBeta {
                    Toggle("Preview every sticker", isOn: $model.settings.rewardsPreview)
                        .help("Reveals every sheet in the collection with a Try it button that plays the claim. For testing; nothing is added to your collection.")
                    Picker("When you review", selection: $model.settings.paperStyle) {
                        ForEach(PaperStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Text("Every review you send moves you one step along this quarter's trail, and stickers wait at 10, 30, 60, 100, 180 and 300 reviews. Any review counts the same: commenting, approving or asking for changes. Diple never judges how you review.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.settings.rewardsBeta {
                if model.settings.rewardsProfile == nil || editing {
                    onboarding
                } else if let p = model.settings.rewardsProfile {
                    Section("Your journey") {
                        LabeledContent("You", value: p.role.title)
                        LabeledContent("Why you review", value: p.reason.title)
                        HStack {
                            Button("Edit") { draft = p; editing = true }
                            Spacer()
                            Button("Open the collection") { Windows.shared.openMain(model, collection: true) }
                        }
                    }
                }
            }
            Section("\(StickerSheet.current.title) · \(owned) of \(StickerSheet.current.stickers.count)") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(StickerSheet.current.stickers) { a in cell(a) }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    @State private var draft = RewardsProfile()
    @State private var editing = false

    private var onboarding: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Two questions before your first sticker")
                    .font(.system(size: 13, weight: .semibold))
                Text("They shape the characters you will meet along the trail. Only this Mac keeps them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Picker("What do you do?", selection: $draft.role) {
                ForEach(RewardsProfile.Role.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Picker("Why review more?", selection: $draft.reason) {
                ForEach(RewardsProfile.Reason.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            HStack {
                Spacer()
                Button(editing ? "Save" : "Start") {
                    model.settings.rewardsProfile = draft
                    editing = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var owned: Int { StickerSheet.current.stickers.filter { (model.artifacts[$0.id] ?? 0) > 0 }.count }

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
