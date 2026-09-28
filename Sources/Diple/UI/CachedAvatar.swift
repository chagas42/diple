import AppKit
import SwiftUI

@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    typealias Loader = @Sendable (URL) async -> Data?

    private let images = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
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
        if let running = inFlight[url] { return await running.value }
        loads += 1
        let task = Task { [load] in await load(url).flatMap(NSImage.init(data:)) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { images.setObject(image, forKey: url as NSURL) }
        return image
    }
}

struct CachedAvatar<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? url.flatMap(AvatarCache.shared.cached) {
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
