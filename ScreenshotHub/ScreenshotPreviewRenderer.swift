import AppKit

nonisolated struct ScreenshotPreviewRequest: Equatable, Sendable {
    var configuration: ScreenshotConfiguration
    var screenshotData: Data?
    var watchScreenshotData: Data?
    var frameImages: DeviceFrameImages?
    var watchFrameImages: DeviceFrameImages?
    var maximumDimension: CGFloat
    var streamsPhone = false
    var streamsWatch = false
    
    var hasLivePreview: Bool { streamsPhone || streamsWatch }
}

nonisolated struct ScreenshotPreview: Sendable {
    var image: CGImage
    var watchOverlay: CGImage?
    var watchScreenMask: CGImage?
    
    var cost: Int {
        [image, watchOverlay, watchScreenMask].compactMap { $0 }
            .reduce(0) { $0 + $1.bytesPerRow * $1.height }
    }
}

actor ScreenshotPreviewRenderer {
    static let shared = ScreenshotPreviewRenderer()
    
    private var entries: [Entry] = []
    private var cost = 0
    
    func render(_ request: ScreenshotPreviewRequest) throws -> ScreenshotPreview {
        try Task.checkCancellation()
        if let index = entries.firstIndex(where: { $0.request == request }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.preview
        }
        let preview = try autoreleasepool {
            let screenshot = request.screenshotData.flatMap(ScreenshotRenderer.image(for:))
            let watchScreenshot = request.watchScreenshotData.flatMap(ScreenshotRenderer.image(for:))
            let bitmap = try ScreenshotRenderer.render(
                configuration: request.configuration,
                screenshot: request.streamsPhone ? nil : screenshot,
                maximumDimension: request.maximumDimension,
                screenIsTransparent: request.streamsPhone,
                frameImages: request.frameImages,
                watchScreenshot: watchScreenshot,
                watchFrameImages: request.watchFrameImages,
                includesWatch: !request.hasLivePreview
            )
            guard let image = bitmap.cgImage else { throw ScreenshotRenderer.RenderError.bitmapCreation }
            var preview = ScreenshotPreview(image: image)
            if request.hasLivePreview, request.configuration.family == .iPhone, request.configuration.watch.isEnabled,
               let graphics = NSGraphicsContext(bitmapImageRep: bitmap) {
                try Task.checkCancellation()
                preview.watchScreenMask = try ScreenshotRenderer.watchScreenMask(
                    configuration: request.configuration,
                    frameImages: request.watchFrameImages,
                    graphics: graphics
                )
                preview.watchOverlay = try ScreenshotRenderer.render(
                    configuration: request.configuration,
                    screenshot: nil,
                    maximumDimension: request.maximumDimension,
                    frameImages: request.frameImages,
                    watchScreenshot: request.streamsWatch ? nil : watchScreenshot,
                    watchFrameImages: request.watchFrameImages,
                    watchScreenIsTransparent: request.streamsWatch,
                    watchOnly: true
                ).cgImage
            }
            return preview
        }
        try Task.checkCancellation()
        let entry = Entry(request: request, preview: preview)
        entries.append(entry)
        cost += entry.cost
        while cost > 96 * 1024 * 1024 || entries.count > 64 {
            cost -= entries.removeFirst().cost
        }
        return preview
    }
    
    private struct Entry {
        var request: ScreenshotPreviewRequest
        var preview: ScreenshotPreview
        
        var cost: Int {
            preview.cost + (request.screenshotData?.count ?? 0) + (request.watchScreenshotData?.count ?? 0)
                + (request.frameImages.map { $0.bezel.count + $0.mask.count } ?? 0)
                + (request.watchFrameImages.map { $0.bezel.count + $0.mask.count } ?? 0)
        }
    }
}
