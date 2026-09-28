import AppKit
import SwiftUI

@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    typealias Loader = @Sendable (URL) async -> Data?

    private let images = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private let load: Loader
    private(set) var loads = 0

    init(load: @escaping Loader = { try? await URLSession.shared.data(from: $0).0 }) {
        self.load = load
        images.countLimit = 300
    }

    func cached(_ url: URL) -> NSImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let hit = cached(url) { return hit }
        let task: Task<Data?, Never>
        if let running = inFlight[url] {
            task = running
        } else {
            loads += 1
            task = Task { [load] in await load(url) }
            inFlight[url] = task
        }
        let data = await task.value
        inFlight[url] = nil
        if let hit = cached(url) { return hit }
        guard let data, let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct CachedAvatar<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? url.flatMap({ AvatarCache.shared.cached($0) }) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await AvatarCache.shared.image(for: url)
        }
    }
}
