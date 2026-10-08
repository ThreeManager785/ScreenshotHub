import AppKit

@MainActor
struct PreviewScreenMask {
    private let bitmap: NSBitmapImageRep
    
    init(image: CGImage) {
        bitmap = .init(cgImage: image)
    }
    
    func contains(_ point: CGPoint, canvasSize: CGSize) -> Bool {
        opacity(at: point, canvasSize: canvasSize) < 0.5
    }
    
    func opacity(at point: CGPoint, canvasSize: CGSize) -> CGFloat {
        guard canvasSize.width > 0, canvasSize.height > 0,
              point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0, point.x < canvasSize.width, point.y < canvasSize.height else { return 1 }
        let x = min(bitmap.pixelsWide - 1, Int(point.x / canvasSize.width * CGFloat(bitmap.pixelsWide)))
        let y = min(bitmap.pixelsHigh - 1, Int(point.y / canvasSize.height * CGFloat(bitmap.pixelsHigh)))
        return bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1
    }
}
