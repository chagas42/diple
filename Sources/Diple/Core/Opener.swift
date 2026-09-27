import Foundation
import AppKit

enum Editor: String, CaseIterable, Identifiable, Codable, Sendable {
    case vscode, cursor, zed, jetbrains, xcode, system, web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vscode:    "VS Code"
        case .cursor:    "Cursor"
        case .zed:       "Zed"
        case .jetbrains: "JetBrains (idea://)"
        case .xcode:     "Xcode"
        case .system:    "Default app for the file"
        case .web:       "GitHub, always"
        }
    }

    func url(file: URL, line: Int?) -> URL? {
        var c = URLComponents()
        switch self {
        case .vscode, .cursor:
            c.scheme = self == .vscode ? "vscode" : "cursor"
            c.host = "file"
            c.path = file.path + (line.map { ":\($0):1" } ?? "")
        case .zed:
            c.scheme = "zed"
            c.host = "file"
            c.path = file.path + (line.map { ":\($0)" } ?? "")
        case .jetbrains:
            c.scheme = "idea"
            c.host = "open"
            c.queryItems = [URLQueryItem(name: "file", value: file.path)]
                + (line.map { [URLQueryItem(name: "line", value: String($0))] } ?? [])
        case .xcode, .system, .web:
            return nil
        }
        return c.url
    }
}

@MainActor
enum Opener {
    static func open(_ node: MapNode, in map: PRMap, editor: Editor, roots: [URL], forceWeb: Bool) -> String? {
        guard let path = node.path, !path.isEmpty else { return "nothing to open for \(node.title)" }

        if !forceWeb, editor != .web, !node.isDirectory,
           let file = local(path, roots: roots),
           openLocal(file, line: node.line, editor: editor) {
            return nil
        }

        guard let url = web(path, line: node.line, directory: node.isDirectory, in: map) else {
            return "could not build a GitHub link for \(path)"
        }
        NSWorkspace.shared.open(url)
        return nil
    }

    static func web(_ path: String, line: Int?, directory: Bool, in map: PRMap) -> URL? {
        let ref = map.head.isEmpty ? "HEAD" : map.head
        let encoded = path.split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let anchor = (!directory ? line.map { "#L\($0)" } : nil) ?? ""
        return URL(string: "https://github.com/\(map.repo)/\(directory ? "tree" : "blob")/\(ref)/\(encoded)\(anchor)")
    }

    private static func local(_ path: String, roots: [URL]) -> URL? {
        let fm = FileManager.default
        for root in roots {
            let candidate = root.appendingPathComponent(path)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
                return candidate
            }
        }
        return nil
    }

    private static func openLocal(_ file: URL, line: Int?, editor: Editor) -> Bool {
        let ws = NSWorkspace.shared
        switch editor {
        case .system:
            return ws.open(file)
        case .xcode:
            guard let app = ws.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else { return false }
            ws.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return true
        case .web:
            return false
        case .vscode, .cursor, .zed, .jetbrains:
            guard let url = editor.url(file: file, line: line),
                  ws.urlForApplication(toOpen: url) != nil else { return false }
            return ws.open(url)
        }
    }
}
