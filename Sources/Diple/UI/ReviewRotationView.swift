import SwiftUI
import os

@MainActor final class RotationPreview: ObservableObject {
    @Published var people: [Person] = []
    @Published var rotation = ReviewRotation()
}

struct ReviewRotationPanel: View {
    @ObservedObject var model: AppModel
    var preview: RotationPreview?
    @State private var teams: [GitHubClient.TeamRef]?
    @State private var slug: String?

    private var org: String { model.org }
    private var team: GitHubClient.TeamRef? { teams?.first { $0.slug == slug } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if preview == nil {
                Text(Self.why).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if org.isEmpty {
                note("Pick an organization first. The rotation belongs to a GitHub team in it.")
            } else if let teams {
                if teams.isEmpty {
                    note("You don't own \(org) or maintain any of its teams, so there is no rotation for you to change.")
                } else {
                    if teams.count > 1 {
                        Wrap(spacing: 6) {
                            ForEach(teams) { t in chip(t) }
                        }
                    }
                    if let team {
                        ReviewRotationEditor(model: model, org: org, team: team, preview: preview).id(team.slug)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: org) { await load() }
    }

    static let why = "When a pull request asks a whole team for review, everyone gets pinged and the reviews pile on whoever answers first. With a rotation, GitHub hands each one to a few people, so they spread across the team."

    private func load() async {
        teams = nil
        guard !org.isEmpty else { return }
        let mine = Set(await model.myTeams(in: org).map(\.slug))
        let picked = Set(model.settings.teams(in: org))
        teams = await model.orgTeams(in: org).filter(\.canAdminister)
        slug = (teams?.first { picked.contains($0.slug) } ?? teams?.first { mine.contains($0.slug) } ?? teams?.first)?.slug
    }

    private func chip(_ t: GitHubClient.TeamRef) -> some View {
        let on = t.slug == slug
        return Button { slug = t.slug } label: {
            HStack(spacing: 4) {
                if !t.canAdminister {
                    Image(systemName: "lock.fill").font(.system(size: 8.5))
                }
                Text(t.name).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                Text("\(t.members)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(on ? Color.white.opacity(0.75) : .secondary)
            }
            .foregroundStyle(on ? Color.white : .primary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(t.canAdminister ? "\(t.name), \(t.members) people" : "\(t.name), \(t.members) people. You can only view it.")
        .animation(.easeOut(duration: 0.15), value: on)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct ReviewRotationEditor: View {
    @ObservedObject var model: AppModel
    let org: String
    let team: GitHubClient.TeamRef
    var preview: RotationPreview?

    enum Status: Equatable {
        case loading, idle, unreadable, saving, saved, needsScope, failed(String), dryRun(String)
    }

    @State private var saved: ReviewRotation?
    @State private var draft = ReviewRotation()
    @State private var status = Status.loading
    @State private var access = TeamAccess.member
    @State private var people: [Person] = []
    @State private var fit: TeamFit?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch status {
            case .loading:
                ProgressView().controlSize(.small)
            case .unreadable:
                Text("Diple could not read this team's review settings.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            case .failed(let message) where saved == nil:
                HStack(alignment: .firstTextBaseline) {
                    Text("Couldn't read \(team.name): \(message)").font(.system(size: 11.5)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Button("Try again") { Task { await load() } }.controlSize(.small)
                }
            default:
                statusLine(fit)
                if preview == nil, !people.isEmpty {
                    RotationDiagram(people: people, rotation: draft)
                }
                if access != .member { editor } else { readOnly }
            }
        }
        .font(.system(size: 13))
        .task { await load() }
        .onChange(of: draft) { _, d in preview?.rotation = d }
    }

    private var readOnly: some View {
        Text(saved?.summary ?? "").fixedSize(horizontal: false, vertical: true)
    }

    private func statusLine(_ fit: TeamFit?) -> some View {
        let warns = fit.map { $0.verdict != .works } ?? false
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: access == .member ? "lock.fill" : "checkmark.shield.fill")
                .foregroundStyle(access == .member ? Color.secondary : Color.green)
            Text(access.short(org: org))
                .foregroundStyle(access == .member ? Color.secondary : Color.green)
            if let fit {
                Text("·").foregroundStyle(.tertiary)
                Image(systemName: warns ? "info.circle" : "checkmark.circle")
                    .foregroundStyle(.secondary)
                Text(fit.headline(team: team.name))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11.5))
        .help([access.explanation(org: org, team: team.name), fit?.explanation(org: org, team: team.name, slug: team.slug)]
              .compactMap { $0 }.joined(separator: "\n\n"))
    }

    @ViewBuilder private var editor: some View {
        HStack {
            Toggle("Pick reviewers automatically", isOn: $draft.enabled)
            Spacer(minLength: 8)
            Button {
                Task { await save() }
            } label: {
                if status == .saving { ProgressView().controlSize(.small) } else { Text("Save") }
            }
            .disabled(draft == saved || status == .saving)
        }
        HStack(spacing: 10) {
            Picker("", selection: $draft.algorithm) {
                ForEach(ReviewRotation.Algorithm.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(draft.algorithm.detail)
            Stepper("\(draft.reviewers) per PR", value: $draft.reviewers, in: ReviewRotation.reviewerRange)
                .fixedSize()
            Toggle("Notify only them", isOn: Binding(get: { !draft.notifyTeam }, set: { draft.notifyTeam = !$0 }))
                .fixedSize()
                .help("Off: GitHub also notifies the whole team. On: only the people it picks.")
        }
        .disabled(!draft.enabled)
        feedback
    }

    @ViewBuilder private var feedback: some View {
        switch status {
        case .saved:
            Label("Saved on GitHub", systemImage: "checkmark.circle.fill").font(.system(size: 11.5)).foregroundStyle(.green)
        case .needsScope:
            VStack(alignment: .leading, spacing: 6) {
                Text("Your gh token can't change team settings. Run this, then save again:")
                    .font(.system(size: 11.5)).foregroundStyle(.orange)
                HStack {
                    Text(ReviewRotation.scopeCommand).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    CopyButton(text: ReviewRotation.scopeCommand, label: "Copy")
                }
            }
        case .failed(let message):
            HStack(alignment: .firstTextBaseline) {
                Text(message).font(.system(size: 11.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                CopyButton(text: message, label: "Copy").controlSize(.small)
            }
        case .dryRun(let mutation):
            HStack {
                Label("Dry run: nothing was sent to GitHub.", systemImage: "eye").font(.system(size: 11.5)).foregroundStyle(.orange)
                CopyButton(text: mutation, label: "Copy mutation").controlSize(.small)
            }
        default:
            EmptyView()
        }
    }

    static let log = Logger(subsystem: "com.chagas42.diple", category: "rotation")

    private func load() async {
        status = .loading
        let read: RotationRead?
        do {
            read = try await model.rotation(org: org, team: team)
        } catch is CancellationError {
            return
        } catch {
            Self.log.error("read \(org, privacy: .public)/\(team.slug, privacy: .public): \(String(describing: error), privacy: .public)")
            status = .failed(error.localizedDescription)
            return
        }
        guard let read else {
            Self.log.error("read \(org, privacy: .public)/\(team.slug, privacy: .public): no rotation fields")
            status = .unreadable
            return
        }
        async let found = model.fit(org: org, team: team)
        let members = Array(await model.members(org: org, team: team).prefix(RotationDiagram.most))
        fit = await found
        access = TeamAccess(team: team, orgAdmin: read.orgAdmin)
        saved = read.rotation
        draft = read.rotation
        people = members
        status = .idle
        preview?.people = members
        preview?.rotation = read.rotation
    }

    private func save() async {
        status = .saving
        do {
            switch try await model.saveRotation(draft, team: team) {
            case .saved(let r):
                saved = r
                draft = r
                status = .saved
            case .dryRun(let mutation):
                status = .dryRun(mutation)
            }
        } catch where ReviewRotation.needsScope(error) {
            status = .needsScope
        } catch {
            Self.log.error("save \(org, privacy: .public)/\(team.slug, privacy: .public): \(String(describing: error), privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }
}

struct ReviewRotationPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                ReviewRotationPanel(model: model)
            } footer: {
                Text("Uses GitHub's own team review assignment. When a pull request asks the team for a review, GitHub swaps the team for the people it picks.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct RotationDiagram: View {
    let people: [Person]
    let rotation: ReviewRotation

    static let most = 10
    static let height: CGFloat = 176
    static let busy = 4

    @State private var sim = RotationSimulation(people: 0)
    @State private var shown: [Int] = []
    @State private var turn = 0
    @State private var number = 120
    @State private var author = 0
    @State private var picked: [Int] = []
    @State private var incoming = false
    @State private var landed = false
    @State private var faded = false
    @State private var caption = ""

    private var color: Color { rotation.enabled ? .green : .orange }
    private var turns: Bool { rotation.enabled && rotation.algorithm == .roundRobin }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let slot = w / CGFloat(max(people.count, 1))
            let size = min(30, slot - 8)
            let start = CGPoint(x: w / 2, y: 16)
            let x = { (i: Int) in slot * (CGFloat(i) + 0.5) }
            ZStack {
                chip.position(start).opacity(incoming ? 1 : 0).scaleEffect(incoming ? 1 : 0.6)
                ForEach(Array(people.enumerated()), id: \.offset) { i, p in
                    stack(i, width: size).position(x: x(i), y: 62)
                    avatar(p, index: i, size: size).position(x: x(i), y: 98)
                    Text(first(i)).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).frame(width: slot - 2).position(x: x(i), y: 126)
                }
                ForEach(Array(picked.enumerated()), id: \.element) { k, i in
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 12)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(color))
                        .position(landed ? CGPoint(x: x(i), y: 72) : CGPoint(x: start.x, y: start.y + 14))
                        .scaleEffect(landed ? 0.8 : 1)
                        .opacity(faded ? 0 : 1)
                        .animation(.easeInOut(duration: 0.8).delay(Double(k) * 0.07), value: landed)
                        .animation(.easeOut(duration: 0.25), value: faded)
                }
                if turns, people.indices.contains(turn) {
                    VStack(spacing: 0) {
                        Image(systemName: "arrowtriangle.up.fill").font(.system(size: 8))
                        Text("next").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .position(x: x(turn), y: 144)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: turn)
                }
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: w - 16).position(x: w / 2, y: 164)
            }
        }
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        .task(id: "\(rotation)\(people.map(\.login))") { await play() }
    }

    private var chip: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.pull").font(.system(size: 10, weight: .bold))
            Text("#\(number) by \(first(author))").font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6)))
    }

    private func stack(_ i: Int, width: CGFloat) -> some View {
        let load = shown.indices.contains(i) ? shown[i] : 0
        return VStack(spacing: 2) {
            ForEach(0..<min(load, 6), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(load >= Self.busy ? Color.red.opacity(0.85) : Color.primary.opacity(0.35))
                    .frame(width: width * 0.7, height: 4)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .frame(height: 40, alignment: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: load)
    }

    private func avatar(_ p: Person, index i: Int, size: CGFloat) -> some View {
        let on = faded && picked.contains(i)
        return CachedAvatar(url: p.avatar) {
            Circle().fill(Color(hue: Double(i) / Double(max(people.count, 1)), saturation: 0.3, brightness: 0.85))
                .overlay(Text(p.initials).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.black.opacity(0.6)))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(on ? color : i == author && incoming ? Color.accentColor : .clear, lineWidth: 2.5))
        .scaleEffect(on ? 1.18 : 1)
        .opacity(i == author && incoming ? 0.45 : 1)
        .help(p.name)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: on)
    }

    private func first(_ i: Int) -> String {
        guard people.indices.contains(i) else { return "" }
        let p = people[i]
        return p.name == p.login ? "@" + p.login : String(p.name.split(separator: " ").first ?? "")
    }

    private var rule: String {
        guard rotation.enabled else { return "Off: everyone is pinged" }
        return rotation.algorithm == .roundRobin ? "Round robin: whoever's turn it is, busy or not"
                                                 : "Load balance: the shortest piles first"
    }

    private func play() async {
        sim = RotationSimulation(people: people.count)
        shown = sim.loads
        turn = sim.cursor
        picked = []
        incoming = false
        landed = false
        faded = false
        author = 0
        caption = rule
        guard people.count > 1 else { return }
        try? await Task.sleep(for: .milliseconds(900))
        while !Task.isCancelled {
            author = (number * 7) % people.count
            picked = []
            landed = false
            faded = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { incoming = true; caption = rule }
            try? await Task.sleep(for: .milliseconds(900))
            let chosen = sim.pick(rotation, author: author)
            picked = chosen
            try? await Task.sleep(for: .milliseconds(60))
            landed = true
            try? await Task.sleep(for: .milliseconds(800 + chosen.count * 70))
            faded = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                shown = sim.loads
                turn = sim.cursor
                let names = chosen.prefix(2).map(first).joined(separator: ", ") + (chosen.count > 2 ? " +\(chosen.count - 2)" : "")
                caption = rotation.enabled ? "\(rule) → \(names)"
                    : "Off: everyone else is pinged (\(chosen.count) \(chosen.count == 1 ? "person" : "people"))"
            }
            try? await Task.sleep(for: .milliseconds(1900))
            sim.settle(chosen.count)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { incoming = false; shown = sim.loads }
            try? await Task.sleep(for: .milliseconds(500))
            number += 1
        }
    }
}

struct Wrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        var height: CGFloat = 0
        var width: CGFloat = 0
        for row in rows {
            let sizes = row.map { $0.sizeThatFits(.unspecified) }
            height += sizes.map(\.height).max() ?? 0
            width = max(width, sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0)))
        }
        height += spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let h = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for v in row {
                let size = v.sizeThatFits(.unspecified)
                v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += h + spacing
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        for v in subviews {
            let w = v.sizeThatFits(.unspecified).width
            if x > 0, x + w > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(v)
            x += w + spacing
        }
        return rows
    }
}
