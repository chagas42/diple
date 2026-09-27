import SwiftUI

struct LinhaPR: View {
    let pr: PR
    let naoLido: Bool
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("#\(pr.number)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                        if naoLido {
                            Circle().fill(color).frame(width: 5, height: 5)
                        }
                        Text(pr.updatedAt.formatted(.relative(presentation: .numeric)))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Text(pr.title)
                        .font(.system(size: 12.5, weight: naoLido ? .semibold : .regular))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let c = pr.lastComment {
                        Text("\(c.author)\(c.location.map { " at \($0)" } ?? ""): \(c.excerpt)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        if pr.checks == .failing { .red }
        else if naoLido { .orange }
        else if pr.approved { .green }
        else { .secondary.opacity(0.35) }
    }
}

struct Secao: View {
    let title: String
    let prs: [PR]
    let unread: Set<String>
    let open: (PR) -> Void

    var body: some View {
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                ForEach(prs) { pr in
                    LinhaPR(pr: pr, naoLido: unread.contains(pr.key)) { open(pr) }
                }
            }
        }
    }
}

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Secao(title: "Needs you", prs: model.needsYou,
                          unread: model.unread, open: model.open)
                    Secao(title: "Your PRs", prs: Array(model.rest.prefix(8)),
                          unread: model.unread, open: model.open)

                    if model.queue.all.isEmpty && !model.loading {
                        Text("Nada na queue.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: 420)

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("⟩")
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(model.count > 0 ? .orange : .secondary)
            Text("\(model.count)")
                .font(.system(size: 26, weight: .semibold))
            Text(model.count == 1 ? "waiting on you" : "waiting on you")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if model.loading {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Sincronizar now")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let s = model.lastSync {
                Text("sync \(s.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if !model.hasPermission {
                Text("· no alert permission")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Window") { Windows.compartilhado.openMain(model) }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .keyboardShortcut("0", modifiers: .command)
            Button("Clear") { model.clearAll() }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
    }
}
