import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel

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

    private var barraLateral: some View {
        List(selection: Binding(get: { model.tab }, set: { model.tab = $0 ?? .esperando })) {
            Section("Queue") {
                ForEach(AppModel.Tab.allCases) { tab in
                    HStack {
                        Label(tab.title, systemImage: tab.icon)
                        Spacer()
                        Text("\(model.count(tab))")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(tab)
                }
            }
            Section("Repositories") {
                ForEach(repos, id: \.0) { name, quantos in
                    HStack {
                        Text(name)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Text("\(quantos)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var repos: [(String, Int)] {
        Dictionary(grouping: model.queue.all, by: \.repo)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0 }
    }

    private var list: some View {
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
                                naoLido: model.unread.contains(pr.key),
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
                    PRRow(pr: pr, naoLido: model.unread.contains(pr.key))
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
    let naoLido: Bool
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
                    .font(.system(size: 13, weight: naoLido ? .semibold : .regular))
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
        else if naoLido { .orange }
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
