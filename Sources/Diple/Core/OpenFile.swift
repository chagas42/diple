import AppKit
import Foundation

enum Editors {
    struct Editor: Sendable {
        let name: String
        let bundleId: String
        let scheme: String?
        let cli: String?
    }

    static let known: [Editor] = [
        Editor(name: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92",
               scheme: "cursor", cli: "cursor"),
        Editor(name: "Visual Studio Code", bundleId: "com.microsoft.VSCode",
               scheme: "vscode", cli: "code"),
        Editor(name: "Zed", bundleId: "dev.zed.Zed", scheme: "zed", cli: "zed"),
        Editor(name: "Sublime Text", bundleId: "com.sublimetext.4",
               scheme: "subl", cli: "subl"),
        Editor(name: "Xcode", bundleId: "com.apple.dt.Xcode", scheme: nil, cli: "xed"),
    ]

    static func installed() -> [Editor] {
        known.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil
        }
    }

    static func named(_ name: String?) -> Editor? {
        guard let name else { return installed().first }
        return known.first { $0.name == name } ?? installed().first
    }

    static func open(file: URL, line: Int?, using editor: Editor) {
        if let scheme = editor.scheme {
            var s = "\(scheme)://file\(file.path)"
            if let line { s += ":\(line)" }
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
        if let cli = editor.cli, let bin = Tools.find(cli) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            if editor.cli == "xed", let line {
                p.arguments = ["--line", "\(line)", file.path]
            } else if let line, editor.cli != "xed" {
                p.arguments = ["--goto", "\(file.path):\(line)"]
            } else {
                p.arguments = [file.path]
            }
            try? p.run()
            return
        }
        NSWorkspace.shared.open(file)
    }
}

extension AppModel {
    var localEditor: String? { Editors.named(settings.editor)?.name }

    func openOnGitHub(pr: PR, thread: PR.ReviewThread) {
        var s = "https://github.com/\(pr.repo)/blob/\(pr.headRef)/\(thread.path)"
        if let l = thread.line { s += "#L\(l)" }
        guard let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }

    func openInEditor(pr: PR, thread: PR.ReviewThread) {
        guard let editor = Editors.named(settings.editor) else { return }
        guard let root = Worktree.localPath(pr.repo, configured: settings.repoPaths) else {
            reportOpenFailure("No local checkout for \(pr.repo). Set one in Settings → Claude.")
            return
        }
        let file = root.appendingPathComponent(thread.path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            reportOpenFailure("\(thread.path) is not in the checkout at \(root.path).")
            return
        }
        Editors.open(file: file, line: thread.line, using: editor)
    }
}

extension AppModel {
    func openFinding(_ f: Finding, on pr: PR) {
        var s = "https://github.com/\(pr.repo)/blob/\(pr.headRef)/\(f.path)"
        if let l = f.line { s += "#L\(l)" }
        guard let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }

    func openFindingInEditor(_ f: Finding, on pr: PR) {
        guard let editor = Editors.named(settings.editor) else { return }
        guard let root = Worktree.localPath(pr.repo, configured: settings.repoPaths) else {
            reportOpenFailure("No local checkout for \(pr.repo). Set one in Settings → Claude.")
            return
        }
        let file = root.appendingPathComponent(f.path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            reportOpenFailure("\(f.path) is not in the checkout at \(root.path).")
            return
        }
        Editors.open(file: file, line: f.line, using: editor)
    }
}
