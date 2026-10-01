import SwiftUI

struct FeedbackView: View {
    @ObservedObject var model: AppModel
    let feature: FeedbackFeature
    var onClose: () -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case quick, issue
        var id: String { rawValue }
        var title: String { self == .quick ? "Quick feedback" : "Technical issue" }
    }

    @State private var mode: Mode = .quick
    @State private var text = ""
    @State private var rating: TelemetryEvent.Rating?
    @State private var title = ""
    @State private var diagnostics = true
    @State private var sent = false

    private var remaining: Int { FeedbackText.limit - text.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(feature.title).font(.system(size: 17, weight: .semibold))
            if mode == .quick { quick } else { issue }
        }
        .padding([.horizontal, .bottom], 20)
        .padding(.top, 6)
        .frame(width: 480)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var quick: some View {
        if sent {
            Label("Sent — thank you.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if !model.canSendQuickFeedback {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick feedback travels with anonymous usage, which is off.")
                        .font(.system(size: 13, weight: .medium))
                    Text("You can still open an issue on GitHub, or turn sharing on in Settings → Privacy.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Write a GitHub issue instead") { mode = .issue }
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("How is it?").font(.system(size: 12)).foregroundStyle(.secondary)
                    thumb(.up, "hand.thumbsup")
                    thumb(.down, "hand.thumbsdown")
                }
                editor($text, prompt: "What works, what gets in the way, what is missing…")
                HStack {
                    Text("Sent anonymously. Tokens, e-mails and home paths are removed.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(remaining)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(remaining < 0 ? .red : .secondary)
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                    Button("Send") {
                        model.sendQuickFeedback(feature: feature, rating: rating, text: text)
                        sent = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            onClose()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(FeedbackText.clean(text).isEmpty && rating == nil)
                }
            }
        }
    }

    private var issue: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title, prompt: Text("\(feature.title): what went wrong"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            editor($text, prompt: "Steps, what you expected, what happened instead…")
            Toggle(isOn: $diagnostics) {
                Text("Include app version, macOS and Mac model")
                    .font(.system(size: 11.5))
            }
            Text("Opens a pre-filled issue on GitHub. Review it there, paste or drag screenshots, and submit with your account — nothing is sent from here.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button("Open on GitHub") {
                    model.openIssue(title: title, description: text, feature: feature, diagnostics: diagnostics)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func editor(_ binding: Binding<String>, prompt: String) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: binding)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(6)
            if binding.wrappedValue.isEmpty {
                Text(prompt)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 150)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: binding.wrappedValue) { _, new in
            if new.count > FeedbackText.limit + 200 { binding.wrappedValue = String(new.prefix(FeedbackText.limit + 200)) }
        }
    }

    private func thumb(_ r: TelemetryEvent.Rating, _ icon: String) -> some View {
        Button { rating = rating == r ? nil : r } label: {
            Image(systemName: rating == r ? icon + ".fill" : icon)
                .font(.system(size: 14))
                .foregroundStyle(rating == r ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(r == .up ? "Good" : "Not good")
    }
}

struct FeedbackButton: View {
    @ObservedObject var model: AppModel
    let feature: FeedbackFeature
    var tint: Color = .secondary

    var body: some View {
        Button { Windows.shared.openFeedback(model, feature: feature) } label: {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help("Feedback on \(feature.title)")
    }
}
