import SwiftUI

struct DetailView: View {
    @ObservedObject var model: AppModel
    let pr: PR

    enum Section: String, CaseIterable, Identifiable {
        case conversation = "Conversation"
        case map = "Overview"
        case ai = "AI review"
        var id: String { rawValue }
    }
    @State private var section: Section

    init(model: AppModel, pr: PR) {
        self.model = model
        self.pr = pr
        _section = State(initialValue: model.section(for: pr.key))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                estatisticas

                Picker("", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch section {
                case .conversation:
                    if pr.threads.isEmpty {
                        semThreads
                    } else {
                        ForEach(pr.threads) { t in
                            ThreadView(model: model, pr: pr, thread: t)
                        }
                    }
                case .map:
                    MapaView(model: model, pr: pr)
                case .ai:
                    AIReviewView(model: model, pr: pr)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: pr.key) { _, key in section = model.section(for: key) }
        .onChange(of: section) { _, s in model.remember(s, for: pr.key) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                selo
                Text("\(pr.repo) #\(pr.number)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(pr.title)
                .font(.system(size: 20, weight: .semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("opened by \(pr.author) · updated \(pr.updatedAt.formatted(.relative(presentation: .numeric)))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                Button {
                    model.open(pr)
                } label: {
                    HStack(spacing: 4) {
                        Text("Open \(pr.repo.split(separator: "/").last.map(String.init) ?? "")#\(pr.number)")
                            .font(.system(size: 12))
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10.5))
                    }
                }
                .buttonStyle(.link)
                .clickable()
                .help("Open this pull request on GitHub")

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var selo: some View {
        let (text, color): (String, Color) =
            if pr.checks == .failing { ("Check failing", .red) }
            else if pr.approved { ("Approved", .green) }
            else if pr.draft { ("Draft", .secondary) }
            else if !pr.threads.isEmpty { ("Open thread", .orange) }
            else { ("Open", .blue) }
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var estatisticas: some View {
        HStack(spacing: 8) {
            label(pr.checks == .failing ? "checks failing" : pr.checks == .passing ? "checks passing" : "checks running")
            Text("·").foregroundStyle(.tertiary)
            label("\(pr.threads.count) open thread\(pr.threads.count == 1 ? "" : "s")")
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private func label(_ t: String) -> some View { Text(t) }

    private var semThreads: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
            Text("No open human threads on this PR.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
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
                DiffHunkView(hunk: h, path: thread.path)
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
