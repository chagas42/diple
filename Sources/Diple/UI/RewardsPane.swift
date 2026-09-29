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
            if model.settings.rewardsBeta {
                if model.settings.rewardsProfile == nil || editing {
                    onboarding
                } else if let p = model.settings.rewardsProfile {
                    Section("Your journey") {
                        LabeledContent("You", value: p.role.title)
                        LabeledContent("Why you review", value: p.reason.title)
                        LabeledContent("Daily goal", value: p.dailyGoal == 1 ? "1 review" : "\(p.dailyGoal) reviews")
                        HStack {
                            Button("Edit") { draft = p; editing = true }
                            Spacer()
                            Button("Open the collection") { Windows.shared.openMain(model, collection: true) }
                        }
                    }
                }
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

    @State private var draft = RewardsProfile()
    @State private var editing = false

    private var onboarding: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Three questions before your first artifact")
                    .font(.system(size: 13, weight: .semibold))
                Text("They set what counts most, and your daily goal. Only this Mac keeps them.")
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
            Stepper(value: $draft.dailyGoal, in: 1...10) {
                Text("Daily goal: \(draft.dailyGoal) \(draft.dailyGoal == 1 ? "review" : "reviews")")
            }
            if draft.reason == .unblock {
                Text("Answering a review request within two hours makes a rare artifact three times as likely.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
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
