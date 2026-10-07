import SwiftUI

struct DetailView: View {
    @ObservedObject var model: AppModel
    let pr: PR

    enum Section: String, CaseIterable, Identifiable {
        case conversation = "Conversation"
        case map = "Overview"
        case ai = "AI review"
        var id: String { rawValue }

        static func available(for pr: PR) -> [Section] {
            pr.isMine ? allCases : [.conversation, .map]
        }

        static func shown(_ wanted: Section, for pr: PR) -> Section {
            available(for: pr).contains(wanted) ? wanted : .conversation
        }
    }
    @State private var section: Section

    init(model: AppModel, pr: PR) {
        self.model = model
        self.pr = pr
        _section = State(initialValue: Section.shown(model.section(for: pr.key), for: pr))
    }

    static let readable: CGFloat = 780

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                status
                if model.canResolveConflicts(pr) || model.resolveRun(pr.key) != nil {
                    ConflictCard(model: model, pr: pr)
                }

                HStack {
                    Picker("", selection: $section) {
                        ForEach(Section.available(for: pr)) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer(minLength: 0)
                }

                switch section {
                case .conversation:
                    if pr.threads.isEmpty {
                        semThreads
                    } else {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(pr.threads) { t in
                                ThreadView(model: model, pr: pr, thread: t)
                            }
                        }
                    }
                case .map:
                    MapaView(model: model, pr: pr)
                case .ai:
                    AIReviewView(model: model, pr: pr)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: Self.readable, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: pr.key) { _, key in section = Section.shown(model.section(for: key), for: pr) }
        .onChange(of: section) { _, s in model.remember(s, for: pr.key) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(pr.title)
                    .font(.system(size: 21, weight: .semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                TrackButton(model: model, pr: pr)
                FeedbackButton(model: model, feature: .pullRequest)
            }
            HStack(spacing: 8) {
                selo
                Text(verbatim: "\(pr.repo) #\(pr.number)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("·").foregroundStyle(.tertiary)
                PRAvatar(url: pr.authorAvatar, login: pr.author)
                    .scaleEffect(0.7)
                    .frame(width: 18, height: 18)
                Text(verbatim: pr.author)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text(pr.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    model.open(pr)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clickable()
                .help("Open this pull request on GitHub")
            }
        }
    }

    @ViewBuilder private var selo: some View {
        let (text, color): (String, Color) =
            if pr.draft { ("Draft", .secondary) }
            else if pr.approved { ("Approved", .green) }
            else { ("Open", .blue) }
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var status: some View {
        HStack(spacing: 8) {
            switch pr.checks {
            case .passing: pill("checkmark.circle.fill", "Checks passing", .green)
            case .failing: pill("xmark.circle.fill", "A check failed", .red)
            case .running: pill("clock", "Checks running", .orange)
            case .none: EmptyView()
            }
            if let a = ApprovalCount(pr: pr, required: model.requiredApprovals(for: pr)) {
                pill(a.met ? "checkmark.seal.fill" : "checkmark.seal",
                     a.required.map { "\(a.approvals) of \($0) approvals" } ?? "\(a.approvals) approval\(a.approvals == 1 ? "" : "s")",
                     a.met ? .green : .secondary)
            }
            pill(pr.threads.isEmpty ? "bubble.left" : "bubble.left.fill",
                 pr.threads.isEmpty ? "No open threads" : "\(pr.threads.count) open thread\(pr.threads.count == 1 ? "" : "s")",
                 pr.threads.isEmpty ? .secondary : .orange)
        }
    }

    private func pill(_ icon: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
    }

    private var semThreads: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.bubble")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.green)
            Text("Nothing to answer")
                .font(.system(size: 14, weight: .semibold))
            Text("No one left an open thread on this pull request.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ThreadView: View {
    @ObservedObject var model: AppModel
    let pr: PR
    let thread: PR.ReviewThread

    private var manyVoices: Bool {
        Set(thread.comments.filter { !$0.isBot }.map(\.author)).count > 1
    }

    @State private var response = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button {
                    model.openOnGitHub(pr: pr, thread: thread)
                } label: {
                    HStack(spacing: 6) {
                        Text(thread.path)
                            .font(.system(size: 11.5, design: .monospaced))
                        if let l = thread.line {
                            Text("line \(l)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .clickable()
                .help("Open the whole file on GitHub")

                Spacer()

                if model.localEditor != nil {
                    Button {
                        model.openInEditor(pr: pr, thread: thread)
                    } label: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .clickable()
                    .help("Open at this line in \(model.localEditor ?? "your editor")")
                }

                Button("Resolve") {
                    Task { error = await model.resolve(thread: thread.id) }
                }
                .buttonStyle(.link)
                .font(.system(size: 11.5))
                .disabled(model.sending)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.quaternary.opacity(0.4))

            if thread.showsCode, let h = thread.diffHunk {
                DiffHunkView(hunk: h, path: thread.path, line: thread.line, startLine: thread.startLine)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else if thread.outdated {
                Label("The lines this thread points at have changed since it was written, so GitHub no longer sends the code.",
                      systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(Array(thread.comments.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Divider().opacity(0.5) }
                CommentView(comment: c, path: thread.path, alwaysNamed: manyVoices)
            }
            Divider()

            VStack(alignment: .leading, spacing: 7) {
                if let e = error {
                    Label(e, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    TextField("Reply in this thread…", text: $response, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button("Comment") {
                        Task {
                            error = await model.reply(thread: thread.id, text: response)
                            if error == nil { response = "" }
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || model.sending)
                }
            }
            .padding(12)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }
}
