import SwiftUI

enum SidebarItem: Hashable {
    case queue(AppModel.Tab)
    case repo(String)
}

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var repoSearch = ""

    var body: some View {
        NavigationSplitView {
            barraLateral
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 280)
        } content: {
            list
                .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 520)
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
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.loading)
                .help("Sincronizar now")
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
        .searchable(text: $repoSearch, placement: .sidebar, prompt: "Find a repository")
        .task { model.loadRepos() }
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
                    PRRow(pr: pr, unread: model.unread.contains(pr.key))
                        .tag(pr.key)
                }
            }
        }
        .navigationTitle(model.selectedRepo ?? "")
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

    private var queueList: some View {
        List(selection: Binding(
            get: { model.selected?.key },
            set: { key in model.selected = model.prs(model.tab).first { $0.key == key } }
        )) {
            ForEach(model.prs(model.tab).groupedIntoStacks()) { stack in
                if stack.isStack {
                    Section {
                        ForEach(Array(stack.prs.enumerated()), id: \.element.key) { i, pr in
                            PRRow(
                                pr: pr,
                                unread: model.unread.contains(pr.key),
                                step: i + 1,
                                steps: stack.prs.count
                            )
                            .tag(pr.key)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.3.layers.3d.down.right")
                                .font(.system(size: 10))
                            Text("PRStack de \(stack.prs.count)")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(stack.base?.repo.split(separator: "/").last.map(String.init) ?? "")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("read bottom to top")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else if let pr = stack.prs.first {
                    PRRow(pr: pr, unread: model.unread.contains(pr.key))
                        .tag(pr.key)
                }
            }
        }
        .navigationTitle(model.tab.title)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let problem = model.errorMessage {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(problem)
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await model.refresh() } }
                        .buttonStyle(.link)
                        .font(.system(size: 11.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.orange.opacity(0.12))
            }
        }
        .overlay {
            if model.prs(model.tab).isEmpty && !model.loading && model.errorMessage == nil {
                ContentUnavailableView("Nothing here", systemImage: "checkmark.circle")
            }
        }
    }
}

struct PRRow: View {
    let pr: PR
    let unread: Bool
    var step: Int? = nil
    var steps: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let d = step, let n = steps {
                Text("\(d)/\(n)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .padding(.top, 3)
            }

            PRAvatar(url: pr.authorAvatar, login: pr.author)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title)
                    .font(.system(size: 13, weight: unread ? .semibold : .regular))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: glyph)
                        .font(.system(size: 10))
                        .foregroundStyle(color)
                    Text("\(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo) #\(pr.number)")
                        .font(.system(size: 11, design: .monospaced))
                    if let c = pr.lastComment {
                        Text("· \(c.author)\(c.location.map { " at \($0)" } ?? "")")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(pr.updatedAt.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if !pr.threads.isEmpty {
                    Label("\(pr.threads.count)", systemImage: "bubble.left")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var glyph: String {
        if pr.checks == .failing { "xmark.circle.fill" }
        else if pr.approved { "checkmark.circle.fill" }
        else if pr.draft { "circle.dashed" }
        else { "arrow.triangle.branch" }
    }

    private var color: Color {
        if pr.checks == .failing { .red }
        else if pr.approved { .green }
        else if unread { .orange }
        else { .secondary }
    }
}

struct PRAvatar: View {
    let url: URL?
    let login: String
    var side: CGFloat = 24

    var body: some View {
        AsyncImage(url: url) { fase in
            switch fase {
            case .success(let img): img.resizable().scaledToFill()
            default:
                ZStack {
                    Color.secondary.opacity(0.18)
                    Text(String(login.prefix(2)).uppercased())
                        .font(.system(size: side * 0.34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
    }
}
