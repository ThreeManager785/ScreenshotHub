import AppKit
import SwiftUI
import CoreText
import QuartzCore
    
nonisolated private final class TestScrollEvent: NSEvent {
    private let location: CGPoint
    private let delta: CGFloat
    private let precise: Bool
    private let momentum: NSEvent.Phase
    
    init(location: CGPoint, delta: CGFloat, precise: Bool, momentum: NSEvent.Phase) {
        self.location = location
        self.delta = delta
        self.precise = precise
        self.momentum = momentum
        super.init()
    }
    
    required init?(coder: NSCoder) { return nil }
    
    override var type: NSEvent.EventType { .scrollWheel }
    override var locationInWindow: NSPoint { location }
    override var scrollingDeltaY: CGFloat { delta }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var momentumPhase: NSEvent.Phase { momentum }
}

@main
struct ValidateWatch {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let catalog = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for frame in DeviceFrame.all {
            for suffix in ["", "Mask"] {
                let name = frame.id + suffix
                let image = NSImage(contentsOf: catalog.appendingPathComponent("\(name).imageset/image.png"))!
                precondition(image.setName(.init(name)))
            }
        }
        let phone = source(width: 400, height: 850, isWatch: false)
        let watch = source(width: 416, height: 496, isWatch: true)
        try DeviceFrameImages.pngData(for: watch).write(to: output.appendingPathComponent("Watch-source.png"))
        var configuration = ScreenshotConfiguration()
        configuration.usesSourceScreenCutouts = true
        configuration.watch.isEnabled = true
        configuration.watch.clock.isEnabled = true
        let frames = DeviceFrame.all.filter { $0.family == .appleWatch }
        precondition(frames.count == 24)
        for frame in frames {
            configuration.watch.frameID = frame.id
            let overlay = try ScreenshotRenderer.render(configuration: configuration, screenshot: nil,
                                                        maximumDimension: 650, watchScreenIsTransparent: true, watchOnly: true)
            let screen = ScreenshotRenderer.watchScreenRect(configuration: configuration)
            let mask = PreviewScreenMask(image: overlay.cgImage!)
            precondition(mask.contains(.init(x: screen.midX, y: screen.midY), canvasSize: configuration.resolution.size))
            precondition(mask.opacity(at: .zero, canvasSize: configuration.resolution.size) == 0)
            let screenMask = try ScreenshotRenderer.watchScreenMask(configuration: configuration,
                                                                    graphics: NSGraphicsContext(bitmapImageRep: overlay)!)
            precondition(screenMask.width == Int(frame.screenWidth + 4) && screenMask.height == Int(frame.screenHeight + 4))
            let image = try ScreenshotRenderer.render(configuration: configuration, screenshot: phone,
                                                      maximumDimension: 650, watchScreenshot: watch)
            precondition(!image.hasAlpha)
        }
        for position in [0.0, 0.25, 0.5, 0.75, 1.0] {
            for scale in [0.30, 0.36, 0.5, 0.65] {
                configuration.watch.horizontalPosition = position
                configuration.watch.scale = scale
                let frame = configuration.frame!
                let screen = ScreenshotRenderer.screenRect(configuration: configuration)
                let ratio = screen.width / frame.screenWidth
                let phoneRect = CGRect(x: screen.minX - frame.screenX * ratio, y: screen.minY - frame.screenY * ratio,
                                       width: frame.width * ratio, height: frame.height * ratio)
                let watchRect = ScreenshotRenderer.watchDeviceRect(configuration: configuration)
                precondition(abs(watchRect.maxY - phoneRect.maxY) < 0.001)
                precondition(abs(watchRect.minX - (phoneRect.midX + phoneRect.width * position / 2)) < 0.001)
                let phoneArea = phoneRect.width * phoneRect.height
                let watchArea = watchRect.width * watchRect.height
                let visualCenter = (phoneRect.midX * phoneArea + watchRect.midX * watchArea) / (phoneArea + watchArea)
                precondition(abs(visualCenter - configuration.resolution.size.width / 2) < 0.001)
                let expectedPhoneCenter = configuration.resolution.size.height * (0.175 + 0.79 / 2 + configuration.deviceOffset)
                precondition(abs(phoneRect.midY - expectedPhoneCenter) < 0.001,
                             "Visual centering must only affect horizontal placement.")
                precondition(phoneRect.union(watchRect).minX >= configuration.resolution.size.width * 0.04 - 0.001)
                precondition(phoneRect.union(watchRect).maxX <= configuration.resolution.size.width * 0.96 + 0.001)
            }
        }
        configuration.watch = .init(isEnabled: true)
        configuration.watch.clock.isEnabled = true
        for resolution in DeviceFamily.iPhone.resolutions {
            configuration.resolution = resolution
            let png = try ScreenshotRenderer.pngData(configuration: configuration, screenshot: phone, watchScreenshot: watch)
            let bitmap = NSBitmapImageRep(data: png)!
            precondition(bitmap.pixelsWide == resolution.width && bitmap.pixelsHigh == resolution.height && !bitmap.hasAlpha)
            try png.write(to: output.appendingPathComponent("Phone-and-Watch-\(resolution.id).png"))
        }
        configuration.watch.clock.time = "10:08"
        let replaced = try ScreenshotRenderer.pngData(configuration: configuration, screenshot: phone, watchScreenshot: watch)
        try replaced.write(to: output.appendingPathComponent("Clock-replaced.png"))
        configuration.watch.clock.time = "9:41"
        configuration.resolution = DeviceFamily.iPhone.resolutions[0]
        let nominalFrame = configuration.watch.frame!
        let nominalSize = CGSize(width: nominalFrame.screenWidth, height: nominalFrame.screenHeight)
        let clock = try WatchClockRenderer.image(configuration: configuration.watch.clock, sourceSize: nominalSize)!
        let cacheStart = ContinuousClock.now
        for _ in 0..<10_000 {
            let cached = try WatchClockRenderer.image(configuration: configuration.watch.clock, sourceSize: nominalSize)
            precondition(cached === clock, "Unchanged time must reuse its raster rather than render per frame.")
        }
        let cacheDuration = cacheStart.duration(to: .now)
        var changedClock = configuration.watch.clock
        changedClock.time = "10:08"
        let changed = try WatchClockRenderer.image(configuration: changedClock, sourceSize: nominalSize)
        precondition(changed !== clock)
        _ = try WatchClockRenderer.image(configuration: configuration.watch.clock, sourceSize: nominalSize)
        let base = try ScreenshotRenderer.render(configuration: configuration, screenshot: nil, maximumDimension: 1100,
                                                  screenIsTransparent: true, includesWatch: false)
        let watchOverlay = try ScreenshotRenderer.render(configuration: configuration, screenshot: nil, maximumDimension: 1100,
                                                          watchScreenIsTransparent: true, watchOnly: true)
        let view = LiveCanvasView(frame: .init(x: 0, y: 0, width: base.pixelsWide, height: base.pixelsHigh))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = view
        let phoneID = UUID()
        let watchID = UUID()
        var phoneEvents: [SimulatorTouchEvent] = []
        var watchEvents: [SimulatorTouchEvent] = []
        var crownEvents: [Bool] = []
        var crownRotations: [Double] = []
        let phoneCG = phone.cgImage(forProposedRect: nil, context: NSGraphicsContext(bitmapImageRep: base), hints: nil)!
        let watchCG = watch.cgImage(forProposedRect: nil, context: NSGraphicsContext(bitmapImageRep: base), hints: nil)!
        let watchScreenMask = try ScreenshotRenderer.watchScreenMask(configuration: configuration,
                                                                     graphics: NSGraphicsContext(bitmapImageRep: base)!)
        let baseImage = base.cgImage!
        let watchOverlayImage = watchOverlay.cgImage!
        let alternateWatch = source(width: 416, height: 496, isWatch: false)
            .cgImage(forProposedRect: nil, context: NSGraphicsContext(bitmapImageRep: base), hints: nil)!
        let watchScreen = ScreenshotRenderer.watchScreenRect(configuration: configuration)
        let detectedLayout = WatchClockRenderer.analyze(watchCG)!
        precondition(["9:41", "0:00"].contains(detectedLayout.originalTime),
                     "Clock detection must retain the recognized time or the pixel-only fallback when Vision is unavailable.")
        let detectedRect = detectedLayout.glyphRect
        precondition(abs(detectedRect.maxX * 416 - 378) < 3 && abs(detectedRect.minY * 496 - 40) < 3,
                     "Clock detection must preserve the original glyph position.")
        try validateClockAlignments(output: output)
        try validateLiveClockAlignments()
        let clockFontName = CTFontCopyPostScriptName(WatchClockRenderer.clockFont(size: 38)) as String
        precondition(clockFontName.hasPrefix(".SFCompact") && !clockFontName.contains("Rounded"))
        for size: CGFloat in [16, 19, 38, 44] {
            let font = WatchClockRenderer.clockFont(size: size)
            func advance(_ text: String) -> Double {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                    .init(kCTFontAttributeName as String): font
                ]))
                return CTLineGetTypographicBounds(line, nil, nil, nil)
            }
            let digitWidth = advance("0")
            for digit in "123456789" {
                precondition(abs(advance(String(digit)) - digitWidth) < 1e-6,
                             "Every clock digit must occupy the same cell width.")
            }
            precondition(advance(":") < digitWidth && advance("i") < advance("W"),
                         "Tabular digits must retain proportional punctuation and the SF Compact font design.")
            precondition(abs(advance("11:11") - advance("88:88")) < 1e-6)
        }
        for size: CGSize in [.init(width: 416, height: 496), .init(width: 368, height: 448), .init(width: 208, height: 248)] {
            for times in [["1:11", "8:88", "0:00"], ["11:11", "88:88", "00:00"]] {
                var originalRect: CGRect?
                for time in times {
                    var clockConfiguration = configuration.watch.clock
                    clockConfiguration.time = time
                    let patch = try WatchClockRenderer.patch(configuration: clockConfiguration, sourceSize: size)!
                    if let originalRect {
                        precondition(patch.normalizedRect == originalRect,
                                     "Equal-length times must keep a fixed tabular layout regardless of digit ink widths.")
                    } else { originalRect = patch.normalizedRect }
                    if size.width == 416 {
                        try DeviceFrameImages.pngData(for: NSImage(cgImage: patch.image, size: .zero))
                            .write(to: output.appendingPathComponent("Tabular-clock-\(time.replacingOccurrences(of: ":", with: "-")).png"))
                    }
                }
            }
        }
        let actualPatch = try WatchClockRenderer.patch(configuration: configuration.watch.clock,
                                                        sourceSize: .init(width: 416, height: 496), source: watchCG, layout: detectedLayout)!
        let actualClock = actualPatch.image
        try validateReferenceClock(output: output)
        let clockRect = actualPatch.rect(in: watchScreen)
        var automaticallyReplacesClock = false
        func update(phoneFrame: CGImage? = phoneCG, watchFrame: CGImage = watchCG, controlsWatch: Bool = true) {
            view.update(frame: phoneFrame, overlay: baseImage, screenRect: ScreenshotRenderer.screenRect(configuration: configuration),
                        canvasSize: configuration.resolution.size, backgroundColor: .init(configuration.backgroundColor),
                        controlSessionID: phoneFrame == nil ? nil : phoneID, inputOrientation: 1,
                        onTouch: { phoneEvents.append($0) },
                        watch: .init(frame: watchFrame, overlay: watchOverlayImage, screenRect: watchScreen, screenMask: watchScreenMask,
                                     clock: actualClock, clockRect: clockRect,
                                     controlSessionID: controlsWatch ? watchID : nil, inputOrientation: 1,
                                     onTouch: { watchEvents.append($0) },
                                     clockConfiguration: automaticallyReplacesClock ? configuration.watch.clock : nil,
                                     crownRect: ScreenshotRenderer.watchCrownRect(configuration: configuration),
                                     onCrown: { crownEvents.append($0) },
                                     onCrownRotation: { crownRotations.append($0) }))
        }
        update()
        view.layoutSubtreeIfNeeded()
        let geometry = PreviewScreenGeometry(bounds: view.bounds, canvasSize: configuration.resolution.size,
                                             screenRect: watchScreen, sourceSize: .init(width: 416, height: 496))
        let center = CGPoint(x: geometry.visibleScreenRect.midX, y: geometry.visibleScreenRect.midY)
        view.mouseDown(with: event(.leftMouseDown, point: center, in: view))
        update()
        view.mouseDragged(with: event(.leftMouseDragged, point: .init(x: center.x + 4, y: center.y), in: view))
        view.mouseUp(with: event(.leftMouseUp, point: center, in: view))
        precondition(phoneEvents.isEmpty && watchEvents.map(\.phase) == [.began, .moved, .ended])
        for x in [0.25, 0.5, 0.75] {
            for y in [0.25, 0.5, 0.75] {
                watchEvents.removeAll()
                let point = CGPoint(x: geometry.visibleScreenRect.minX + geometry.visibleScreenRect.width * x,
                                    y: geometry.visibleScreenRect.minY + geometry.visibleScreenRect.height * y)
                view.mouseDown(with: event(.leftMouseDown, point: point, in: view))
                view.mouseUp(with: event(.leftMouseUp, point: point, in: view))
                precondition(watchEvents.map(\.phase) == [.began, .ended] && phoneEvents.isEmpty,
                             "Visible Watch controls must remain hittable across the screen.")
            }
        }
        watchEvents.removeAll()
        update(phoneFrame: nil)
        view.mouseDown(with: event(.leftMouseDown, point: center, in: view))
        update(phoneFrame: nil)
        view.mouseUp(with: event(.leftMouseUp, point: center, in: view))
        precondition(watchEvents.map(\.phase) == [.began, .ended], "Watch gestures must survive frame updates when the phone uses an image file.")
        let crown = ScreenshotRenderer.watchCrownRect(configuration: configuration)
        let crownPoint = CGPoint(x: geometry.canvasRect.minX + crown.midX * geometry.scale,
                                 y: geometry.canvasRect.minY + crown.midY * geometry.scale)
        watchEvents.removeAll()
        view.mouseDown(with: event(.leftMouseDown, point: crownPoint, in: view))
        update(phoneFrame: nil)
        view.mouseUp(with: event(.leftMouseUp, point: crownPoint, in: view))
        precondition(crownEvents == [true, false] && watchEvents.isEmpty && phoneEvents.isEmpty,
                     "The bezel crown must receive press/release without forwarding a screen touch.")
        crownEvents.removeAll()
        view.mouseDown(with: event(.leftMouseDown, point: crownPoint, in: view))
        view.cancelOperation(nil)
        precondition(crownEvents == [true, false], "Cancelling input must release the Digital Crown.")
        update()
        let phoneScreen = ScreenshotRenderer.screenRect(configuration: configuration)
        let phoneGeometry = PreviewScreenGeometry(bounds: view.bounds, canvasSize: configuration.resolution.size,
                                                  screenRect: phoneScreen, sourceSize: .init(width: 400, height: 850))
        let phonePoint = CGPoint(x: phoneGeometry.visibleScreenRect.midX, y: phoneGeometry.visibleScreenRect.minY + 50)
        let staticIsland = CGPoint(x: phoneGeometry.visibleScreenRect.midX,
                                   y: phoneGeometry.visibleScreenRect.minY + phoneGeometry.visibleScreenRect.height * 0.035)
        let actualIsland = CGPoint(x: phoneGeometry.imageRect.midX,
                                   y: phoneGeometry.imageRect.minY + phoneGeometry.imageRect.height * 0.08)
        for point in [staticIsland, actualIsland] {
            view.mouseDown(with: event(.leftMouseDown, point: point, in: view))
            view.mouseUp(with: event(.leftMouseUp, point: point, in: view))
            precondition(phoneEvents.map(\.phase) == [.began, .ended],
                         "Static and actual Dynamic Island locations must forward touches to the phone.")
            let expected = phoneGeometry.normalizedPoint(for: point)!
            precondition(abs(phoneEvents[0].point.x - expected.x) < 1e-8
                         && abs(phoneEvents[0].point.y - expected.y) < 1e-8,
                         "Dynamic Island touches must use the same source transform as its displayed pixels.")
            phoneEvents.removeAll()
        }
        func scroll(at point: CGPoint, delta: CGFloat, precise: Bool = true, momentum: NSEvent.Phase = []) {
            view.scrollWheel(with: TestScrollEvent(location: view.convert(point, to: nil), delta: delta,
                                                  precise: precise, momentum: momentum))
        }
        scroll(at: center, delta: 12.5)
        update(phoneFrame: nil)
        scroll(at: crownPoint, delta: -3, precise: false)
        scroll(at: center, delta: 0)
        scroll(at: center, delta: .nan)
        scroll(at: center, delta: .infinity)
        scroll(at: center, delta: 10, momentum: .changed)
        scroll(at: phonePoint, delta: 10)
        scroll(at: .zero, delta: 10)
        scroll(at: geometry.visibleScreenRect.origin, delta: 10)
        precondition(crownRotations == [-12.5, 3],
                     "Wheel and trackpad scrolling must rotate only on the visible Watch screen/crown with native direction.")
        update(controlsWatch: false)
        scroll(at: center, delta: 10)
        scroll(at: crownPoint, delta: 10)
        precondition(crownRotations == [-12.5, 3], "Inactive Watch previews must not capture crown scrolling.")
        update()
        view.mouseDown(with: event(.leftMouseDown, point: phonePoint, in: view))
        view.mouseUp(with: event(.leftMouseUp, point: phonePoint, in: view))
        precondition(phoneEvents.map(\.phase) == [.began, .ended])
        let expected = try ScreenshotRenderer.render(configuration: configuration, screenshot: phone,
                                                      maximumDimension: 1100, watchScreenshot: watch)
        let native = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: base.pixelsWide, pixelsHigh: base.pixelsHigh,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
        let graphics = NSGraphicsContext(bitmapImageRep: native)!
        graphics.cgContext.translateBy(x: 0, y: CGFloat(native.pixelsHigh))
        graphics.cgContext.scaleBy(x: 1, y: -1)
        view.layer!.render(in: graphics.cgContext)
        try native.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Native-preview.png"))
        try expected.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Expected-preview.png"))
        var totalDifference = 0.0
        var samples = 0
        for y in stride(from: 0, to: expected.pixelsHigh, by: 11) {
            for x in stride(from: 0, to: expected.pixelsWide, by: 11) {
                let expectedColor = expected.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let actualColor = native.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                totalDifference += max(abs(expectedColor.redComponent - actualColor.redComponent),
                                       abs(expectedColor.greenComponent - actualColor.greenComponent),
                                       abs(expectedColor.blueComponent - actualColor.blueComponent))
                samples += 1
            }
        }
        let averageDifference = totalDifference / Double(samples)
        precondition(averageDifference < 0.008, "Native dual-stream composition must match export: \(averageDifference)")
        automaticallyReplacesClock = true
        update()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let start = ContinuousClock.now
        for index in 0..<2400 { update(watchFrame: index.isMultiple(of: 2) ? watchCG : alternateWatch) }
        let duration = start.duration(to: .now)
        let components = duration.components
        let milliseconds = (Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15) / 2400
        precondition(milliseconds < 1000 / 120, "CPU layer updates must fit within the 120 fps frame budget.")
        let hosted = NSHostingView(rootView: LiveScreenshotPreview(
            frame: phoneCG, overlay: baseImage,
            screenRect: ScreenshotRenderer.screenRect(configuration: configuration),
            canvasSize: configuration.resolution.size, backgroundColor: .init(configuration.backgroundColor),
            controlSessionID: phoneID, inputOrientation: 1, onTouch: { phoneEvents.append($0) },
            watch: .init(frame: watchCG, overlay: watchOverlayImage, screenRect: watchScreen,
                         screenMask: watchScreenMask, clock: nil, clockRect: .zero,
                         controlSessionID: watchID, inputOrientation: 1, onTouch: { watchEvents.append($0) },
                         crownRect: crown, onCrown: { crownEvents.append($0) },
                         onCrownRotation: { crownRotations.append($0) })
        ).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 32).padding(.vertical, 16))
        hosted.sizingOptions = []
        window.contentView = hosted
        window.layoutIfNeeded()
        hosted.layoutSubtreeIfNeeded()
        func canvas(in view: NSView) -> LiveCanvasView? {
            if let view = view as? LiveCanvasView { return view }
            return view.subviews.lazy.compactMap { canvas(in: $0) }.first
        }
        let hostedCanvas = canvas(in: hosted)!
        let hostedGeometry = PreviewScreenGeometry(bounds: hostedCanvas.bounds, canvasSize: configuration.resolution.size,
                                                   screenRect: watchScreen, sourceSize: .init(width: 416, height: 496))
        let hostedCenter = CGPoint(x: hostedGeometry.visibleScreenRect.midX, y: hostedGeometry.visibleScreenRect.midY)
        let hostedCrown = CGPoint(x: hostedGeometry.canvasRect.minX + crown.midX * hostedGeometry.scale,
                                  y: hostedGeometry.canvasRect.minY + crown.midY * hostedGeometry.scale)
        watchEvents.removeAll()
        crownEvents.removeAll()
        for point in [hostedCenter, hostedCrown] {
            let hit = hosted.hitTest(hosted.convert(point, from: hostedCanvas))
            precondition(hit === hostedCanvas, "SwiftUI hosting and padding must preserve Watch screen/crown hit testing.")
            hit!.mouseDown(with: event(.leftMouseDown, point: point, in: hostedCanvas))
            hit!.mouseUp(with: event(.leftMouseUp, point: point, in: hostedCanvas))
            hit!.scrollWheel(with: TestScrollEvent(location: hostedCanvas.convert(point, to: nil), delta: 4,
                                                  precise: true, momentum: []))
        }
        precondition(watchEvents.map(\.phase) == [.began, .ended] && crownEvents == [true, false],
                     "Hosted preview must deliver Watch touches and crown presses through AppKit hit testing.")
        precondition(crownRotations == [-12.5, 3, -4, -4],
                     "SwiftUI hosting must deliver scrolling over both the Watch screen and crown.")
        let hostedPhone = PreviewScreenGeometry(bounds: hostedCanvas.bounds, canvasSize: configuration.resolution.size,
                                                screenRect: phoneScreen, sourceSize: .init(width: 400, height: 850))
        let hostedIsland = CGPoint(x: hostedPhone.imageRect.midX,
                                   y: hostedPhone.imageRect.minY + hostedPhone.imageRect.height * 0.08)
        let islandHit = hosted.hitTest(hosted.convert(hostedIsland, from: hostedCanvas))
        precondition(islandHit === hostedCanvas, "SwiftUI must preserve Dynamic Island hit testing.")
        phoneEvents.removeAll()
        islandHit!.mouseDown(with: event(.leftMouseDown, point: hostedIsland, in: hostedCanvas))
        islandHit!.mouseUp(with: event(.leftMouseUp, point: hostedIsland, in: hostedCanvas))
        precondition(phoneEvents.map(\.phase) == [.began, .ended])
        window.contentView = nil
        print("Validated 24 Watch frames/masks, all ten iPhone output sizes, cached clock replacement (10,000 lookups in \(cacheDuration)), independent phone/Watch hit routing, crown press/release, wheel/trackpad crown rotation on screen/bezel including SwiftUI hosting, inactive-input rejection, gesture continuity with either phone source, and 2,400 updates averaging \(String(format: "%.3f", milliseconds)) ms/frame.")
    }
    
    @MainActor
    static func validateClockAlignments(output: URL) throws {
        for size: CGSize in [.init(width: 416, height: 496), .init(width: 368, height: 448), .init(width: 448, height: 536)] {
            for alignment: WatchClockLayout.Alignment in [.leading, .center, .trailing] {
                for originalTime in ["0:00", "00:00"] {
                    let fixture = clockSource(size: size, time: originalTime, alignment: alignment)
                    let detected = WatchClockRenderer.analyze(fixture.image)!
                    precondition(detected.alignment == alignment,
                                 "Header clocks must retain their leading, centered, or trailing alignment.")
                    let glyph = CGRect(x: detected.glyphRect.minX * size.width, y: detected.glyphRect.minY * size.height,
                                       width: detected.glyphRect.width * size.width, height: detected.glyphRect.height * size.height)
                    precondition(abs(glyph.minX - fixture.rect.minX) <= 2 && abs(glyph.maxX - fixture.rect.maxX) <= 2
                                 && abs(glyph.minY - fixture.rect.minY) <= 2 && abs(glyph.maxY - fixture.rect.maxY) <= 2,
                                 "Navigation icons must not become part of a detected clock.")
                    for replacement in ["0:00", "00:00"] {
                        let patch = try WatchClockRenderer.patch(configuration: .init(isEnabled: true, time: replacement),
                                                                  sourceSize: size, source: fixture.image, layout: detected)!
                        let rect = patch.rect(in: .init(origin: .zero, size: size))
                        precondition(rect.contains(glyph), "Replacement patches must erase the whole original clock when it shrinks.")
                        let bitmap = NSBitmapImageRep(cgImage: patch.image)
                        var ink = CGRect.null
                        for y in 0..<bitmap.pixelsHigh {
                            for x in 0..<bitmap.pixelsWide {
                                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 {
                                    ink = ink.union(.init(x: x, y: y, width: 1, height: 1))
                                }
                            }
                        }
                        ink = ink.offsetBy(dx: rect.minX, dy: rect.minY)
                        let difference: CGFloat
                        switch alignment {
                        case .leading: difference = ink.minX - glyph.minX
                        case .center: difference = ink.midX - glyph.midX
                        case .trailing: difference = ink.maxX - glyph.maxX
                        }
                        precondition(abs(difference) <= 2,
                                     "Changing the hour digit count must preserve the detected alignment: \(alignment), \(difference).")
                        if size.width == 416 {
                            try bitmap.representation(using: .png, properties: [:])!
                                .write(to: output.appendingPathComponent("Clock-\(alignment)-\(originalTime.replacingOccurrences(of: ":", with: "-"))-to-\(replacement.replacingOccurrences(of: ":", with: "-")).png"))
                        }
                    }
                }
            }
        }
        let contentOnly = clockSource(size: .init(width: 416, height: 496), time: nil, alignment: .center)
        precondition(WatchClockRenderer.analyze(contentOnly.image) == nil,
                     "A time inside screen content must not be mistaken for the status clock.")
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let current = NSBitmapImageRep(data: try Data(contentsOf: fixtures.appendingPathComponent("Centered-watchOS.png")))!.cgImage!
        let layout = WatchClockRenderer.analyze(current)!
        precondition(layout.alignment == .center && abs(layout.glyphRect.midX - 0.5) < 0.01,
                     "The current watchOS reader clock must be detected between its navigation buttons.")
        let size = CGSize(width: current.width, height: current.height)
        let patch = try WatchClockRenderer.patch(configuration: .init(isEnabled: true, time: "9:41"),
                                                  sourceSize: size, source: current, layout: layout)!
        let rect = patch.rect(in: .init(origin: .zero, size: size))
        let context = CGContext(data: nil, width: current.width, height: current.height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(current, in: .init(origin: .zero, size: size))
        context.draw(patch.image, in: .init(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height))
        try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("Centered-watchOS-adjusted.png"))
        print("Validated clock detection and hour-width changes for leading, centered, and trailing headers, including the current watchOS screen.")
    }

    static func validateLiveClockAlignments() throws {
        let size = CGSize(width: 416, height: 496)
        let screen = CGRect(origin: .zero, size: size)
        let view = LiveCanvasView(frame: screen)
        let empty = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let session = UUID()
        let configuration = WatchClockConfiguration(isEnabled: true, time: "00:00")
        for alignment: WatchClockLayout.Alignment in [.trailing, .center, .leading] {
            let fixture = clockSource(size: size, time: "0:00", alignment: alignment)
            let layout = WatchClockRenderer.analyze(fixture.image)!
            let expected = try WatchClockRenderer.patch(configuration: configuration, sourceSize: size,
                                                         source: fixture.image, layout: layout)!.rect(in: screen)
            view.update(frame: nil, overlay: empty, screenRect: .zero, canvasSize: size, backgroundColor: .black,
                        controlSessionID: nil, inputOrientation: 1, onTouch: { _ in },
                        watch: .init(frame: fixture.image, overlay: empty, screenRect: screen, screenMask: nil,
                                     clock: nil, clockRect: .zero, controlSessionID: session, inputOrientation: 1,
                                     onTouch: { _ in }, clockConfiguration: configuration))
            let canvas = view.layer!.sublayers!.first!
            let clip = canvas.sublayers!.first { $0.sublayers?.count == 2 }!
            let clock = clip.sublayers!.last!
            func matches() -> Bool {
                clock.contents != nil && abs(clock.frame.minX - expected.minX) < 0.001
                    && abs(clock.frame.minY - expected.minY) < 0.001
                    && abs(clock.frame.width - expected.width) < 0.001
                    && abs(clock.frame.height - expected.height) < 0.001
            }
            let deadline = Date().addingTimeInterval(2)
            while !matches() && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            precondition(matches(),
                         "Live preview must re-detect \(alignment) in the same simulator session: \(clock.frame), expected \(expected).")
        }
        func update(_ image: CGImage, enabled: Bool = true) {
            var setting = configuration
            setting.isEnabled = enabled
            view.update(frame: nil, overlay: empty, screenRect: .zero, canvasSize: size, backgroundColor: .black,
                        controlSessionID: nil, inputOrientation: 1, onTouch: { _ in },
                        watch: .init(frame: image, overlay: empty, screenRect: screen, screenMask: nil,
                                     clock: nil, clockRect: .zero, controlSessionID: session, inputOrientation: 1,
                                     onTouch: { _ in }, clockConfiguration: setting))
        }
        let canvas = view.layer!.sublayers!.first!
        let clock = canvas.sublayers!.first { $0.sublayers?.count == 2 }!.sublayers!.last!
        let leading = clockSource(size: size, time: "0:00", alignment: .leading)
        let trailing = clockSource(size: size, time: "0:00", alignment: .trailing)
        let distance = trailing.rect.minX - leading.rect.minX
        let animation = (0...40).map { index -> (CGImage, CGRect) in
            let fixture = clockSource(size: size, time: "0:00", alignment: .leading,
                                      horizontalOffset: distance * CGFloat(index) / 40, showsNavigationButton: false)
            let layout = WatchClockRenderer.analyze(fixture.image)!
            let expected = try! WatchClockRenderer.patch(configuration: configuration, sourceSize: size,
                                                          source: fixture.image, layout: layout)!.rect(in: screen)
            return (fixture.image, expected)
        }
        for (image, expected) in animation {
            update(image)
            precondition(clock.contents != nil && abs(clock.frame.midX - expected.midX) < 0.001
                         && abs(clock.frame.midY - expected.midY) < 0.001,
                         "The replacement clock must follow each animation frame without waiting for Vision.")
            RunLoop.current.run(until: Date().addingTimeInterval(1.0 / 120))
        }
        let obscured = clockSource(size: size, time: nil, alignment: .center)
        update(obscured.image)
        precondition(clock.contents == nil, "An unreadable animation frame must not keep an old replacement clock visible.")
        update(leading.image)
        let finalLayout = WatchClockRenderer.analyze(leading.image)!
        let finalRect = try WatchClockRenderer.patch(configuration: configuration, sourceSize: size,
                                                      source: leading.image, layout: finalLayout)!.rect(in: screen)
        let deadline = Date().addingTimeInterval(2)
        while (clock.contents == nil || abs(clock.frame.midX - finalRect.midX) >= 0.001) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(clock.contents != nil && abs(clock.frame.midX - finalRect.midX) < 0.001,
                     "Analysis of an old animation frame must drain to the final frame even when no more frames arrive.")
        update(obscured.image)
        update(trailing.image, enabled: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(clock.contents == nil, "A delayed analysis must not restore a disabled clock overlay.")
        print("Validated per-frame clock animation tracking, final-frame recovery, and cancellation of stale recognition.")
    }

    static func clockSource(
        size: CGSize,
        time: String?,
        alignment: WatchClockLayout.Alignment,
        horizontalOffset: CGFloat = 0,
        showsNavigationButton: Bool = true
    ) -> (image: CGImage, rect: CGRect) {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.black.cgColor)
        context.fill(.init(origin: .zero, size: size))
        let font = WatchClockRenderer.clockFont(size: size.width * 38 / 416)
        func text(_ value: String) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
                .init(kCTFontAttributeName as String): font,
                .init(kCTForegroundColorAttributeName as String): NSColor.white.cgColor
            ]))
        }
        context.textPosition = .init(x: 20, y: size.height * 0.5)
        CTLineDraw(text("12:34"), context)
        var rect = CGRect.zero
        if let time {
            let line = text(time)
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let left: CGFloat
            switch alignment {
            case .leading: left = size.width * 0.06
            case .center: left = (size.width - ink.width) / 2
            case .trailing: left = size.width * 0.91 - ink.width
            }
            rect = .init(x: left + horizontalOffset, y: size.height * 0.06, width: ink.width, height: ink.height)
            context.textPosition = .init(x: rect.minX - ink.minX, y: size.height - rect.minY - ink.maxY)
            CTLineDraw(line, context)
            if showsNavigationButton {
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: .init(x: alignment == .trailing ? size.width * 0.04 : size.width * 0.86,
                                              y: size.height - rect.maxY, width: ink.height, height: ink.height))
            }
        }
        return (context.makeImage()!, rect)
    }

    static func validateReferenceClock(output: URL) throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let reference = NSBitmapImageRep(data: try Data(contentsOf: fixtures.appendingPathComponent("34-2.png")))!
        let previous = NSBitmapImageRep(data: try Data(contentsOf: fixtures.appendingPathComponent("34-1.png")))!
        let size = CGSize(width: reference.pixelsWide, height: reference.pixelsHigh)
        let layout = WatchClockLayout(glyphRect: .init(x: 58 / size.width, y: 26 / size.height,
                                                       width: 49 / size.width, height: 16 / size.height),
                                      originalTime: "4:34", minuteDigitGap: 14 / size.width)
        let patch = try WatchClockRenderer.patch(configuration: .init(isEnabled: true, time: "4:34"),
                                                  sourceSize: size, source: reference.cgImage!, layout: layout)!
        let adjusted = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: reference.pixelsWide, pixelsHigh: reference.pixelsHigh,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
        let graphics = NSGraphicsContext(bitmapImageRep: adjusted)!
        graphics.cgContext.translateBy(x: 0, y: size.height)
        graphics.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
        NSImage(cgImage: reference.cgImage!, size: .zero).draw(in: .init(origin: .zero, size: size),
                                                            from: .zero, operation: .sourceOver, fraction: 1,
                                                            respectFlipped: true, hints: nil)
        NSImage(cgImage: patch.image, size: .zero).draw(in: patch.rect(in: .init(origin: .zero, size: size)),
                                                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        let renderedData = adjusted.representation(using: .png, properties: [:])!
        try renderedData.write(to: output.appendingPathComponent("Reference-clock-adjusted.png"))
        let rendered = NSBitmapImageRep(data: renderedData)!
        var previousError = 0.0
        var adjustedError = 0.0
        for y in 23..<45 {
            for x in 52..<111 {
                let target = reference.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent
                let before = previous.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent
                let after = rendered.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent
                previousError += pow(before - target, 2)
                adjustedError += pow(after - target, 2)
            }
        }
        let count = Double(22 * 59)
        print("Watch clock reference MSE: previous \(previousError / count), adjusted \(adjustedError / count).")
        precondition(adjustedError < previousError * 0.25,
                     "The lighter font, minute digit spacing, and colon padding must match the supplied watchOS reference more closely.")
        func glyphColumns(_ bitmap: NSBitmapImageRep) -> [ClosedRange<Int>] {
            var result: [ClosedRange<Int>] = []
            for x in 52..<111 {
                guard (23..<45).contains(where: { y in
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    return min(color.redComponent, color.greenComponent, color.blueComponent) > 0.6
                }) else { continue }
                if let last = result.last, last.upperBound + 1 == x {
                    result[result.count - 1] = last.lowerBound...x
                } else {
                    result.append(x...x)
                }
            }
            return result
        }
        let referenceColumns = glyphColumns(reference)
        let adjustedColumns = glyphColumns(rendered)
        precondition(referenceColumns.count == 4 && adjustedColumns.count == 4)
        for (expected, actual) in zip(referenceColumns, adjustedColumns) {
            precondition(abs(expected.lowerBound - actual.lowerBound) <= 1
                         && abs(expected.upperBound - actual.upperBound) <= 1,
                         "Each digit and the colon must align with the reference within one raster pixel.")
        }
    }
    
    @MainActor
    static func event(_ type: NSEvent.EventType, point: CGPoint, in view: NSView) -> NSEvent {
        .mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    
    @MainActor
    static func source(width: Int, height: Int, isWatch: Bool) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor(calibratedRed: isWatch ? 0.02 : 0.1, green: isWatch ? 0.02 : 0.2, blue: isWatch ? 0.02 : 0.5, alpha: 1).setFill()
        NSBezierPath(rect: .init(x: 0, y: 0, width: width, height: height)).fill()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: .init(x: 0, y: height - 12, width: width, height: 12)).fill()
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: .init(x: 0, y: 0, width: width, height: 12)).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSAttributedString(string: isWatch ? "Watch\nCompanion" : "Your app\non iPhone", attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(width) * 0.11, weight: .medium),
            .foregroundColor: NSColor.white, .paragraphStyle: paragraph
        ])
        text.draw(in: .init(x: 0, y: height / 2 - 60, width: width, height: 150))
        if isWatch {
            let font = WatchClockRenderer.clockFont(size: 38)
            let time = CTLineCreateWithAttributedString(NSAttributedString(string: "9:41", attributes: [
                .init(kCTFontAttributeName as String): font,
                .init(kCTForegroundColorAttributeName as String): NSColor.white.cgColor
            ]))
            let ink = CTLineGetBoundsWithOptions(time, .useGlyphPathBounds)
            graphics.cgContext.textPosition = .init(x: CGFloat(width) - 38 - ink.maxX, y: CGFloat(height) - 40 - ink.maxY)
            CTLineDraw(time, graphics.cgContext)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: .init(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }
}
