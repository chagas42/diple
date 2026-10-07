import SwiftUI

struct TrackButton: View {
    @ObservedObject var model: AppModel
    let pr: PR

    var body: some View {
        let on = model.isTracked(pr)
        Button { model.toggleTrack(pr) } label: {
            Label(on ? "Tracking" : "Track", systemImage: on ? "scope" : "plus.viewfinder")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(on ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(on ? "Stop tracking this PR" : "Get notified on every commit, comment, review and check of this PR until it merges")
    }
}

struct TrackedSection: View {
    @ObservedObject var model: AppModel
    @State private var link = ""
    @State private var problem: String?
    @State private var adding = false

    var body: some View {
        Section {
            HStack {
                TextField("github.com/owner/repo/pull/123", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(adding ? "Adding…" : "Track", action: add)
                    .disabled(link.isEmpty || adding)
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }
            ForEach(model.tracked.values.sorted { $0.since > $1.since }) { t in
                HStack(spacing: 8) {
                    Image(systemName: "scope").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 12.5)).lineLimit(1)
                        Text(verbatim: t.key)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Stop") { model.untrack(t.key) }
                }
            }
        } header: {
            Text("Tracked pull requests")
        } footer: {
            Text("Any PR, yours or not. Every commit, comment, review and check change notifies you, "
                 + "and tracking ends on its own when the PR merges or closes.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private func add() {
        guard !link.isEmpty, !adding else { return }
        adding = true
        Task {
            problem = await model.track(link: link)
            if problem == nil { link = "" }
            adding = false
        }
    }
}
