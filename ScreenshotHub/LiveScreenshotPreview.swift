import AppKit
import SwiftUI
import QuartzCore

struct LiveWatchPreview {
    var frame: CGImage?
    var overlay: CGImage
    var screenRect: CGRect
    var screenMask: CGImage?
    var clock: CGImage?
    var clockRect: CGRect
    var controlSessionID: UUID?
    var inputOrientation: UInt32
    var onTouch: (SimulatorTouchEvent) -> Void
    var clockConfiguration: WatchClockConfiguration? = nil
    var crownRect: CGRect = .zero
    var onCrown: (Bool) -> Void = { _ in }
    var onCrownRotation: (Double) -> Void = { _ in }
}
    
struct LiveScreenshotPreview: NSViewRepresentable {
    var frame: CGImage?
    var overlay: CGImage
    var screenRect: CGRect
    var canvasSize: CGSize
    var backgroundColor: NSColor
    var controlSessionID: UUID?
    var inputOrientation: UInt32
    var onTouch: (SimulatorTouchEvent) -> Void
    var watch: LiveWatchPreview? = nil
    
    func makeNSView(context: Context) -> LiveCanvasView {
        .init()
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LiveCanvasView, context: Context) -> CGSize? {
        proposal.viewportSize(idealSize: .init(width: 360, height: 480))
    }
    
    func updateNSView(_ view: LiveCanvasView, context: Context) {
        view.update(
            frame: frame,
            overlay: overlay,
            screenRect: screenRect,
            canvasSize: canvasSize,
            backgroundColor: backgroundColor,
            controlSessionID: controlSessionID,
            inputOrientation: inputOrientation,
            onTouch: onTouch,
            watch: watch
        )
    }
}

final class LiveCanvasView: NSView {
    private let canvasLayer = CALayer()
    private let screenClipLayer = CALayer()
    private let screenLayer = CALayer()
    private let watchClipLayer = CALayer()
    private let watchScreenLayer = CALayer()
    private let watchClockLayer = CALayer()
    private let watchOverlayLayer = CALayer()
    private let overlayLayer = CALayer()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        canvasLayer.masksToBounds = true
        screenLayer.contentsGravity = .resize
        overlayLayer.contentsGravity = .resize
        layer?.addSublayer(canvasLayer)
        screenClipLayer.masksToBounds = true
        watchClipLayer.masksToBounds = true
        canvasLayer.addSublayer(screenClipLayer)
        screenClipLayer.addSublayer(screenLayer)
        canvasLayer.addSublayer(overlayLayer)
        canvasLayer.addSublayer(watchClipLayer)
        watchClipLayer.addSublayer(watchScreenLayer)
        watchClipLayer.addSublayer(watchClockLayer)
        canvasLayer.addSublayer(watchOverlayLayer)
    }
    
    required init?(coder: NSCoder) { nil }
    
    private var screenRect = CGRect.zero
    private var canvasSize = CGSize(width: 1, height: 1)
    private var currentOverlay: CGImage?
    private var sourceSize = CGSize(width: 1, height: 1)
    private var screenMask: PreviewScreenMask?
    private var controlSessionID: UUID?
    private var inputOrientation: UInt32 = 1
    private var isControlAvailable = false
    private var onTouch: ((SimulatorTouchEvent) -> Void)?
    private var gestureHandler: ((SimulatorTouchEvent) -> Void)?
    private var gestureOrientation: UInt32 = 1
    private var lastTouch = CGPoint.zero
    private var lastBounds = CGRect.zero
    private var focusObserver: NSObjectProtocol?
    private var watch: LiveWatchPreview?
    private var watchSourceSize = CGSize(width: 1, height: 1)
    private var watchMask: PreviewScreenMask?
    private var watchScreenHitMask: PreviewScreenMask?
    private var currentWatchScreenMask: CGImage?
    private var crownHandler: ((Bool) -> Void)?
    private var currentWatchOverlay: CGImage?
    private var clockLayout: WatchClockLayout?
    private var clockPatch: WatchClockPatch?
    private var clockAnalysis: Task<Void, Never>?
    private var lastClockRecognition = ContinuousClock.now - .seconds(3)
    private var clockSessionID = UUID()
    private var gestureGeometry: PreviewScreenGeometry?
    
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isControlAvailable || watch?.controlSessionID != nil }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { acceptsFirstResponder }
    
    override func layout() {
        super.layout()
        if lastBounds != bounds { endGesture() }
        lastBounds = bounds
        updateLayout()
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        endGesture()
        resetWatchClock()
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        focusObserver = nil
        super.viewWillMove(toWindow: newWindow)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackingScale()
        guard let window else { return }
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endGesture() }
        }
    }
    
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingScale()
    }
    
    private func updateBackingScale() {
        let scale = window?.backingScaleFactor ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for imageLayer in [layer, canvasLayer, screenClipLayer, screenLayer, overlayLayer,
                           watchClipLayer, watchScreenLayer, watchClockLayer, watchOverlayLayer,
                           watchClipLayer.mask].compactMap({ $0 }) {
            imageLayer.contentsScale = scale
            imageLayer.minificationFilter = .trilinear
            imageLayer.magnificationFilter = .linear
        }
        CATransaction.commit()
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let watch, watch.controlSessionID != nil, watch.frame != nil,
           let canvasPoint = geometry.canvasPoint(for: point), watch.crownRect.contains(canvasPoint) {
            endGesture()
            window?.makeFirstResponder(self)
            crownHandler = watch.onCrown
            crownHandler?(true)
            return
        }
        let targetsWatch = watchGeometry?.visibleScreenRect.contains(point) == true
        let targetGeometry = targetsWatch ? watchGeometry : geometry
        let handler: ((SimulatorTouchEvent) -> Void)?
        let orientation: UInt32
        if targetsWatch, let watch, watch.controlSessionID != nil, watch.frame != nil,
           isWatchScreenPoint(point) {
            handler = watch.onTouch
            orientation = watch.inputOrientation
        } else if !targetsWatch, !watchOccludes(point), isControlAvailable, isScreenPoint(point) {
            handler = onTouch
            orientation = inputOrientation
        } else {
            super.mouseDown(with: event)
            return
        }
        guard let targetGeometry, let normalized = targetGeometry.normalizedPoint(for: point) else { return }
        endGesture()
        window?.makeFirstResponder(self)
        gestureHandler = handler
        gestureGeometry = targetGeometry
        gestureOrientation = orientation
        lastTouch = normalized
        gestureHandler?(.init(point: normalized, phase: .began, inputOrientation: gestureOrientation))
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard gestureHandler != nil,
              let point = gestureGeometry?.normalizedPoint(for: convert(event.locationInWindow, from: nil), clamping: true) else { return }
        lastTouch = point
        gestureHandler?(.init(point: point, phase: .moved, inputOrientation: gestureOrientation))
    }
    
    override func mouseUp(with event: NSEvent) {
        if let point = gestureGeometry?.normalizedPoint(for: convert(event.locationInWindow, from: nil), clamping: true) {
            lastTouch = point
        }
        endGesture()
    }
    
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let watch, watch.controlSessionID != nil, watch.frame != nil,
              let canvasPoint = geometry.canvasPoint(for: point),
              watch.crownRect.contains(canvasPoint)
                || (watchGeometry?.visibleScreenRect.contains(point) == true && isWatchScreenPoint(point)) else {
            super.scrollWheel(with: event)
            return
        }
        // Match SimulatorKit's crown direction and exclude trackpad momentum.
        let delta = -Double(event.scrollingDeltaY)
        guard event.momentumPhase.isEmpty, delta.isFinite, delta != 0 else { return }
        watch.onCrownRotation(delta)
    }
    
    override func cancelOperation(_ sender: Any?) { endGesture() }
    
    func update(
        frame: CGImage?,
        overlay: CGImage,
        screenRect: CGRect,
        canvasSize: CGSize,
        backgroundColor: NSColor,
        controlSessionID: UUID?,
        inputOrientation: UInt32,
        onTouch: @escaping (SimulatorTouchEvent) -> Void,
        watch: LiveWatchPreview? = nil
    ) {
        let sourceSize = frame.map { CGSize(width: $0.width, height: $0.height) } ?? .init(width: 1, height: 1)
        let canControl = controlSessionID != nil && frame != nil
        let watchSize = watch?.frame.map { CGSize(width: $0.width, height: $0.height) } ?? .init(width: 1, height: 1)
        if self.watch?.controlSessionID != watch?.controlSessionID || self.watch?.screenRect != watch?.screenRect
            || self.watch?.crownRect != watch?.crownRect
            || self.watch?.inputOrientation != watch?.inputOrientation || watchSourceSize != watchSize {
            endGesture()
            resetWatchClock()
        }
        self.watch = watch
        if currentWatchScreenMask !== watch?.screenMask {
            currentWatchScreenMask = watch?.screenMask
            watchScreenHitMask = watch?.screenMask.map { .init(image: $0) }
        }
        watchSourceSize = watchSize
        if self.controlSessionID != controlSessionID || self.inputOrientation != inputOrientation
            || self.sourceSize != sourceSize || self.screenRect != screenRect || self.canvasSize != canvasSize || self.isControlAvailable != canControl {
            endGesture()
        }
        self.controlSessionID = controlSessionID
        self.inputOrientation = inputOrientation
        self.isControlAvailable = canControl
        self.onTouch = onTouch
        self.screenRect = screenRect
        self.canvasSize = canvasSize
        self.sourceSize = sourceSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        screenLayer.contents = frame
        watchScreenLayer.contents = watch?.frame
        updateWatchClock()
        watchClockLayer.contents = watch?.clockConfiguration == nil ? watch?.clock : clockPatch?.image
        watchClipLayer.isHidden = watch == nil
        watchOverlayLayer.isHidden = watch == nil
        if currentWatchOverlay !== watch?.overlay {
            watchOverlayLayer.contents = watch?.overlay
            currentWatchOverlay = watch?.overlay
            watchMask = watch.map { .init(image: $0.overlay) }
            if let watch {
                let maskLayer = CALayer()
                maskLayer.contents = watch.screenMask
                maskLayer.contentsScale = window?.backingScaleFactor ?? 1
                watchClipLayer.mask = maskLayer
            } else {
                watchClipLayer.mask = nil
            }
        }
        canvasLayer.backgroundColor = backgroundColor.cgColor
        if currentOverlay !== overlay {
            overlayLayer.contents = overlay
            currentOverlay = overlay
            screenMask = .init(image: overlay)
        }
        CATransaction.commit()
        updateLayout()
    }
    
    private func updateWatchClock() {
        guard let watch, let configuration = watch.clockConfiguration, configuration.isEnabled, let frame = watch.frame else {
            if clockLayout != nil || clockPatch != nil || clockAnalysis != nil { resetWatchClock() }
            return
        }
        let tracked = clockLayout.flatMap { WatchClockRenderer.track(frame, near: $0) }
        if let tracked { clockLayout = tracked }
        clockPatch = tracked.flatMap { layout in
            try? WatchClockRenderer.patch(configuration: configuration, sourceSize: watchSourceSize, source: frame, layout: layout)
        }
        // Track geometry on every frame; Vision only refreshes the source text.
        if clockAnalysis == nil, tracked == nil || lastClockRecognition.duration(to: .now) >= .seconds(2) {
            recognizeWatchClock(in: frame)
        }
    }
    
    private func resetWatchClock() {
        clockAnalysis?.cancel()
        clockAnalysis = nil
        clockSessionID = UUID()
        clockLayout = nil
        clockPatch = nil
        lastClockRecognition = .now - .seconds(3)
    }
    
    private func recognizeWatchClock(in analyzedFrame: CGImage) {
        lastClockRecognition = .now
        let session = clockSessionID
        clockAnalysis = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { WatchClockRenderer.analyze(analyzedFrame) }.value
            guard let self, !Task.isCancelled, self.clockSessionID == session else { return }
            self.clockAnalysis = nil
            guard let current = self.watch, let frame = current.frame,
                  let configuration = current.clockConfiguration, configuration.isEnabled else { return }
            // A delayed result must match the currently displayed frame before moving the overlay.
            let verified = frame === analyzedFrame ? result
                : result.flatMap { WatchClockRenderer.track(frame, near: $0) }
                    ?? self.clockLayout.flatMap { WatchClockRenderer.track(frame, near: $0) }
            if let verified { self.clockLayout = verified }
            self.clockPatch = verified.flatMap { layout in
                try? WatchClockRenderer.patch(configuration: configuration, sourceSize: self.watchSourceSize, source: frame, layout: layout)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.watchClockLayer.contents = self.clockPatch?.image
            self.updateLayout()
            CATransaction.commit()
            if verified == nil, frame !== analyzedFrame {
                self.recognizeWatchClock(in: frame)
            }
        }
    }
    
    private var geometry: PreviewScreenGeometry {
        .init(bounds: bounds, canvasSize: canvasSize, screenRect: screenRect, sourceSize: sourceSize)
    }
    
    private var watchGeometry: PreviewScreenGeometry? {
        watch.map { .init(bounds: bounds, canvasSize: canvasSize, screenRect: $0.screenRect, sourceSize: watchSourceSize) }
    }
    
    private func isWatchScreenPoint(_ point: CGPoint) -> Bool {
        guard let watch, let canvasPoint = geometry.canvasPoint(for: point) else { return false }
        if let watchScreenHitMask {
            let localPoint = CGPoint(x: canvasPoint.x - watch.screenRect.minX, y: canvasPoint.y - watch.screenRect.minY)
            return watchScreenHitMask.opacity(at: localPoint, canvasSize: watch.screenRect.size) >= 0.5
        }
        return watchMask?.contains(canvasPoint, canvasSize: canvasSize) == true
    }
    
    private func watchOccludes(_ point: CGPoint) -> Bool {
        guard let canvasPoint = geometry.canvasPoint(for: point), let watchMask else { return false }
        return watchMask.opacity(at: canvasPoint, canvasSize: canvasSize) >= 0.5
    }
    
    private func isScreenPoint(_ point: CGPoint) -> Bool {
        guard let canvasPoint = geometry.canvasPoint(for: point), let screenMask else { return false }
        return screenMask.contains(canvasPoint, canvasSize: canvasSize)
    }
    
    private func endGesture() {
        let crownHandler = crownHandler
        self.crownHandler = nil
        crownHandler?(false)
        let handler = gestureHandler
        gestureHandler = nil
        gestureGeometry = nil
        handler?(.init(point: lastTouch, phase: .ended, inputOrientation: gestureOrientation))
    }
    
    private func updateLayout() {
        let geometry = geometry
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvasLayer.frame = geometry.canvasRect
        overlayLayer.frame = .init(origin: .zero, size: geometry.canvasRect.size)
        let screen = geometry.visibleScreenRect
        screenClipLayer.frame = screen.offsetBy(dx: -geometry.canvasRect.minX, dy: -geometry.canvasRect.minY)
        screenLayer.frame = geometry.imageRect.offsetBy(dx: -screen.minX, dy: -screen.minY)
        watchOverlayLayer.frame = overlayLayer.frame
        if let watch, let geometry = watchGeometry {
            let screen = CGRect(x: geometry.canvasRect.minX + watch.screenRect.minX * geometry.scale,
                                y: geometry.canvasRect.minY + watch.screenRect.minY * geometry.scale,
                                width: watch.screenRect.width * geometry.scale, height: watch.screenRect.height * geometry.scale)
            watchClipLayer.frame = screen.offsetBy(dx: -geometry.canvasRect.minX, dy: -geometry.canvasRect.minY)
            watchClipLayer.mask?.frame = .init(origin: .zero, size: watchClipLayer.bounds.size)
            watchScreenLayer.frame = geometry.imageRect.offsetBy(dx: -screen.minX, dy: -screen.minY)
            let clockRect = watch.clockRect
            if let clockPatch {
                watchClockLayer.frame = clockPatch.rect(in: geometry.imageRect).offsetBy(dx: -screen.minX, dy: -screen.minY)
            } else {
            watchClockLayer.frame = .init(x: geometry.canvasRect.minX + clockRect.minX * geometry.scale - screen.minX,
                                         y: geometry.canvasRect.minY + clockRect.minY * geometry.scale - screen.minY,
                                         width: clockRect.width * geometry.scale, height: clockRect.height * geometry.scale)
            }
        }
        CATransaction.commit()
    }
}
