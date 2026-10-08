import SwiftUI
import os

@MainActor final class RotationPreview: ObservableObject {
    @Published var people: [Person] = []
    @Published var rotation = ReviewRotation()
}

struct RotationSnapshot {
    var read: RotationRead?
    var people: [Person]?
    var fit: TeamFit?
    var fitKnown = false
}

@MainActor final class RotationEditing: ObservableObject {
    enum Status: Equatable {
        case loading, idle, unreadable, saving, saved, needsScope, failed(String), dryRun(String)
    }

    let model: AppModel
    let org: String
    let team: GitHubClient.TeamRef
    let preview: RotationPreview?

    @Published var saved: ReviewRotation?
    @Published var draft = ReviewRotation() { didSet { preview?.rotation = draft } }
    @Published var status = Status.loading
    @Published var access = TeamAccess.member
    @Published var people: [Person]?
    @Published var fit: TeamFit?
    @Published var fitKnown = false

    static let log = Logger(subsystem: "com.chagas42.diple", category: "rotation")

    private var key: String { "\(org)/\(team.slug)" }
    var loading: Bool { saved == nil && status == .loading }

    init(model: AppModel, org: String, team: GitHubClient.TeamRef, preview: RotationPreview?) {
        self.model = model
        self.org = org
        self.team = team
        self.preview = preview
        guard let cached = model.rotationCache["\(org)/\(team.slug)"] else { return }
        if let read = cached.read {
            access = TeamAccess(team: team, orgAdmin: read.orgAdmin)
            saved = read.rotation
            draft = read.rotation
            status = .idle
        }
        people = cached.people
        fit = cached.fit
        fitKnown = cached.fitKnown
        if let people = cached.people { preview?.people = people }
    }

    func load() async {
        if saved == nil { status = .loading }
        async let members = model.members(org: org, team: team)
        async let found = model.fit(org: org, team: team)
        do {
            guard let read = try await model.rotation(org: org, team: team) else {
                Self.log.error("read \(self.key, privacy: .public): no rotation fields")
                if saved == nil { status = .unreadable }
                return
            }
            access = TeamAccess(team: team, orgAdmin: read.orgAdmin)
            if saved == nil || draft == saved { draft = read.rotation }
            saved = read.rotation
            if status == .loading { status = .idle }
            model.rotationCache[key, default: RotationSnapshot()].read = read
        } catch is CancellationError {
            return
        } catch {
            Self.log.error("read \(self.key, privacy: .public): \(String(describing: error), privacy: .public)")
            if saved == nil { status = .failed(error.localizedDescription) }
            return
        }
        let list = Array(await members.prefix(RotationDiagram.most))
        people = list
        preview?.people = list
        model.rotationCache[key, default: RotationSnapshot()].people = list
        fit = await found
        fitKnown = true
        model.rotationCache[key, default: RotationSnapshot()].fit = fit
        model.rotationCache[key, default: RotationSnapshot()].fitKnown = true
    }

    func save() async {
        status = .saving
        do {
            switch try await model.saveRotation(draft, team: team) {
            case .saved(let r):
                saved = r
                draft = r
                status = .saved
                if let read = model.rotationCache[key]?.read {
                    model.rotationCache[key]?.read = RotationRead(rotation: r, orgAdmin: read.orgAdmin)
                }
            case .dryRun(let mutation):
                status = .dryRun(mutation)
            }
        } catch where ReviewRotation.needsScope(error) {
            status = .needsScope
        } catch {
            Self.log.error("save \(self.key, privacy: .public): \(String(describing: error), privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }
}

@MainActor enum RotationTeams {
    static func load(_ model: AppModel, org: String) async -> (teams: [GitHubClient.TeamRef], slug: String?) {
        let mine = Set(await model.myTeams(in: org).map(\.slug))
        let picked = Set(model.settings.teams(in: org))
        let teams = await model.orgTeams(in: org).filter(\.canAdminister)
        let slug = (teams.first { picked.contains($0.slug) } ?? teams.first { mine.contains($0.slug) } ?? teams.first)?.slug
        return (teams, slug)
    }

    static let why = "When a pull request asks a whole team for review, everyone gets pinged and the reviews pile on whoever answers first. With a rotation, GitHub hands each one to a few people, so they spread across the team."
    static let skeleton = ["Engineering", "Design", "Data"]
}

struct TeamChips: View {
    let teams: [GitHubClient.TeamRef]?
    @Binding var slug: String?

    var body: some View {
        Wrap(spacing: 6) {
            if let teams {
                ForEach(teams) { t in chip(t.name, count: t.members, on: t.slug == slug) { slug = t.slug } }
            } else {
                ForEach(RotationTeams.skeleton, id: \.self) { name in chip(name, count: 10, on: false) {} }
                    .redacted(reason: .placeholder)
            }
        }
        .animation(.easeOut(duration: 0.15), value: slug)
    }

    private func chip(_ name: String, count: Int, on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack(spacing: 4) {
                Text(name).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                Text("\(count)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(on ? Color.white.opacity(0.75) : .secondary)
            }
            .foregroundStyle(on ? Color.white : .primary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(name), \(count) people")
    }
}

struct RotationStatusLine: View {
    @ObservedObject var editing: RotationEditing

    var body: some View {
        let team = editing.team.name
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            Text(editing.access.short(org: editing.org)).foregroundStyle(.green)
            Text("·").foregroundStyle(.tertiary)
            Image(systemName: editing.fit.map { $0.verdict == .works } ?? true ? "checkmark.circle" : "info.circle")
                .foregroundStyle(.secondary)
            Group {
                if let fit = editing.fit {
                    Text(fit.headline(team: team))
                } else {
                    Text("000 PRs asked \(team) in 30 days").redacted(reason: editing.fitKnown ? [] : .placeholder)
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .font(.system(size: 11.5))
        .redacted(reason: editing.loading ? .placeholder : [])
        .help([editing.access.explanation(org: editing.org, team: team),
               editing.fit?.explanation(org: editing.org, team: team, slug: editing.team.slug)]
              .compactMap { $0 }.joined(separator: "\n\n"))
    }
}

struct RotationFeedback: View {
    @ObservedObject var editing: RotationEditing

    var body: some View {
        switch editing.status {
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
                Text(editing.saved == nil ? "Couldn't read \(editing.team.name): \(message)" : message)
                    .font(.system(size: 11.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if editing.saved == nil {
                    Button("Try again") { Task { await editing.load() } }.controlSize(.small)
                } else {
                    CopyButton(text: message, label: "Copy").controlSize(.small)
                }
            }
        case .unreadable:
            Text("Diple could not read this team's review settings.").font(.system(size: 11.5)).foregroundStyle(.secondary)
        case .dryRun(let mutation):
            HStack {
                Label("Dry run: nothing was sent to GitHub.", systemImage: "eye").font(.system(size: 11.5)).foregroundStyle(.orange)
                CopyButton(text: mutation, label: "Copy mutation").controlSize(.small)
            }
        default:
            EmptyView()
        }
    }
}

struct SaveRotationButton: View {
    @ObservedObject var editing: RotationEditing

    var body: some View {
        Button {
            Task { await editing.save() }
        } label: {
            Text("Save").opacity(editing.status == .saving ? 0 : 1)
                .overlay { if editing.status == .saving { ProgressView().controlSize(.small) } }
        }
        .disabled(editing.loading || editing.draft == editing.saved || editing.status == .saving)
    }
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
            if org.isEmpty {
                note("Pick an organization first. The rotation belongs to a GitHub team in it.")
            } else if teams?.isEmpty == true {
                note("You don't own \(org) or maintain any of its teams, so there is no rotation for you to change.")
            } else {
                TeamChips(teams: teams, slug: $slug)
                if let team {
                    CompactRotationEditor(model: model, org: org, team: team, preview: preview).id(team.slug)
                } else {
                    CompactRotationEditor.skeleton
                }
            }
        }
        .task(id: org) {
            guard !org.isEmpty else { return }
            (teams, slug) = await RotationTeams.load(model, org: org)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct CompactRotationEditor: View {
    @StateObject private var editing: RotationEditing

    init(model: AppModel, org: String, team: GitHubClient.TeamRef, preview: RotationPreview?) {
        _editing = StateObject(wrappedValue: RotationEditing(model: model, org: org, team: team, preview: preview))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RotationStatusLine(editing: editing)
            HStack {
                Toggle("Pick reviewers automatically", isOn: $editing.draft.enabled)
                Spacer(minLength: 8)
                SaveRotationButton(editing: editing)
            }
            HStack(spacing: 10) {
                Picker("", selection: $editing.draft.algorithm) {
                    ForEach(ReviewRotation.Algorithm.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(editing.draft.algorithm.detail)
                Stepper("\(editing.draft.reviewers) per PR", value: $editing.draft.reviewers, in: ReviewRotation.reviewerRange)
                    .fixedSize()
                Toggle("Notify only them", isOn: Binding(get: { !editing.draft.notifyTeam }, set: { editing.draft.notifyTeam = !$0 }))
                    .fixedSize()
                    .help("Off: GitHub also notifies the whole team. On: only the people it picks.")
            }
            .disabled(!editing.draft.enabled)
            RotationFeedback(editing: editing)
        }
        .font(.system(size: 13))
        .redacted(reason: editing.loading ? .placeholder : [])
        .disabled(editing.loading)
        .task { await editing.load() }
    }

    static var skeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Owner of the organization · 000 PRs asked the team in 30 days").font(.system(size: 11.5))
            Toggle("Pick reviewers automatically", isOn: .constant(true))
            HStack(spacing: 10) {
                Picker("", selection: .constant(ReviewRotation.Algorithm.loadBalance)) {
                    ForEach(ReviewRotation.Algorithm.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Stepper("2 per PR", value: .constant(2)).fixedSize()
                Toggle("Notify only them", isOn: .constant(false)).fixedSize()
            }
        }
        .font(.system(size: 13))
        .redacted(reason: .placeholder)
        .disabled(true)
    }
}

struct ReviewRotationPane: View {
    @ObservedObject var model: AppModel
    @State private var teams: [GitHubClient.TeamRef]?
    @State private var slug: String?

    private var org: String { model.org }
    private var team: GitHubClient.TeamRef? { teams?.first { $0.slug == slug } }

    var body: some View {
        Form {
            Section {
                TeamChips(teams: teams, slug: $slug)
            } header: {
                Text("Team")
            } footer: {
                Text(RotationTeams.why).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let team {
                RotationFormSections(model: model, org: org, team: team).id(team.slug)
            } else if teams?.isEmpty == true {
                Section {
                    Text("You don't own \(org) or maintain any of its teams, so there is no rotation for you to change.")
                        .foregroundStyle(.secondary)
                }
            } else {
                RotationFormSections.skeleton
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .task(id: org) {
            guard !org.isEmpty else { return }
            (teams, slug) = await RotationTeams.load(model, org: org)
        }
    }
}

struct RotationFormSections: View {
    @StateObject private var editing: RotationEditing

    init(model: AppModel, org: String, team: GitHubClient.TeamRef) {
        _editing = StateObject(wrappedValue: RotationEditing(model: model, org: org, team: team, preview: nil))
    }

    var body: some View {
        Group {
            Section {
                RotationStatusLine(editing: editing)
                RotationDiagram(people: editing.people ?? [], rotation: editing.draft)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
            }
            Section {
                Toggle("Pick reviewers automatically", isOn: $editing.draft.enabled)
                Group {
                    Picker("Algorithm", selection: $editing.draft.algorithm) {
                        ForEach(ReviewRotation.Algorithm.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Reviewers per pull request") {
                        HStack(spacing: 6) {
                            Text("\(editing.draft.reviewers)").monospacedDigit()
                            Stepper("", value: $editing.draft.reviewers, in: ReviewRotation.reviewerRange).labelsHidden()
                        }
                    }
                    Toggle("Notify only the people picked", isOn: Binding(get: { !editing.draft.notifyTeam }, set: { editing.draft.notifyTeam = !$0 }))
                }
                .disabled(!editing.draft.enabled)
            } header: {
                Text("Rotation")
            } footer: {
                Text(editing.draft.enabled ? editing.draft.algorithm.detail : "Off: everyone in the team is asked for every review.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    RotationFeedback(editing: editing)
                    Spacer(minLength: 8)
                    SaveRotationButton(editing: editing)
                }
            }
        }
        .redacted(reason: editing.loading ? .placeholder : [])
        .disabled(editing.loading)
        .task { await editing.load() }
    }

    static var skeleton: some View {
        Group {
            Section {
                Text("Owner of the organization · 000 PRs asked the team in 30 days").font(.system(size: 11.5))
                RotationDiagram(people: [], rotation: ReviewRotation(enabled: true))
            }
            Section("Rotation") {
                Toggle("Pick reviewers automatically", isOn: .constant(true))
                Picker("Algorithm", selection: .constant(ReviewRotation.Algorithm.loadBalance)) {
                    ForEach(ReviewRotation.Algorithm.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Reviewers per pull request") { Text("2") }
                Toggle("Notify only the people picked", isOn: .constant(false))
            }
        }
        .redacted(reason: .placeholder)
        .disabled(true)
    }
}

struct RotationDiagram: View {
    let people: [Person]
    let rotation: ReviewRotation

    static let most = 10
    static let height: CGFloat = 176
    static let busy = 4

    @State private var simulation = RotationSimulation(people: 0)
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
        if people.isEmpty { placeholder } else { stage }
    }

    private var placeholder: some View {
        HStack(spacing: 22) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(spacing: 6) {
                    Circle().fill(Color.primary.opacity(0.10)).frame(width: 30, height: 30)
                    Capsule().fill(Color.primary.opacity(0.08)).frame(width: 34, height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private var stage: some View {
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
        simulation = RotationSimulation(people: people.count)
        shown = simulation.loads
        turn = simulation.cursor
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
            let chosen = simulation.pick(rotation, author: author)
            picked = chosen
            try? await Task.sleep(for: .milliseconds(60))
            landed = true
            try? await Task.sleep(for: .milliseconds(800 + chosen.count * 70))
            faded = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                shown = simulation.loads
                turn = simulation.cursor
                let names = chosen.prefix(2).map(first).joined(separator: ", ") + (chosen.count > 2 ? " +\(chosen.count - 2)" : "")
                caption = rotation.enabled ? "\(rule) → \(names)"
                    : "Off: everyone else is pinged (\(chosen.count) \(chosen.count == 1 ? "person" : "people"))"
            }
            try? await Task.sleep(for: .milliseconds(1900))
            simulation.settle(chosen.count)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { incoming = false; shown = simulation.loads }
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
