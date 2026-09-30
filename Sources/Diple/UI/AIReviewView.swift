import SwiftUI
import AppKit

struct AIReviewView: View {
    @ObservedObject var model: AppModel
    let pr: PR

    private var result: ReviewResult? { model.aiReview(pr)?.result }
    private var context: ReviewContext? { model.aiReview(pr)?.context }
    private var running: Bool { model.isReviewing(pr.key) }
    private var steps: [ProgressLine] { model.run(pr.key)?.progress ?? [] }

    private func byCategory(_ items: [Finding]) -> [(String, [Finding])] {
        let groups = Dictionary(grouping: sorted(items)) { $0.axis ?? $0.category.label }
        let rank: (String) -> Int = { name in
            groups[name]?.compactMap { $0.severity.map(Self.weight) }.max() ?? 0
        }
        return groups
            .map { ($0.key, $0.value) }
            .sorted { a, b in
                rank(a.0) == rank(b.0) ? a.0 < b.0 : rank(a.0) > rank(b.0)
            }
    }

    private static func weight(_ s: Severity) -> Int {
        switch s {
        case .high:    3
        case .medium:  2
        case .low:     1
        case .request: 0
        }
    }

    var body: some View {
        content.task(id: model.resultIDs(pr)) { await model.holdResults(for: pr) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if running || !steps.isEmpty {
                progress
            }

            if let r = result, !running {
                if !r.findings.isEmpty || !r.threads.isEmpty { notice }
                if !r.summary.isEmpty { SummaryCard(text: r.summary) }

                if r.novel.isEmpty {
                    Label(r.threads.isEmpty ? "The AI found nothing worth flagging."
                                            : "Nothing new to flag beyond what is already on the PR.",
                          systemImage: "checkmark.circle")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                } else {
                    section("NEW FINDINGS", count: r.novel.count)
                    ForEach(byCategory(r.novel), id: \.0) { label, items in
                        CategoryGroup(
                            label: label,
                            items: items,
                            model: model,
                            pr: pr
                        )
                    }
                }

                if !r.threads.isEmpty {
                    section("WHAT IS ALREADY ON THE PR", count: r.threads.count)
                    ForEach(Array(r.threads.enumerated()), id: \.offset) { _, v in
                        ThreadVerdictCard(verdict: v, thread: context?.threads.first { $0.id == v.id })
                    }
                }

                if !r.alreadyRaised.isEmpty {
                    DisclosureGroup("Found too, but someone raised it already (\(r.alreadyRaised.count))") {
                        ForEach(r.alreadyRaised) { a in
                            FindingCard(model: model, pr: pr, finding: a, stacked: true) { model.discardFinding(pr, a) }
                        }
                    }
                    .font(.system(size: 12))
                }

                if !r.clean.isEmpty || !r.dropped.isEmpty {
                    DisclosureGroup("Checked and clean (\(r.clean.count + r.dropped.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(r.clean, id: \.self) { Label($0, systemImage: "checkmark") }
                            ForEach(r.dropped, id: \.self) { Label($0, systemImage: "minus") }
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private func sorted(_ list: [Finding]) -> [Finding] {
        let order = Dictionary(uniqueKeysWithValues: Severity.allCases.enumerated().map { ($1, $0) })
        return list.sorted { (order[$0.severity ?? .low] ?? 9) < (order[$1.severity ?? .low] ?? 9) }
    }

    private func section(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text("\(count)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 6)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            Text("AI review").font(.system(size: 13, weight: .semibold))
            if DeepReview.available {
                Text("DEEP")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.purple)
                    .help("Runs your ~/.claude/skills/diple-review: two review axes, the value pass, "
                          + "and a verdict on every comment already on the PR.")
            }
            Spacer()
            FeedbackButton(model: model, feature: .aiReview)
            Button {
                Task { await model.runAIReview(pr) }
            } label: {
                Label(result == nil ? "Review with AI" : "Review again", systemImage: "play.fill")
            }
            .disabled(running)
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if running {
                    ProgressView().controlSize(.small)
                    Text("Reviewing")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                if let i = model.run(pr.key)?.startedAt {
                    Text(i, style: .timer)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 8)

            ForEach(steps) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: line.done ? "checkmark" : "circle.dotted")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(line.done ? .green : .secondary)
                        .frame(width: 12)
                    Text(line.text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(line.done ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if line.repeats > 1 {
                        Text("×\(line.repeats)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }

            if running {
                Text(DeepReview.available
                     ? "The deep review runs two axes in parallel, then the value pass and a verdict per thread. "
                       + "Usually 3 to 8 minutes, longer on big PRs."
                     : "Git takes about 3 seconds. The rest is Claude reading the repository, usually 30 s to 2 min.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }

    private var notice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 10))
            Text("Local draft. The session runs without `gh` and without write access, so publishing is always you.")
                .font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct CopyButton: View {
    let text: String
    var label = "Copy comment"
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
        } label: {
            Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .font(.system(size: 12))
    }
}

struct SummaryCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REVIEW SUMMARY").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            CopyButton(text: text, label: "Copy summary")
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct FindingCard: View {
    @ObservedObject var model: AppModel
    let pr: PR
    let finding: Finding
    let stacked: Bool
    let onDiscard: () -> Void

    @State private var showWhy = false
    @State private var copied = false

    private var accent: Color {
        guard let s = finding.severity else {
            return finding.verdict == .confirmed ? .orange : .secondary
        }
        return color(s)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(accent).frame(width: 3)

            VStack(alignment: .leading, spacing: 9) {
                header
                Text(finding.summary)
                    .font(.system(size: 13.5, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let c = finding.comment, !c.isEmpty {
                    Text(c)
                        .font(.system(size: 12.5))
                        .textSelection(.enabled)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                        .fixedSize(horizontal: false, vertical: true)

                    DisclosureGroup("Why it holds", isExpanded: $showWhy) {
                        why.padding(.top, 4)
                    }
                    .font(.system(size: 11.5))
                } else {
                    why
                }

                if stacked {
                    if let t = finding.raised {
                        Text("raised in thread \(t)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    actions
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 7) {
            if let s = finding.severity { badge(s.label, color: color(s)) }
            badge(finding.verdict.label, color: finding.verdict == .confirmed ? .green : .secondary)
            if finding.inline == false { badge("PR conversation", color: .teal) }
            Spacer(minLength: 6)
            if let n = finding.pr {
                Text("#\(n)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Button {
                model.openFinding(finding, on: pr)
            } label: {
                Text(finding.location)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .clickable()
            .help("Open this line")
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if model.posted.contains(finding.id) {
                Label("Posted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task { await model.postOnGitHub(finding, on: pr) }
                } label: {
                    if model.posting.contains(finding.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Comment on the PR", systemImage: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.posting.contains(finding.id))
                .help("Posts this as your review comment at \(finding.location)")
            }

            CopyButton(text: finding.markdown, label: "Copy")

            if model.localEditor != nil {
                Button {
                    model.openFindingInEditor(finding, on: pr)
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open at this line in \(model.localEditor ?? "your editor")")
            }

            Spacer()

            Button("Discard", action: onDiscard)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
        }
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(finding.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let c = finding.scenario, !c.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(.purple.opacity(0.65))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("SCENARIO")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.purple)
                        Text(c)
                            .font(.system(size: 12))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }

    private func color(_ s: Severity) -> Color {
        switch s {
        case .high:    .red
        case .medium:  .orange
        case .low:     .secondary
        case .request: .purple
        }
    }

    private func badge(_ t: String, color: Color) -> some View {
        Text(t.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
}

struct ThreadVerdictCard: View {
    let verdict: ThreadVerdict
    let thread: ReviewContext.Thread?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(verdict.kind.label.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(tint)
                if let t = thread {
                    Text(t.comments.first.map { $0.isBot ? "\($0.author) · bot" : $0.author } ?? "")
                        .font(.system(size: 11.5, weight: .medium))
                    if t.isResolved { tag("resolved") }
                    if t.isOutdated { tag("outdated") }
                }
                Spacer()
                if let t = thread {
                    Text(t.location).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    if let u = t.url {
                        Button { NSWorkspace.shared.open(u) } label: { Image(systemName: "arrow.up.forward.square") }
                            .clickable()
                            .buttonStyle(.plain)
                            .help("Open the thread on GitHub")
                    }
                }
            }

            if let first = thread?.comments.first {
                Text(first.body)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text(verdict.reason)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)

            if let reply = verdict.reply, !reply.isEmpty {
                Text(reply)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                    .fixedSize(horizontal: false, vertical: true)
                CopyButton(text: reply, label: "Copy reply")
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35), lineWidth: 1))
    }

    private var tint: Color {
        switch verdict.kind {
        case .holds:       .green
        case .doesNotHold: .red
        case .partly:      .orange
        case .solved:      .blue
        case .outdated:    .secondary
        }
    }

    private func tag(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 9.5))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

struct CategoryGroup: View {
    let label: String
    let items: [Finding]
    @ObservedObject var model: AppModel
    let pr: PR

    @State private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(label.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text("\(items.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if !open {
                        Text(items.compactMap(\.severity).map(\.label).joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 10) {
                    ForEach(items) { a in
                        FindingCard(model: model, pr: pr, finding: a, stacked: false) {
                            model.discardFinding(pr, a)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }
}
