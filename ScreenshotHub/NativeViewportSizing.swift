import SwiftUI

nonisolated enum PreviewRenderSizing {
    static func maximumDimension(
        canvasSize: CGSize,
        viewportSize: CGSize,
        displayScale: CGFloat
    ) -> CGFloat {
        let longestEdge = max(canvasSize.width, canvasSize.height)
        guard canvasSize.width > 0, canvasSize.height > 0,
              viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0,
              displayScale.isFinite, displayScale > 0 else { return min(1100, longestEdge) }
        let fit = min(viewportSize.width / canvasSize.width, viewportSize.height / canvasSize.height)
        let pixels = longestEdge * fit * displayScale
        // Round up in buckets so resizing does not rerender for every point of movement.
        return min(longestEdge, max(128, (pixels / 128).rounded(.up) * 128))
    }
}

extension ProposedViewSize {
    nonisolated func viewportSize(idealSize: CGSize) -> CGSize {
        .init(
            width: width.map { $0.isFinite ? max(0, $0) : idealSize.width } ?? idealSize.width,
            height: height.map { $0.isFinite ? max(0, $0) : idealSize.height } ?? idealSize.height
        )
    }
}
