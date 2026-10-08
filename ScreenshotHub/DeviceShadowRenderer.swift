import AppKit
import Accelerate

nonisolated enum DeviceShadowRenderer {
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var shadows: [String: Shadow] = [:]
    
    static func draw(
        frame: DeviceFrame,
        bezel: NSImage,
        screenMask: CGImage,
        in deviceRect: CGRect,
        graphics: NSGraphicsContext,
        cacheKey: String? = nil
    ) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let shadow: Shadow
        let key = cacheKey ?? frame.id
        if let cached = shadows[key] {
            shadow = cached
        } else {
            guard let bezelImage = try? DeviceFrameImages.nativeCGImage(for: bezel) else {
                throw ScreenshotRenderer.RenderError.missingFrame
            }
            shadow = try makeShadow(frame: frame, bezel: bezelImage, screenMask: screenMask)
            if shadows.count >= 12 { shadows.removeAll(keepingCapacity: true) }
            shadows[key] = shadow
        }
        let scale = deviceRect.width / shadow.deviceSize.width
        let rect = CGRect(
            x: deviceRect.minX - shadow.padding * scale,
            y: deviceRect.minY - shadow.padding * scale,
            width: CGFloat(shadow.image.width) * scale,
            height: CGFloat(shadow.image.height) * scale
        )
        let context = graphics.cgContext
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(shadow.image, in: .init(origin: .zero, size: rect.size))
        context.restoreGState()
    }
    
    private static func makeShadow(frame: DeviceFrame, bezel: CGImage, screenMask: CGImage) throws -> Shadow {
        let scale = min(1, 1024 / max(frame.width, frame.height))
        let deviceWidth = Int(ceil(frame.width * scale))
        let deviceHeight = Int(ceil(frame.height * scale))
        let shortSide = CGFloat(min(deviceWidth, deviceHeight))
        let blur = shortSide * 0.012
        let padding = Int(ceil(blur * 5))
        let length = Int(ceil(shortSide * 0.6))
        let width = deviceWidth + length + padding * 2
        let height = deviceHeight + length + padding * 2
        var silhouette = [UInt8](repeating: 0, count: deviceWidth * deviceHeight * 4)
        try silhouette.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: deviceWidth,
                height: deviceHeight,
                bitsPerComponent: 8,
                bytesPerRow: deviceWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw ScreenshotRenderer.RenderError.shadowCreation }
            let rect = CGRect(x: 0, y: 0, width: deviceWidth, height: deviceHeight)
            context.interpolationQuality = .high
            context.draw(bezel, in: rect)
            context.draw(screenMask, in: rect)
        }
        
        // The reference PNG's alpha falls exponentially with distance along a down-right cast.
        let decay = Float(exp(-1 / (shortSide * 0.105)))
        var diagonal = [Float](repeating: 0, count: width)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let sourceX = x - padding
                let sourceY = y - padding
                let source: Float
                if sourceX >= 0, sourceX < deviceWidth, sourceY >= 0, sourceY < deviceHeight {
                    source = Float(silhouette[(sourceY * deviceWidth + sourceX) * 4 + 3])
                } else {
                    source = 0
                }
                let previous = x > 0 ? diagonal[x - 1] : 0
                diagonal[x] = source * (1 - decay) + previous * decay
                alpha[y * width + x] = UInt8((diagonal[x] * 0.35).rounded())
            }
        }
        alpha = try soften(alpha, width: width, height: height, kernel: max(3, Int((blur * 2).rounded()) | 1))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in alpha.indices { pixels[index * 4 + 3] = alpha[index] }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { throw ScreenshotRenderer.RenderError.shadowCreation }
        return .init(
            image: image,
            padding: CGFloat(padding),
            deviceSize: .init(width: deviceWidth, height: deviceHeight)
        )
    }
    
    private static func soften(_ alpha: [UInt8], width: Int, height: Int, kernel: Int) throws -> [UInt8] {
        var source = alpha
        var destination = [UInt8](repeating: 0, count: alpha.count)
        try source.withUnsafeMutableBytes { sourceBytes in
            try destination.withUnsafeMutableBytes { destinationBytes in
                var input = vImage_Buffer(
                    data: sourceBytes.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width
                )
                var output = vImage_Buffer(
                    data: destinationBytes.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width
                )
                for _ in 0..<3 {
                    let error = vImageBoxConvolve_Planar8(
                        &input, &output, nil, 0, 0,
                        UInt32(kernel), UInt32(kernel), 0,
                        vImage_Flags(kvImageEdgeExtend)
                    )
                    guard error == kvImageNoError else { throw ScreenshotRenderer.RenderError.shadowCreation }
                    swap(&input, &output)
                }
            }
        }
        return destination
    }
    
    private struct Shadow {
        let image: CGImage
        let padding: CGFloat
        let deviceSize: CGSize
    }
}
