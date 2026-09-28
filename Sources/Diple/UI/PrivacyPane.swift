import SwiftUI

struct PrivacyPane: View {
    @ObservedObject var model: AppModel

    static let sent = [
        "A random id for this install, which you can reset below",
        "App version, macOS version, whether the screen has a notch",
        "That the app was used today, with the size of your queue as numbers",
        "When an AI review or a map starts and finishes: outcome, finding count, duration range",
        "That you replied, resolved a thread, posted a finding or opened a pull request",
        "Which kind of notification was shown",
        "When something fails: which step, the error's type and numeric code, never its message",
    ]

    static let neverSent = [
        "Your GitHub login, name or e-mail",
        "Repository names, pull request numbers or titles",
        "Code, diffs, comments or file paths",
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Share anonymous usage", isOn: $model.settings.shareUsage)
                Text(model.telemetry.isActive || !model.settings.shareUsage
                     ? "Counts help decide what to build next. Nothing is sent while this is off."
                     : "This build has no analytics key, so nothing is sent either way.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("What is sent") {
                ForEach(Self.sent, id: \.self) { line in
                    Label(line, systemImage: "checkmark").font(.system(size: 11.5))
                }
            }

            Section("What is never sent") {
                ForEach(Self.neverSent, id: \.self) { line in
                    Label(line, systemImage: "xmark").font(.system(size: 11.5))
                }
            }

            Section {
                LabeledContent("Anonymous id") {
                    Text(model.anonymousId.prefix(8) + "…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Reset anonymous id") { model.resetAnonymousId() }
                    Spacer()
                    Link("Privacy in the README", destination: URL(string: "https://github.com/chagas42/diple#privacy")!)
                        .font(.system(size: 11))
                }
                Text("Setting DO_NOT_TRACK=1 in your environment also turns it off.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct UsageNotice: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.usageNoticeVisible {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.secondary)
                Text("Diple sends anonymous usage counts.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Privacy") {
                    model.dismissUsageNotice()
                    Windows.shared.openSettings(model)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                Button("OK") { model.dismissUsageNotice() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.5)))
        }
    }
}
