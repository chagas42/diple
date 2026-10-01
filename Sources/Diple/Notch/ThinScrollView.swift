import SwiftUI

struct ThinScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 15, *) {
            ThinScroller { content }
        } else {
            ScrollView { content }.scrollIndicators(.visible)
        }
    }
}

@available(macOS 15, *)
private struct ThinScroller<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var metrics = ScrollMetrics()
    @State private var showsThumb = false

    var body: some View {
        ScrollView { content }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: ScrollMetrics.self) { g in
                ScrollMetrics(
                    offset: g.contentOffset.y + g.contentInsets.top,
                    content: g.contentSize.height,
                    viewport: g.containerSize.height
                )
            } action: { old, new in
                if new.offset != old.offset { showsThumb = true }
                metrics = new
            }
            .overlay(alignment: .topTrailing) { thumb }
            .task(id: metrics.offset) {
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.easeOut(duration: 0.3)) { showsThumb = false }
            }
    }

    @ViewBuilder private var thumb: some View {
        if metrics.content > metrics.viewport + 1 {
            let track = metrics.viewport - 6
            let length = max(24, track * metrics.viewport / metrics.content)
            let progress = min(max(metrics.offset / (metrics.content - metrics.viewport), 0), 1)
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 3, height: length)
                .offset(x: -3, y: 3 + progress * (track - length))
                .opacity(showsThumb ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

private struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var viewport: CGFloat = 0
}
