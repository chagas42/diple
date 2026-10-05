import AppKit
import CryptoKit

@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    enum State: Equatable {
        case idle
        case checking
        case current
        case available(version: String, page: URL)
        case failed
        case downloading(version: String, received: Int64, total: Int64)
        case ready(version: String)
        case installing(version: String)
        case installFailed(version: String, page: URL)
    }

    struct Asset: Equatable, Sendable {
        let zip: URL
        let checksum: URL
        let size: Int64
    }

    typealias Fetch = @Sendable (_ url: URL, _ progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> Data

    @Published private(set) var state = State.idle

    let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    let isDevelopment = (Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "").hasSuffix("(Dev)")
    let viaHomebrew = ["/opt/homebrew/Caskroom/diple", "/usr/local/Caskroom/diple"]
        .contains { FileManager.default.fileExists(atPath: $0) }

    var transport: any Transport = URLSessionTransport()
    var fetch: Fetch = Updates.liveFetch
    private var loop: Task<Void, Never>?
    private(set) var asset: Asset?
    private(set) var staged: URL?

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
        if viaHomebrew {
            upgradeWithHomebrew(version: version, page: page)
        } else {
            Task { await download(version: version, page: page) }
        }
    }

    func download(version: String, page: URL) async {
        guard let asset else { state = .installFailed(version: version, page: page); return }
        state = .downloading(version: version, received: 0, total: asset.size)
        do {
            let data = try await fetch(asset.zip) { [weak self] received, total in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(version: version, received: received, total: total > 0 ? total : asset.size)
                }
            }
            let sum = String(decoding: try await fetch(asset.checksum) { _, _ in }, as: UTF8.self)
            guard Self.checksumMatches(data, sum) else { state = .installFailed(version: version, page: page); return }
            staged = try await Self.unpack(data)
            state = .ready(version: version)
        } catch {
            state = .installFailed(version: version, page: page)
        }
    }

    private func upgradeWithHomebrew(version: String, page: URL) {
        guard let brew = Tools.find("brew") else { state = .installFailed(version: version, page: page); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", Self.homebrewCommand(brew: brew)]
        p.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.staged = nil
                self.state = Self.afterInstall(status: status, onDisk: Self.versionOnDisk(), installed: self.installed,
                                               version: version, page: page)
            }
        }
        do {
            try p.run()
            state = .installing(version: version)
        } catch {
            state = .installFailed(version: version, page: page)
        }
    }

    nonisolated static func homebrewCommand(brew: String, app: String = appPath) -> String {
        "set -e; '\(brew)' update --quiet; '\(brew)' upgrade --cask diple; open '\(app)'"
    }

    nonisolated static func afterInstall(status: Int32, onDisk: String?, installed: String,
                                         version: String, page: URL) -> State {
        guard status == 0, let onDisk, isNewer(onDisk, than: installed) else {
            return .installFailed(version: version, page: page)
        }
        return .ready(version: version)
    }

    nonisolated static func checksumMatches(_ data: Data, _ file: String) -> Bool {
        guard let expected = file.split(whereSeparator: \.isWhitespace).first?.lowercased() else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expected
    }

    nonisolated static func unpack(_ zip: Data) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diple-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Diple.zip")
        try zip.write(to: file)
        let unpacked = dir.appendingPathComponent("unpacked")
        let result = await Shell.live.run("ditto", ["-x", "-k", file.path, unpacked.path], dir, 120)
        let app = unpacked.appendingPathComponent("Diple.app")
        guard result.ok, FileManager.default.fileExists(atPath: app.path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return app
    }

    nonisolated static func liveFetch(_ url: URL, _ progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> Data {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let total = response.expectedContentLength
        var data = Data()
        if total > 0 { data.reserveCapacity(Int(total)) }
        var chunk: [UInt8] = []
        chunk.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count == 64 * 1024 {
                data.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                progress(Int64(data.count), total)
            }
        }
        data.append(contentsOf: chunk)
        progress(Int64(data.count), total)
        return data
    }

    nonisolated static func swapScript(opener: String = "open") -> String {
        """
        pid="$1"; staged="$2"; dest="$3"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        if [ -n "$staged" ]; then
          rm -rf "$dest" && ditto "$staged" "$dest" || exit 1
          xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
          /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dest" 2>/dev/null || true
        fi
        \(opener) "$dest"
        """
    }

    func rehearse(version: String = "1.43.0", holdingAt fraction: Double? = nil) async {
        let total: Int64 = 4_225_651
        for step in 0...20 {
            let received = total * Int64(step) / 20
            if let fraction, Double(received) / Double(total) >= fraction {
                state = .downloading(version: version, received: received, total: total)
                return
            }
            state = .downloading(version: version, received: received, total: total)
            try? await Task.sleep(for: .milliseconds(120))
        }
        state = .ready(version: version)
    }

    func restartAndInstall() {
        guard case .ready = state else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", Self.swapScript(), "diple-update",
                       "\(ProcessInfo.processInfo.processIdentifier)", staged?.path ?? "", Self.appPath]
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
        case .checking, .installing, .downloading, .ready: return
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
            asset = release.asset
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

    struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        var assets: [File]? = nil

        struct File: Decodable {
            let name: String
            let size: Int64
            let url: URL

            enum CodingKeys: String, CodingKey {
                case name, size
                case url = "browser_download_url"
            }
        }

        var asset: Asset? {
            guard let files = assets,
                  let zip = files.first(where: { $0.name.hasSuffix(".zip") }),
                  let sum = files.first(where: { $0.name == zip.name + ".sha256" }) else { return nil }
            return Asset(zip: zip.url, checksum: sum.url, size: zip.size)
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }
}
