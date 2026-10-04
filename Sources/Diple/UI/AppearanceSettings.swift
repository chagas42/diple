import SwiftUI

struct AppearanceSettings: View {
    @ObservedObject var model: AppModel

    private static let sample = """
    @@ -24,7 +24,9 @@ export class RefundPolicy {
       async decide(order: Order): Promise<Refund | null> {
    -    if (!order.paidAt) return null
    +    if (!order.paidAt) {
    +      throw new OrderNotPaid(order.id)
    +    }
         return this.build(order, 0.5)
       }
    """

    @State private var accessible = MenuBarItems.allowed

    private var rightIsCrowded: Bool { NotchGeometry.current().wings().crowded }

    var body: some View {
        Form {
            Section {
                Toggle("Show the eye", isOn: $model.settings.showsEye)
                Toggle("Blink", isOn: $model.settings.eyeBlinks)
                    .disabled(!model.settings.showsEye)
                Toggle("Lean toward the pointer", isOn: $model.settings.liquidNotch)
                Picker("Count", selection: $model.settings.countSide) {
                    ForEach(CountSide.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(rightIsCrowded)
            } header: {
                Text("Notch")
            } footer: {
                Text(rightIsCrowded
                     ? "Menu bar icons fill the space right of the notch, so the count and the eye share the left side."
                     : "The little eye follows your pointer from the side opposite the count.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Screen while focused", selection: $model.settings.focusLook) {
                    ForEach(FocusLook.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Focus")
            } footer: {
                Text("While a macOS Focus is on, or after you click the eye in the open notch, opening the "
                     + "notch shows this instead of your queue, with how long you have been focused. "
                     + "Click the eye again to come back.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !NotchGeometry.statusItemsAreWindows {
                Section("Menu bar") {
                    Toggle("Fit the notch to the menu bar", isOn: Binding(
                        get: { model.settings.fitsMenuBar },
                        set: {
                            model.settings.fitsMenuBar = $0
                            if $0, !MenuBarItems.allowed { MenuBarItems.askForAccess() }
                        }
                    ))
                    Text("On this version of macOS, Diple can see where the menu bar icons are only with "
                         + "Accessibility permission, and only on the main display. Without it, the count "
                         + "stays left of the notch so it never covers an icon.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    if model.settings.fitsMenuBar, !accessible {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Waiting for Accessibility permission.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button("Ask Again") { MenuBarItems.askForAccess() }
                                Button("Open Accessibility") { NSWorkspace.shared.open(MenuBarItems.accessibilityPane) }
                            }
                            Text("If Diple is already on in that list, the permission belongs to an earlier copy "
                                 + "of Diple: every update or new build counts as a different app. Select Diple, "
                                 + "remove it with the − button, then click Ask Again.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .task {
                            while !Task.isCancelled, !accessible {
                                try? await Task.sleep(for: .seconds(1))
                                accessible = MenuBarItems.allowed
                            }
                        }
                    }
                }
            }

            Section("Code") {
                Picker("Theme", selection: Binding(
                    get: { model.settings.codeTheme },
                    set: { model.settings.codeTheme = $0 }
                )) {
                    ForEach(CodeTheme.all) { t in
                        Text(t.name).tag(t.id)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    DiffHunkView(hunk: Self.sample, path: "refund-policy.ts")
                        .environment(\.codeTheme, CodeTheme.named(model.settings.codeTheme))
                }
                .padding(.vertical, 4)
            }

            Section("Open files in") {
                Picker("Editor", selection: Binding(
                    get: { model.settings.editor ?? Editors.installed().first?.name ?? "" },
                    set: { model.settings.editor = $0 }
                )) {
                    ForEach(Editors.installed(), id: \.name) { e in
                        Text(e.name).tag(e.name)
                    }
                }
                .pickerStyle(.menu)
                .disabled(Editors.installed().isEmpty)

                Text(Editors.installed().isEmpty
                     ? "No supported editor found. Cursor, VS Code, Zed, Sublime Text and Xcode are recognised."
                     : "Clicking the code icon on a thread opens the file at that line.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { accessible = MenuBarItems.allowed }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessible = MenuBarItems.allowed
        }
    }
}
