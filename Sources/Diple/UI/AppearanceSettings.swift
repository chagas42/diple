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

    var body: some View {
        Form {
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
    }
}
