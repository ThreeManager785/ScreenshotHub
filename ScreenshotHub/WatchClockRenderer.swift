import AppKit
import Vision
import CoreText
    
nonisolated struct WatchClockLayout: Equatable, Sendable {
    var glyphRect: CGRect
    var originalTime: String
    var minuteDigitGap: CGFloat? = nil
    var alignment: Alignment = .trailing
    
    nonisolated static let standard = Self(glyphRect: .init(x: 0.70, y: 0.04, width: 0.23, height: 0.058), originalTime: "9:41")

    nonisolated static func alignment(for rect: CGRect) -> Alignment {
        if abs(rect.midX - 0.5) <= 0.08 { return .center }
        return rect.midX < 0.5 ? .leading : .trailing
    }

    enum Alignment: Equatable, Sendable {
        case leading, center, trailing
    }
}
    
nonisolated struct WatchClockPatch: Sendable {
    var image: CGImage
    var normalizedRect: CGRect
    
    func rect(in screen: CGRect) -> CGRect {
        .init(x: screen.minX + normalizedRect.minX * screen.width,
              y: screen.minY + normalizedRect.minY * screen.height,
              width: normalizedRect.width * screen.width, height: normalizedRect.height * screen.height)
    }
}
    
nonisolated enum WatchClockRenderer {
    private static let compactDescriptor: CTFontDescriptor? = {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/SFCompact.ttf")
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        return descriptors?.first { (CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String) == ".SFCompact-Regular" }
    }()
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static weak var analyzedImage: NSImage?
    nonisolated(unsafe) private static var analyzedLayout: WatchClockLayout?
    nonisolated(unsafe) private static var cachedKey: CacheKey?
    nonisolated(unsafe) private static var cachedPatch: WatchClockPatch?
    
    nonisolated static func analyze(_ source: CGImage) -> WatchClockLayout? {
        let pixelLayout = analyzePixels(source)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.regionOfInterest = .init(x: 0, y: 0.80, width: 1, height: 0.20)
        guard (try? VNImageRequestHandler(cgImage: source).perform([request])) != nil else { return pixelLayout }
        let candidates = (request.results ?? []).compactMap { observation -> (CGRect, String)? in
            guard let text = observation.topCandidates(1).first,
                  let range = text.string.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression),
                  let box = try? text.boundingBox(for: range) else { return nil }
            let rect = box.boundingBox
            return (.init(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height), String(text.string[range]))
        }
        if var layout = pixelLayout {
            if let candidate = candidates.first(where: { $0.0.intersects(layout.glyphRect) }) {
                layout.originalTime = candidate.1
            }
            return layout
        }
        guard let candidate = candidates.min(by: { $0.0.minY < $1.0.minY }) else { return nil }
        return .init(glyphRect: candidate.0, originalTime: candidate.1,
                     alignment: WatchClockLayout.alignment(for: candidate.0))
    }
    
    nonisolated static func track(_ source: CGImage, near layout: WatchClockLayout) -> WatchClockLayout? {
        let size = CGSize(width: source.width, height: source.height)
        let glyph = CGRect(x: layout.glyphRect.minX * size.width, y: layout.glyphRect.minY * size.height,
                           width: layout.glyphRect.width * size.width, height: layout.glyphRect.height * size.height)
        let padding = max(4, glyph.height * 0.5)
        let region = glyph.insetBy(dx: -padding, dy: -padding).integral
            .intersection(.init(origin: .zero, size: size))
        guard var result = analyzePixels(source, in: region) else { return nil }
        let rect = CGRect(x: result.glyphRect.minX * size.width, y: result.glyphRect.minY * size.height,
                          width: result.glyphRect.width * size.width, height: result.glyphRect.height * size.height)
        guard rect.minX > region.minX, rect.maxX < region.maxX,
              rect.minY > region.minY, rect.maxY < region.maxY,
              result.originalTime.count == layout.originalTime.count else { return nil }
        result.originalTime = layout.originalTime
        return result
    }
    
    nonisolated private static func analyzePixels(_ source: CGImage, in requestedRegion: CGRect? = nil) -> WatchClockLayout? {
        let region = requestedRegion
            ?? CGRect(x: 0, y: 0, width: CGFloat(source.width), height: CGFloat(source.height) * 0.20).integral
        guard let crop = source.cropping(to: region) else { return nil }
        let width = crop.width
        let height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(crop, in: .init(x: 0, y: 0, width: width, height: height))
        let samples = Array(stride(from: 0, to: width * height, by: 7))
        let background = (0..<3).map { channel in samples.map { Int(pixels[$0 * 4 + channel]) }.sorted()[samples.count / 2] }
        var marked = [UInt8](repeating: 0, count: width * height)
        for index in marked.indices {
            let difference = (0..<3).reduce(0) { $0 + abs(Int(pixels[index * 4 + $1]) - background[$1]) }
            marked[index] = difference > 240 ? 1 : 0
        }
        var components: [CGRect] = []
        var pending: [Int] = []
        for seed in marked.indices where marked[seed] == 1 {
            marked[seed] = 0
            pending.append(seed)
            var left = width
            var top = height
            var right = 0
            var bottom = 0
            var area = 0
            while let index = pending.popLast() {
                let x = index % width
                let y = index / width
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
                area += 1
                for row in max(0, y - 1)...min(height - 1, y + 1) {
                    for column in max(0, x - 1)...min(width - 1, x + 1) {
                        let neighbor = row * width + column
                        if marked[neighbor] == 1 { marked[neighbor] = 0; pending.append(neighbor) }
                    }
                }
            }
            if area >= 3 { components.append(.init(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) }
        }
        let dots = components.filter { $0.height <= CGFloat(source.height) * 0.025 && $0.width <= CGFloat(source.width) * 0.025 }
        for upper in dots {
            for lower in dots where lower.minY > upper.maxY {
                guard abs(upper.midX - lower.midX) < max(upper.width, lower.width) / 2,
                      lower.minY - upper.maxY < CGFloat(source.height) * 0.035,
                      abs(upper.width - lower.width) <= 2, abs(upper.height - lower.height) <= 2 else { continue }
                let colon = upper.union(lower)
                let digits = components.filter {
                    $0.height >= CGFloat(source.height) * 0.025 && $0.height <= CGFloat(source.height) * 0.10
                        && $0.width >= 2 && $0.width <= $0.height
                        && $0.minY <= colon.minY && $0.maxY >= colon.maxY
                        && abs($0.midX - colon.midX) <= CGFloat(source.width) * 0.25
                }.sorted { $0.minX < $1.minX }
                func adjacentDigits(_ candidates: [CGRect], beforeColon: Bool) -> [CGRect] {
                    var result: [CGRect] = []
                    var edge = beforeColon ? colon.minX : colon.maxX
                    for digit in candidates {
                        let gap = beforeColon ? edge - digit.maxX : digit.minX - edge
                        guard gap <= digit.height * 0.8 else { break }
                        result.append(digit)
                        edge = beforeColon ? digit.minX : digit.maxX
                    }
                    return result.sorted { $0.minX < $1.minX }
                }
                let left = adjacentDigits(Array(digits.filter { $0.maxX < colon.minX }.reversed()), beforeColon: true)
                let right = adjacentDigits(digits.filter { $0.minX > colon.maxX }, beforeColon: false)
                guard (1...2).contains(left.count), right.count == 2 else { continue }
                let clockDigits = left + right
                let glyph = clockDigits.reduce(colon) { $0.union($1) }.offsetBy(dx: region.minX, dy: region.minY)
                let digitHeight = clockDigits.map(\.height).max() ?? 0
                guard colon.height >= digitHeight * 0.35, colon.height <= digitHeight * 0.95,
                      glyph.width < CGFloat(source.width) * 0.40 else { continue }
                let normalized = CGRect(x: glyph.minX / CGFloat(source.width), y: glyph.minY / CGFloat(source.height),
                                        width: glyph.width / CGFloat(source.width), height: glyph.height / CGFloat(source.height))
                return .init(glyphRect: normalized,
                             originalTime: left.count == 2 ? "00:00" : "0:00",
                             minuteDigitGap: (right[1].minX - right[0].minX) / CGFloat(source.width),
                             alignment: WatchClockLayout.alignment(for: normalized))
            }
        }
        return nil
    }
    
    static func layout(for image: NSImage, source: CGImage) -> WatchClockLayout? {
        cacheLock.lock()
        if analyzedImage === image {
            let layout = analyzedLayout
            cacheLock.unlock()
            return layout
        }
        cacheLock.unlock()
        let layout = analyze(source)
        cacheLock.lock()
        analyzedImage = image
        analyzedLayout = layout
        cacheLock.unlock()
        return layout
    }
    
    static func patch(
        configuration: WatchClockConfiguration,
        sourceSize: CGSize,
        source: CGImage? = nil,
        layout: WatchClockLayout = .standard
    ) throws -> WatchClockPatch? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard configuration.isEnabled else { return nil }
        guard configuration.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let colors = source.map { sampleColors($0, layout: layout) } ?? (background: [UInt8](repeating: 0, count: 3), foreground: [UInt8](repeating: 255, count: 3))
        let key = CacheKey(configuration: configuration, size: sourceSize, layout: layout,
                           background: colors.background, foreground: colors.foreground)
        if cachedKey == key { return cachedPatch }
        let glyph = CGRect(x: layout.glyphRect.minX * sourceSize.width, y: layout.glyphRect.minY * sourceSize.height,
                           width: layout.glyphRect.width * sourceSize.width, height: layout.glyphRect.height * sourceSize.height)
        let referenceFont = clockFont(size: 38)
        let referenceLine = line(layout.originalTime, font: referenceFont, color: .white)
        let referenceBounds = CTLineGetBoundsWithOptions(referenceLine, .useGlyphPathBounds)
        let measuredSize = 38 * max(1, glyph.height) / max(1, referenceBounds.height)
        let font = clockFont(size: max(2, measuredSize))
        let minutes = String(layout.originalTime.suffix(2))
        let minuteLine = line(minutes, font: font, color: .white)
        let firstDigit = line(String(minutes.prefix(1)), font: font, color: .white)
        let secondDigit = line(String(minutes.suffix(1)), font: font, color: .white)
        let inkGap = CTLineGetOffsetForStringIndex(minuteLine, 1, nil)
            + CTLineGetBoundsWithOptions(secondDigit, .useGlyphPathBounds).minX
            - CTLineGetBoundsWithOptions(firstDigit, .useGlyphPathBounds).minX
        let digitTracking = layout.minuteDigitGap.map {
            min(CTFontGetSize(font) * 0.1, max(0, $0 * sourceSize.width - inkGap))
        } ?? 0
        let unspacedOriginal = line(layout.originalTime, font: font, color: .white, digitTracking: digitTracking)
        let colonSpacing = layout.minuteDigitGap == nil ? CTFontGetSize(font) * 0.1
            : min(CTFontGetSize(font) * 0.2, max(0, (glyph.width - CTLineGetBoundsWithOptions(unspacedOriginal, .useGlyphPathBounds).width) / 2))
        let originalText = line(layout.originalTime, font: font, color: .white,
                                digitTracking: digitTracking, colonSpacing: colonSpacing)
        let originalInk = CTLineGetBoundsWithOptions(originalText, .useGlyphPathBounds)
        let originalWidth = CGFloat(CTLineGetTypographicBounds(originalText, nil, nil, nil))
        let text = line(configuration.time, font: font, color: color(colors.foreground),
                        digitTracking: digitTracking, colonSpacing: colonSpacing)
        let textWidth = CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil))
        // Align digit cells and the baseline, rather than the varying ink bounds of individual digits.
        let textOrigin: CGFloat
        switch layout.alignment {
        case .leading:
            textOrigin = glyph.minX - originalInk.minX
        case .center:
            textOrigin = glyph.midX - originalInk.midX + (originalWidth - textWidth) / 2
        case .trailing:
            textOrigin = glyph.maxX + originalWidth - originalInk.maxX - textWidth
        }
        let padding: CGFloat = 3
        let left = max(0, min(glyph.minX, textOrigin) - padding)
        let right = max(glyph.maxX, textOrigin + textWidth)
        let rect = CGRect(x: left, y: max(0, glyph.minY - padding),
                          width: max(1, min(sourceSize.width, right + padding) - left),
                          height: glyph.height + padding * 2).integral
        guard let context = CGContext(data: nil, width: max(1, Int(rect.width)), height: max(1, Int(rect.height)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScreenshotRenderer.RenderError.bitmapCreation
        }
        context.setFillColor(color(colors.background).cgColor)
        context.fill(.init(origin: .zero, size: rect.size))
        context.textPosition = .init(x: textOrigin - rect.minX,
                                     y: rect.height - (glyph.minY - rect.minY) - originalInk.maxY)
        CTLineDraw(text, context)
        guard let image = context.makeImage() else { throw ScreenshotRenderer.RenderError.bitmapCreation }
        let patch = WatchClockPatch(image: image, normalizedRect: .init(x: rect.minX / sourceSize.width, y: rect.minY / sourceSize.height,
                                                                      width: rect.width / sourceSize.width, height: rect.height / sourceSize.height))
        cachedKey = key
        cachedPatch = patch
        return patch
    }
    
    static func image(configuration: WatchClockConfiguration, sourceSize: CGSize) throws -> CGImage? {
        try patch(configuration: configuration, sourceSize: sourceSize)?.image
    }
    
    static func rect(configuration: WatchClockConfiguration, in screenRect: CGRect) -> CGRect {
        (try? patch(configuration: configuration, sourceSize: screenRect.size))?.rect(in: screenRect) ?? .zero
    }
    
    static func clockFont(size: CGFloat) -> CTFont {
        let font = compactDescriptor.map { CTFontCreateWithFontDescriptor($0, size, nil) }
            ?? CTFontCreateUIFontForLanguage(.system, size, nil)!
        let attributes: [CFString: Any] = [
            // Keep the watch's text-size outlines when fitting a scaled simulator image.
            kCTFontOpticalSizeAttribute: 19,
            kCTFontVariationAttribute: [2003265652: 425],
            kCTFontFeatureSettingsAttribute: [[kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]]
        ]
        return CTFontCreateCopyWithAttributes(font, size, nil, CTFontDescriptorCreateWithAttributes(attributes as CFDictionary))
    }
    
    private static func line(
        _ text: String,
        font: CTFont,
        color: NSColor,
        digitTracking: CGFloat = 0,
        colonSpacing: CGFloat = 0
    ) -> CTLine {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color.cgColor
        ])
        let characters = Array(text.utf16)
        for (index, character) in characters.enumerated() {
            if (48...57).contains(character) {
                let spacing = digitTracking + (index + 1 < characters.count && characters[index + 1] == 58 ? colonSpacing : 0)
                attributed.addAttribute(.init(kCTKernAttributeName as String), value: spacing,
                                        range: .init(location: index, length: 1))
            } else if character == 58 {
                attributed.addAttribute(.init(kCTKernAttributeName as String), value: colonSpacing,
                                        range: .init(location: index, length: 1))
            }
        }
        return CTLineCreateWithAttributedString(attributed)
    }
    
    private static func color(_ channels: [UInt8]) -> NSColor {
        .init(deviceRed: CGFloat(channels[0]) / 255, green: CGFloat(channels[1]) / 255, blue: CGFloat(channels[2]) / 255, alpha: 1)
    }
    
    private static func sampleColors(_ source: CGImage, layout: WatchClockLayout) -> (background: [UInt8], foreground: [UInt8]) {
        let rect = CGRect(x: layout.glyphRect.minX * CGFloat(source.width), y: layout.glyphRect.minY * CGFloat(source.height),
                          width: layout.glyphRect.width * CGFloat(source.width), height: layout.glyphRect.height * CGFloat(source.height))
            .insetBy(dx: -3, dy: -3).integral
        guard let crop = source.cropping(to: rect) else { return ([0, 0, 0], [255, 255, 255]) }
        let width = min(crop.width, 128)
        let height = min(crop.height, 48)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return ([0, 0, 0], [255, 255, 255])
        }
        context.draw(crop, in: .init(x: 0, y: 0, width: width, height: height))
        let borders = (0..<width).map { $0 * 4 } + (0..<width).map { ((height - 1) * width + $0) * 4 }
        let background = (0..<3).map { channel in borders.map { pixels[$0 + channel] }.sorted()[borders.count / 2] }
        var foreground = background
        var distance = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let difference = (0..<3).reduce(0) { $0 + abs(Int(pixels[offset + $1]) - Int(background[$1])) }
            if difference > distance { distance = difference; foreground = Array(pixels[offset..<offset + 3]) }
        }
        return (background, distance > 90 ? foreground : [255, 255, 255])
    }
    
    private struct CacheKey: Equatable {
        var configuration: WatchClockConfiguration
        var size: CGSize
        var layout: WatchClockLayout
        var background: [UInt8]
        var foreground: [UInt8]
    }
}
