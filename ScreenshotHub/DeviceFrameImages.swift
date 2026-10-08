import AppKit

nonisolated struct DeviceFrameImages: Equatable, Sendable {
    var bezel: Data
    var mask: Data
    
    static func load(frameID: String) throws -> Self {
        guard let bezel = NSImage(named: frameID), let mask = NSImage(named: "\(frameID)Mask") else {
            throw ScreenshotRenderer.RenderError.missingFrame
        }
        return try .init(bezel: pngData(for: bezel), mask: pngData(for: mask))
    }
    
    static func pngData(for image: NSImage) throws -> Data {
        let cgImage = try nativeCGImage(for: image)
        guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw ScreenshotRenderer.RenderError.pngEncoding
        }
        return data
    }
    
    static func nativeCGImage(for image: NSImage) throws -> CGImage {
        let representation = image.representations.max {
            Double($0.pixelsWide) * Double($0.pixelsHigh) < Double($1.pixelsWide) * Double($1.pixelsHigh)
        }
        if let bitmap = representation as? NSBitmapImageRep, let cgImage = bitmap.cgImage { return cgImage }
        let size: CGSize
        if let representation, representation.pixelsWide > 0, representation.pixelsHigh > 0 {
            size = .init(width: representation.pixelsWide, height: representation.pixelsHigh)
        } else {
            size = image.size
        }
        var rect = CGRect(origin: .zero, size: size)
        // Use a neutral context so a thumbnail's drawing scale cannot downsample the source representation.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ScreenshotRenderer.RenderError.bitmapCreation
        }
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: context, hints: nil) else {
            throw ScreenshotRenderer.RenderError.bitmapCreation
        }
        return cgImage
    }
}
