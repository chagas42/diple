import SwiftUI

struct CollectionView: View {
    @ObservedObject var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    private var owned: Int { Artifact.catalog.filter { (model.artifacts[$0.id] ?? 0) > 0 }.count }
    private var total: Int { model.artifacts.values.reduce(0, +) }
    private var rarest: Artifact? {
        Artifact.catalog.filter { (model.artifacts[$0.id] ?? 0) > 0 }.max { $0.rarity < $1.rarity }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                trail
                HStack(spacing: 12) {
                    stat("\(owned)/\(Artifact.catalog.count)", "stickers found")
                    stat("\(total)", total == 1 ? "sticker earned" : "stickers earned")
                    stat(rarest?.rarity.title ?? "—", "rarest so far", tint: rarest?.rarity.color)
                }
                rarityBar
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Artifact.catalog) { cell($0) }
                }
            }
            .padding(20)
        }
        .navigationTitle("Collection")
    }

    private var trail: some View {
        let count = model.seasonReviews
        let next = Trail.milestones.first { $0 > count }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Trail.season(of: Date())) trail")
                    .font(.system(size: 15, weight: .bold))
                Text("\(count) \(count == 1 ? "review" : "reviews")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(next.map { "next sticker at \($0)" } ?? "trail complete \u{2713}")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { g in
                let w = g.size.width
                let last = Double(Trail.milestones.last!)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule().fill(Color.accentColor)
                        .frame(width: w * min(1, Double(count) / last), height: 4)
                    ForEach(Array(Trail.milestones.enumerated()), id: \.offset) { i, m in
                        let r = Trail.rarities[i]
                        let reached = count >= m
                        VStack(spacing: 3) {
                            Circle()
                                .fill(reached ? r.color : Color.secondary.opacity(0.25))
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(r.color, lineWidth: 1.5))
                            Text("\(m)")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(reached ? r.color : .secondary)
                        }
                        .offset(x: w * Double(m) / last - 5.5, y: 9)
                    }
                }
            }
            .frame(height: 34)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint ?? .primary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rarityBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By rarity")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Rarity.allCases, id: \.self) { r in
                    let pool = Artifact.catalog.filter { $0.rarity == r }
                    let have = pool.filter { (model.artifacts[$0.id] ?? 0) > 0 }.count
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(r.color.opacity(0.18))
                            .overlay(alignment: .leading) {
                                GeometryReader { g in
                                    Capsule().fill(r.color)
                                        .frame(width: g.size.width * CGFloat(have) / CGFloat(max(1, pool.count)))
                                }
                            }
                            .frame(height: 5)
                        Text("\(r.title) \(have)/\(pool.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(r.color)
                    }
                }
            }
        }
    }

    private func cell(_ a: Artifact) -> some View {
        let count = model.artifacts[a.id] ?? 0
        return VStack(spacing: 8) {
            Group {
                if count > 0 {
                    ArtifactTile(artifact: a, side: 96)
                } else {
                    PixelArt(artifact: a)
                        .padding(14)
                        .frame(width: 96, height: 96)
                        .brightness(-0.6)
                        .saturation(0)
                        .opacity(0.35)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
            Text(count > 0 ? a.name : "???")
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(count > 1 ? "\(a.rarity.title) · ×\(count)" : a.rarity.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(a.rarity.color)
            if count > 0 {
                Text(a.flavor)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct JourneyView: View {
    @ObservedObject var model: AppModel

    private var days: [(day: Date, items: [EarnedArtifact])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: model.earned) { cal.startOfDay(for: $0.at) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.at > $1.at }) }
    }

    var body: some View {
        Group {
            if model.earned.isEmpty {
                ContentUnavailableView(
                    "No stickers yet",
                    systemImage: "sparkles",
                    description: Text("Your first sticker waits at \(Trail.milestones[0]) reviews this quarter.")
                )
            } else {
                List {
                    ForEach(days, id: \.day) { d in
                        Section(d.day.formatted(.dateTime.weekday(.wide).day().month())) {
                            ForEach(d.items) { row($0) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Journey")
    }

    private func row(_ e: EarnedArtifact) -> some View {
        let a = Artifact.named(e.artifact)
        return HStack(spacing: 10) {
            if let a {
                PixelArt(artifact: a)
                    .padding(4)
                    .frame(width: 32, height: 32)
                    .background(a.rarity.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a?.name ?? e.artifact)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("> \(e.verdict.word)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(e.verdict == .commented ? .secondary : e.verdict.color)
                }
                Text(e.pr ?? "")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if e.claimedAt == nil {
                Image(systemName: "gift.fill")
                    .foregroundStyle(a?.rarity.color ?? .secondary)
                    .help("Not in your backpack yet")
            }
            Text(e.at.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
