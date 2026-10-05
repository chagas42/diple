import SwiftUI
import AppKit

struct ConflictCard: View {
    @ObservedObject var model: AppModel
    let pr: PR

    private var run: ResolveRun? { model.resolveRun(pr.key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint).font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                actions
            }
            if let run, !run.steps.isEmpty { steps(run) }
            if let run, let outcome = run.outcome { result(outcome, folder: run.folder) }
        }
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.25)))
    }

    private var tint: Color {
        switch run?.outcome {
        case .pushed?: .green
        case .failed?: .red
        default: .orange
        }
    }

    private var icon: String {
        switch run?.outcome {
        case .pushed?: "checkmark.circle.fill"
        case .committed?: "arrow.up.circle"
        case .failed?: "exclamationmark.triangle.fill"
        case nil: run == nil ? "arrow.triangle.merge" : "sparkles"
        }
    }

    private var title: String {
        switch run?.outcome {
        case .pushed?: "Conflicts resolved and pushed"
        case .committed?: "Resolved locally, ready to push"
        case .failed(let step, _)?: "Could not resolve (\(step))"
        case nil: run == nil ? "Conflicts with \(pr.baseRef)" : "Claude is resolving the conflicts"
        }
    }

    private var subtitle: String {
        if run == nil {
            return "Claude merges \(pr.baseRef) in a worktree on this Mac, resolves the conflicts, runs the project's tests and pushes."
        }
        return run?.running == true ? "This runs on this Mac and can take a few minutes." : "Merged \(pr.baseRef) into \(pr.headRef)."
    }

    @ViewBuilder private var actions: some View {
        if run == nil, model.canResolveConflicts(pr) {
            Button { Task { await model.resolveConflicts(pr) } } label: {
                Label("Resolve with Claude", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        } else if run?.running == true {
            ProgressView().controlSize(.small)
        } else if case .committed? = run?.outcome {
            Button("Push") { Task { await model.pushResolved(pr) } }
                .buttonStyle(.borderedProminent).controlSize(.small)
        } else if run?.outcome != nil {
            Button("Dismiss") { model.dismissResolve(pr) }.controlSize(.small)
        }
    }

    private func steps(_ run: ResolveRun) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(run.steps.enumerated()), id: \.offset) { i, step in
                let current = run.running && i == run.steps.count - 1
                Label(step, systemImage: current ? "circle.dotted" : "checkmark")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(current ? .primary : .secondary)
            }
        }
    }

    @ViewBuilder private func result(_ outcome: ConflictResolver.Outcome, folder: URL?) -> some View {
        switch outcome {
        case .pushed(let commit, let report), .committed(let commit, let report):
            VStack(alignment: .leading, spacing: 6) {
                if !report.files.isEmpty {
                    Text("Resolved: " + report.files.joined(separator: ", ")).font(.system(size: 11.5))
                }
                Text("Checks: " + report.checks).font(.system(size: 11.5)).foregroundStyle(.secondary)
                if !report.summary.isEmpty {
                    Text(report.summary).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                Text("Commit \(commit.prefix(7))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        case .failed(_, let reason):
            VStack(alignment: .leading, spacing: 6) {
                Text(reason).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let folder {
                    Button("Show the worktree in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        .buttonStyle(.link).font(.system(size: 11.5))
                }
            }
        }
    }
}
