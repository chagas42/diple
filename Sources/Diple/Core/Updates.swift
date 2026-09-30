import Foundation

@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    enum State: Equatable {
        case idle
        case checking
        case current
        case available(version: String, page: URL)
        case failed
    }

    @Published private(set) var state = State.idle

    let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    let isDevelopment = (Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "").hasSuffix("(Dev)")
    let viaHomebrew = ["/opt/homebrew/Caskroom/diple", "/usr/local/Caskroom/diple"]
        .contains { FileManager.default.fileExists(atPath: $0) }

    var transport: any Transport = URLSessionTransport()
    private var loop: Task<Void, Never>?

    static let latest = URL(string: "https://api.github.com/repos/chagas42/diple/releases/latest")!

    var summary: String {
        isDevelopment ? "\(installed), development build" : installed
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
        guard state != .checking else { return }
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
