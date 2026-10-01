import AppKit

@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    enum State: Equatable {
        case idle
        case checking
        case current
        case available(version: String, page: URL)
        case failed
        case installing(version: String)
        case installFailed(version: String, page: URL)
    }

    @Published private(set) var state = State.idle

    let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    let isDevelopment = (Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "").hasSuffix("(Dev)")
    let viaHomebrew = ["/opt/homebrew/Caskroom/diple", "/usr/local/Caskroom/diple"]
        .contains { FileManager.default.fileExists(atPath: $0) }

    var transport: any Transport = URLSessionTransport()
    private var loop: Task<Void, Never>?

    static let latest = URL(string: "https://api.github.com/repos/chagas42/diple/releases/latest")!
    static let releases = URL(string: "https://github.com/chagas42/diple/releases")!
    static let installer = "https://raw.githubusercontent.com/chagas42/diple/main/install.sh"
    nonisolated static let appPath = "/Applications/Diple.app"

    var summary: String {
        isDevelopment ? "\(installed), development build" : installed
    }

    var releaseNotes: URL {
        switch state {
        case .available(_, let page), .installFailed(_, let page): page
        default: isDevelopment ? Self.releases : Self.releases.appending(path: "tag/v\(installed)")
        }
    }

    var canInstall: Bool {
        guard !isDevelopment, Bundle.main.bundlePath == Self.appPath else { return false }
        return viaHomebrew ? Tools.find("brew") != nil : FileManager.default.isWritableFile(atPath: "/Applications")
    }

    func install() {
        guard canInstall, case .available(let version, let page) = state else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", installCommand]
        p.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                let onDisk = Self.versionOnDisk()
                self.state = Self.afterInstall(status: status, onDisk: onDisk, installed: self.installed,
                                               version: version, page: page)
                if case .installing = self.state { self.relaunch() }
            }
        }
        do {
            try p.run()
            state = .installing(version: version)
        } catch {
            state = .installFailed(version: version, page: page)
        }
    }

    private var installCommand: String {
        if viaHomebrew, let brew = Tools.find("brew") {
            return Self.homebrewCommand(brew: brew, app: Self.appPath)
        }
        return "set -o pipefail; curl -fsSL \(Self.installer) | bash"
    }

    nonisolated static func homebrewCommand(brew: String, app: String) -> String {
        "set -e; '\(brew)' update --quiet; '\(brew)' upgrade --cask diple; open '\(app)'"
    }

    nonisolated static func afterInstall(status: Int32, onDisk: String?, installed: String,
                                         version: String, page: URL) -> State {
        guard status == 0, let onDisk, isNewer(onDisk, than: installed) else {
            return .installFailed(version: version, page: page)
        }
        return .installing(version: version)
    }

    private func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "sleep 1; open '\(Self.appPath)'"]
        try? p.run()
        NSApplication.shared.terminate(nil)
    }

    nonisolated static func versionOnDisk() -> String? {
        let plist = URL(fileURLWithPath: appPath).appending(path: "Contents/Info.plist")
        return (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"]) as? String
    }

    func start() {
        guard loop == nil, !isDevelopment else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    func check() async {
        switch state {
        case .checking, .installing: return
        default: break
        }
        state = .checking
        var request = URLRequest(url: Self.latest)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await transport.send(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { state = .failed; return }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            state = Self.isNewer(version, than: installed)
                ? .available(version: version, page: release.htmlURL)
                : .current
        } catch {
            state = .failed
        }
    }

    nonisolated static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
