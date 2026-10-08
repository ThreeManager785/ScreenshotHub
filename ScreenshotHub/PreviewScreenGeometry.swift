import Foundation
import CoreGraphics

nonisolated struct PreviewScreenGeometry {
    let bounds: CGRect
    let canvasSize: CGSize
    let screenRect: CGRect
    let sourceSize: CGSize
    
    var scale: CGFloat {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return 0 }
        return min(bounds.width / canvasSize.width, bounds.height / canvasSize.height)
    }
    
    var canvasRect: CGRect {
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        return .init(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    
    var visibleScreenRect: CGRect {
        .init(
            x: canvasRect.minX + screenRect.minX * scale,
            y: canvasRect.minY + screenRect.minY * scale,
            width: screenRect.width * scale,
            height: screenRect.height * scale
        ).intersection(canvasRect)
    }
    
    var imageRect: CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return .zero }
        let fill = max(screenRect.width / sourceSize.width, screenRect.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * fill * scale, height: sourceSize.height * fill * scale)
        return .init(
            x: canvasRect.minX + screenRect.midX * scale - size.width / 2,
            y: canvasRect.minY + screenRect.midY * scale - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
    
    func canvasPoint(for point: CGPoint) -> CGPoint? {
        guard scale > 0, canvasRect.contains(point) else { return nil }
        return .init(x: (point.x - canvasRect.minX) / scale, y: (point.y - canvasRect.minY) / scale)
    }
    
    func normalizedPoint(for point: CGPoint, clamping: Bool = false) -> CGPoint? {
        guard scale > 0, !visibleScreenRect.isEmpty, imageRect.width > 0, imageRect.height > 0,
              point.x.isFinite, point.y.isFinite else { return nil }
        guard clamping || visibleScreenRect.contains(point) else { return nil }
        let x = min(visibleScreenRect.maxX, max(visibleScreenRect.minX, point.x))
        let y = min(visibleScreenRect.maxY, max(visibleScreenRect.minY, point.y))
        return .init(
            x: min(1, max(0, (x - imageRect.minX) / imageRect.width)),
            y: min(1, max(0, (y - imageRect.minY) / imageRect.height))
        )
    }
}
