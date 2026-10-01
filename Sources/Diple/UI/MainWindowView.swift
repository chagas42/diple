import SwiftUI

enum SidebarItem: Hashable {
    case queue(AppModel.Tab)
    case repo(String)
}

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var repoSearch = ""
    @State private var onlyUnreviewed = false

    var body: some View {
        NavigationSplitView {
            barraLateral
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 280)
        } content: {
            list
                .navigationSplitViewColumnWidth(min: 380, ideal: 520, max: 680)
        } detail: {
            if let pr = model.selected {
                DetailView(model: model, pr: pr)
            } else {
                ContentUnavailableView(
                    "Pick a pull request",
                    systemImage: "chevron.right",
                    description: Text("The queue on the left shows what is waiting on you.")
                )
            }
        }
        .navigationTitle("Diple")
        .environment(\.codeTheme, CodeTheme.named(model.settings.codeTheme))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refreshVisible() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.loading)
                .help("Sync now")
            }
        }
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: {
                if let r = model.selectedRepo { return .repo(r) }
                return .queue(model.tab)
            },
            set: { item in
                switch item {
                case .queue(let t):
                    model.selectRepo(nil)
                    model.tab = t
                case .repo(let r):
                    model.selectRepo(r)
                case nil:
                    break
                }
            }
        )
    }

    private var barraLateral: some View {
        List(selection: sidebarSelection) {
            Section("Queue") {
                ForEach(AppModel.Tab.allCases) { tab in
                    HStack {
                        Label(tab.title, systemImage: tab.icon)
                        Spacer()
                        Text("\(model.count(tab))")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarItem.queue(tab))
                }
            }

            if !model.watching.isEmpty {
                Section("Watching") {
                    ForEach(model.watching.sorted(), id: \.self) { full in
                        repoRow(full, starred: true)
                            .tag(SidebarItem.repo(full))
                    }
                }
            }

            ForEach(filteredGroups) { group in
                Section {
                    ForEach(group.items) { repo in
                        repoRow(repo.nameWithOwner, starred: model.watching.contains(repo.nameWithOwner))
                            .tag(SidebarItem.repo(repo.nameWithOwner))
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text("\(group.items.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { UsageNotice(model: model).padding(8) }
        .searchable(text: $repoSearch, placement: .sidebar, prompt: "Find a repository")
        .task { await model.showRepos() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.windowFocused()
        }
    }

    private var filteredGroups: [AppModel.RepoGroup] {
        let q = repoSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.repoGroups }
        return model.repoGroups.compactMap { g in
            let hits = g.items.filter { $0.nameWithOwner.lowercased().contains(q) }
            guard !hits.isEmpty else { return nil }
            switch g {
            case .personal:      return .personal(hits)
            case .org(let o, _): return .org(o, hits)
            }
        }
    }

    private func repoRow(_ full: String, starred: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: starred ? "star.fill" : "book.closed")
                .font(.system(size: 10))
                .foregroundStyle(starred ? .orange : .secondary)
            Text(full.split(separator: "/").last.map(String.init) ?? full)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                model.toggleWatch(full)
            } label: {
                Image(systemName: starred ? "star.slash" : "star")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .clickable()
            .help(starred ? "Stop watching" : "Watch this repository")
        }
    }

    private var list: some View {
        Group {
            if model.selectedRepo != nil { repoList } else { queueList }
        }
    }

    private var repoList: some View {
        List(selection: Binding(
            get: { model.selected?.key },
            set: { key in model.selected = model.repoPRs.first { $0.key == key } }
        )) {
            if model.loadingRepo && model.repoPRs.isEmpty {
                HStack { ProgressView().controlSize(.small); Text("Loading pull requests…") }
                    .foregroundStyle(.secondary)
            } else if model.repoPRsShown.isEmpty {
                Text(model.repoShowsDraft ? "No drafts open." : "No pull requests ready for review.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            } else {
                ForEach(model.repoPRsShown, id: \.key) { pr in
                    PRRow(pr: pr, unread: model.unread.contains(pr.key), required: model.requiredApprovals(for: pr))
                        .tag(pr.key)
                }
            }
        }
        .navigationTitle(model.selectedRepo ?? "")
        .task(id: model.repoPRs.map(\.key)) { model.loadRequirements(for: model.repoPRs) }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("", selection: Binding(
                    get: { model.repoShowsDraft },
                    set: { model.repoShowsDraft = $0 }
                )) {
                    Text("Ready \(model.repoPRs.filter { !$0.draft }.count)").tag(false)
                    Text("Draft \(model.repoPRs.filter(\.draft).count)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }
            .background(.bar)
        }
    }

    @State private var openStacks: Set<String> = []

    private func isOpen(_ stack: PRStack) -> Bool {
        openStacks.contains(stack.id) || stack.prs.contains { $0.key == model.selected?.key }
    }

    private func toggle(_ stack: PRStack) {
        if isOpen(stack) {
            openStacks.remove(stack.id)
            if stack.prs.contains(where: { $0.key == model.selected?.key }) { model.selected = nil }
        } else {
            openStacks.insert(stack.id)
        }
    }

    private var queueShown: [PR] {
        let all = model.prs(model.tab)
        return onlyUnreviewed ? all.filter(\.hasNoReviews) : all
    }

    private var queueList: some View {
        let stacked = Set(queueShown.groupedIntoStacks().filter(\.isStack).flatMap { $0.prs.map(\.key) })
        return List(selection: Binding(
            get: { model.selected.flatMap { stacked.contains($0.key) ? nil : $0.key } },
            set: { key in
                if let key {
                    model.selected = model.prs(model.tab).first { $0.key == key }
                } else if let current = model.selected?.key, !stacked.contains(current) {
                    model.selected = nil
                }
            }
        )) {
            if onlyUnreviewed && queueShown.isEmpty {
                Text("Every pull request here has a review.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            }
            ForEach(queueShown.groupedIntoStacks()) { stack in
                if stack.isStack {
                    StackGroup(
                        stack: stack, model: model, open: isOpen(stack),
                        toggle: { toggle(stack) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
                } else if let pr = stack.prs.first {
                    PRRow(pr: pr, unread: model.unread.contains(pr.key), required: model.requiredApprovals(for: pr),
                          selected: model.selected?.key == pr.key)
                        .opacity(model.dims(pr) ? 0.45 : 1)
                        .tag(pr.key)
                }
            }
        }
        .navigationTitle(model.tab.title)
        .task(id: model.queue.all.map(\.key)) { model.loadRequirements(for: model.queue.all) }
        .onChange(of: model.selected?.key, initial: true) { _, key in
            guard let key, let stack = queueShown.groupedIntoStacks().first(where: { $0.isStack && $0.prs.contains { $0.key == key } }) else { return }
            openStacks.insert(stack.id)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("", selection: $onlyUnreviewed) {
                    Text("All \(model.prs(model.tab).count)").tag(false)
                    Text("No reviews yet \(model.prs(model.tab).filter(\.hasNoReviews).count)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }
            .background(.bar)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let problem = model.syncProblem {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: model.isOnline ? "exclamationmark.triangle.fill" : "wifi.slash")
                        .foregroundStyle(.orange)
                    Text(problem)
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if model.isOnline {
                        Button("Retry") { Task { await model.refresh() } }
                            .buttonStyle(.link)
                            .font(.system(size: 11.5))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.orange.opacity(0.12))
            }
        }
        .overlay {
            if model.prs(model.tab).isEmpty && !model.loading && model.syncProblem == nil {
                ContentUnavailableView("Nothing here", systemImage: "checkmark.circle")
            }
        }
    }
}

struct PRRow: View {
    let pr: PR
    let unread: Bool
    var stack: (index: Int, count: Int)? = nil
    var required: Int? = nil
    var selected = false
    var showsRepo = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let stack { StackRail(index: stack.index, count: stack.count) }
            content.padding(.vertical, 6)
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            PRAvatar(url: pr.authorAvatar, login: pr.author)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if unread {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    }
                    Text(pr.title)
                        .font(.system(size: 13, weight: unread ? .semibold : .regular))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(Self.ago(pr.updatedAt))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .help(pr.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                HStack(spacing: 8) {
                    Text(verbatim: place)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    if pr.draft {
                        Text("Draft")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    if let c = pr.lastComment {
                        Text(verbatim: c.author)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(c.location.map { "\(c.author) at \($0)" } ?? c.author)
                    }
                    Spacer(minLength: 6)
                    ReviewMarks(pr: pr, required: required, selected: selected)
                        .fixedSize()
                        .layoutPriority(1)
                    ChecksDot(state: pr.checks, selected: selected)
                }
            }
        }
    }

    private var place: String {
        let repo = pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo
        return showsRepo ? "\(repo) #\(pr.number)" : "#\(pr.number)"
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86_400: return "\(Int(s / 3600))h"
        case ..<(7 * 86_400): return "\(Int(s / 86_400))d"
        case ..<(30 * 86_400): return "\(Int(s / (7 * 86_400)))w"
        case ..<(365 * 86_400): return "\(Int(s / (30 * 86_400)))mo"
        default: return "\(Int(s / (365 * 86_400)))y"
        }
    }
}

struct StackRail: View {
    let index: Int
    let count: Int

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(index == 1 ? .clear : Color.secondary.opacity(0.35)).frame(width: 1.5, height: 20)
                Rectangle().fill(index == count ? .clear : Color.secondary.opacity(0.35)).frame(width: 1.5)
            }
            Circle()
                .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
                .frame(width: 9, height: 9)
                .padding(.top, 15.5)
        }
        .frame(width: 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .help("\(index) of \(count); the top one merges first")
    }
}

struct ChecksDot: View {
    let state: CheckState
    var selected = false

    var body: some View {
        switch state {
        case .none: EmptyView()
        case .passing: dot(.green, "Checks passing")
        case .failing: dot(.red, "A check failed")
        case .running: dot(.orange, "Checks running")
        }
    }

    private func dot(_ color: Color, _ help: String) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
            .frame(width: 8, height: 8)
            .help(help)
    }
}

struct ReviewMarks: View {
    let pr: PR
    let required: Int?
    var selected = false

    var body: some View {
        HStack(spacing: 8) {
            if let a = ApprovalCount(pr: pr, required: required) {
                mark(a.met ? "checkmark.circle.fill" : "checkmark.circle", a.text, a.met ? .green : .secondary,
                     a.required.map { "\(a.approvals) of the \($0) approvals this branch needs" }
                        ?? "\(a.approvals) approval\(a.approvals == 1 ? "" : "s")")
            }
            if let n = pr.changesRequested, n > 0 {
                mark("arrow.uturn.backward.circle.fill", "\(n)", .red,
                     "\(n) reviewer\(n == 1 ? "" : "s") asked for changes")
            }
            if let n = pr.commentReviews, n > 0 {
                mark("text.bubble", "\(n)", .blue, "\(n) review\(n == 1 ? "" : "s") left comments")
            }
            if !pr.threads.isEmpty {
                mark("bubble.left", "\(pr.threads.count)", .secondary,
                     "\(pr.threads.count) open thread\(pr.threads.count == 1 ? "" : "s")")
            }
        }
    }

    private func mark(_ icon: String, _ text: String, _ color: Color, _ help: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(selected ? Color.white : color)
            .help(help)
    }
}

struct PRAvatar: View {
    let url: URL?
    let login: String
    var side: CGFloat = 24

    var body: some View {
        CachedAvatar(url: url) {
            ZStack {
                Color.secondary.opacity(0.18)
                Text(String(login.prefix(2)).uppercased())
                    .font(.system(size: side * 0.34, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
    }
}

struct ApprovalCount: View {
    let approvals: Int
    let required: Int?

    init?(pr: PR, required: Int?) {
        guard !pr.draft, let approvals = pr.approvals else { return nil }
        let needs = required.flatMap { $0 > 0 ? $0 : nil }
        guard approvals > 0 || needs != nil else { return nil }
        self.approvals = approvals
        self.required = needs
    }

    var met: Bool { required.map { approvals >= $0 } ?? (approvals > 0) }

    var text: String { required.map { "\(approvals)/\($0)" } ?? "\(approvals)" }

    var body: some View {
        Label(text, systemImage: met ? "checkmark.circle.fill" : "checkmark.circle")
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(met ? Color.green : Color.secondary)
            .help(required.map { "\(approvals) of the \($0) approvals this branch needs" }
                  ?? "\(approvals) approval\(approvals == 1 ? "" : "s")")
    }
}

struct StackGroup: View {
    let stack: PRStack
    @ObservedObject var model: AppModel
    let open: Bool
    let toggle: () -> Void

    static let radius: CGFloat = 10
    static let peek: CGFloat = 5
    static let maxPeeks = 3

    private var n: Int { stack.prs.count }

    private var shown: [PR] { open ? stack.prs : Array(stack.prs.prefix(1)) }
    private var peeks: Int { open ? 0 : min(n - 1, Self.maxPeeks) }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach((0..<peeks).reversed(), id: \.self) { k in
                sheet
                    .padding(.horizontal, CGFloat(k + 1) * 8)
                    .offset(y: CGFloat(k + 1) * Self.peek)
                    .opacity(1 - Double(k) * 0.2)
            }
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(shown.enumerated()), id: \.element.key) { i, pr in
                    VStack(spacing: 0) {
                        Divider().opacity(0.6)
                        row(pr, index: open ? i + 1 : nil)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .fill(.background.secondary)
                    .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
            )
            .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        }
        .padding(.bottom, CGFloat(peeks) * Self.peek + 2)
        .padding(.horizontal, 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(open ? 90 : 0))
                .animation(.easeInOut(duration: 0.18), value: open)
            Image(systemName: "square.3.layers.3d.down.right")
                .font(.system(size: 10))
            Text("Stack of \(n)")
                .font(.system(size: 11, weight: .semibold))
            Text(verbatim: stack.base?.repo.split(separator: "/").last.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
            Spacer()
            Text(open ? "merges top first" : "\(n) branches")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .help(open ? "Collapse this stack" : "Show the \(n) pull requests in this stack")
    }

    private func row(_ pr: PR, index: Int?) -> some View {
        let selected = model.selected?.key == pr.key
        return PRRow(
            pr: pr,
            unread: model.unread.contains(pr.key),
            stack: index.map { ($0, n) },
            required: model.requiredApprovals(for: pr),
            showsRepo: false
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Color.accentColor).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selected = pr }
        .opacity(model.dims(pr) ? 0.45 : 1)
    }

    private var sheet: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(.background.secondary)
            .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            .frame(height: 30)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

