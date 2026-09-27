import SwiftUI
import AppKit

struct AIReviewView: View {
    @ObservedObject var model: AppModel
    let pr: PR

    private var findings: [Finding] { model.findings[pr.key] ?? [] }
    private var running: Bool { model.reviewingKey == pr.key }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if running || !model.reviewProgress.isEmpty {
                progress
            }

            if !findings.isEmpty {
                notice
                ForEach(findings) { a in
                    FindingCard(finding: a) { model.discardFinding(pr, a) }
                }
            } else if !running, case .done = model.reviewStep {
                Label("The AI found nothing worth flagging.",
                      systemImage: "checkmark.circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            Text("AI review").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await model.runAIReview(pr) }
            } label: {
                Label(findings.isEmpty ? "Review with AI" : "Review again",
                      systemImage: "play.fill")
            }
            .disabled(model.reviewingKey != nil)
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
                if let i = model.reviewStartedAt {
                    Text(i, style: .timer)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 8)

            ForEach(model.reviewProgress) { line in
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
                Text("Git takes about 3 seconds. The rest is Claude reading the "
                     + "repository — usually 30 s to 2 min.")
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
            Text("Local draft. The session runs without `gh` and without write access — publishing is always you.")
                .font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct FindingCard: View {
    let finding: Finding
    let onDiscard: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                badge(finding.category.label, color: categoryColor)
                badge(finding.verdict.label,
                     color: finding.verdict == .confirmed ? .green : .secondary)
                Spacer()
                Text(finding.location)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(finding.summary)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(finding.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let c = finding.scenario, !c.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("SCENARIO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.purple)
                        .padding(.top, 1)
                    Text(c)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finding.markdown, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy comment",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Spacer()
                Button("Discard", action: onDiscard)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }

    private var categoryColor: Color {
        switch finding.category {
        case .correctness:      .red
        case .simplification: .purple
        case .efficiency:    .blue
        case .test:         .teal
        case .note:         .secondary
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
