import AppKit
import Observation

@MainActor
@Observable
final class SimulatorFeed {
    private let client: SimulatorClient
    private let isWatch: Bool
    private let frameSource: @Sendable (String, String) -> SimulatorFrameStream
    
    init(
        client: SimulatorClient = .init(),
        isWatch: Bool = false,
        frameSource: (@Sendable (String, String) -> SimulatorFrameStream)? = nil
    ) {
        self.client = client
        self.isWatch = isWatch
        self.frameSource = frameSource ?? { SimulatorFrames.open(deviceID: $0, developerDirectory: $1, isWatch: isWatch) }
    }
    
    private(set) var devices: [RunningSimulator] = []
    var selectedDeviceID: String?
    @ObservationIgnored private var activeStream: SimulatorFrameStream?
    private(set) var inputSessionID: UUID?
    private(set) var inputOrientation: UInt32 = 1
    private(set) var inputError: String?
    private(set) var frameSize = CGSize.zero
    private(set) var hasFrame = false
    private(set) var frame: CGImage?
    private(set) var imageDeviceID: String?
    private(set) var imageSize = ""
    private(set) var frameRevision = UUID()
    private(set) var listError: String?
    private(set) var captureError: String?
    private(set) var isRefreshing = false
    private(set) var lastCapture: Date?
    
    var selectedDevice: RunningSimulator? { devices.first { $0.id == selectedDeviceID } }
    var hasCurrentFrame: Bool { hasFrame && imageDeviceID == selectedDeviceID }
    var currentFrame: CGImage? { imageDeviceID == selectedDeviceID ? frame : nil }
    
    func monitorDevices() async {
        while !Task.isCancelled {
            await refreshDevices()
            do {
                try await Task.sleep(for: .seconds(3))
            } catch { return }
        }
    }
    
    func refreshDevices(automaticallySelectsDevice: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let devices = try await client.runningDevices().filter { $0.isWatch == isWatch }
            try Task.checkCancellation()
            self.devices = devices
            listError = nil
            if !devices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = automaticallySelectsDevice ? devices.first?.id : nil
                clearImage()
            }
        } catch is CancellationError {
        } catch {
            listError = error.localizedDescription
        }
    }
    
    func stream(deviceID: String) async {
        clearImage()
        captureError = nil
        do {
            let directory = try await client.developerDirectory()
            try Task.checkCancellation()
            let stream = frameSource(deviceID, directory)
            activeStream = stream
            inputSessionID = stream.id
            defer {
                stream.stop()
                if activeStream?.id == stream.id {
                    activeStream = nil
                    inputSessionID = nil
                }
            }
            for try await frame in stream.frames {
                try Task.checkCancellation()
                guard selectedDeviceID == deviceID else { return }
                accept(frame, deviceID: deviceID)
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, selectedDeviceID == deviceID else { return }
            captureError = error.localizedDescription
        }
    }
    
    func sendTouch(_ event: SimulatorTouchEvent, sessionID: UUID) {
        guard let stream = activeStream, stream.id == sessionID,
              imageDeviceID == selectedDeviceID, currentFrame != nil else { return }
        if event.phase == .began { inputError = nil }
        stream.sendTouch(event) { [weak self] error in
            guard let self, let error else { return }
            Task { @MainActor in
                guard self.activeStream?.id == sessionID else { return }
                self.inputError = error.localizedDescription
            }
        }
    }
    
    func sendCrown(isPressed: Bool, sessionID: UUID) {
        guard isWatch, let stream = activeStream, stream.id == sessionID,
              imageDeviceID == selectedDeviceID, currentFrame != nil else { return }
        if isPressed { inputError = nil }
        stream.sendCrown(isPressed) { [weak self] error in
            guard let self, let error else { return }
            Task { @MainActor in
                guard self.activeStream?.id == sessionID else { return }
                self.inputError = error.localizedDescription
            }
        }
    }
    
    func rotateCrown(by delta: Double, sessionID: UUID) {
        guard delta.isFinite, delta != 0, isWatch,
              let stream = activeStream, stream.id == sessionID,
              imageDeviceID == selectedDeviceID, currentFrame != nil else { return }
        inputError = nil
        stream.rotateCrown(delta) { [weak self] error in
            guard let self, let error else { return }
            Task { @MainActor in
                guard self.activeStream?.id == sessionID else { return }
                self.inputError = error.localizedDescription
            }
        }
    }
    
    func applyStatusBar(_ configuration: SimulatorStatusBarConfiguration, deviceID: String) async throws {
        try await client.applyStatusBar(configuration, deviceID: deviceID)
    }
    
    func clearStatusBar(deviceID: String) async throws {
        try await client.clearStatusBar(deviceID: deviceID)
    }
    
    func captureForExport(deviceID: String) async throws -> NSImage {
        try Task.checkCancellation()
        guard selectedDeviceID == deviceID else { throw CancellationError() }
        guard let frame = currentFrame else { throw SimulatorClient.ClientError.invalidScreenshot }
        let image = NSImage(size: .init(width: frame.width, height: frame.height))
        image.addRepresentation(NSBitmapImageRep(cgImage: frame))
        return image
    }
    
    private func accept(_ videoFrame: SimulatorVideoFrame, deviceID: String) {
        let frame = videoFrame.image
        self.frame = frame
        if inputOrientation != videoFrame.inputOrientation { inputOrientation = videoFrame.inputOrientation }
        if imageDeviceID != deviceID { imageDeviceID = deviceID }
        let size = CGSize(width: frame.width, height: frame.height)
        if frameSize != size {
            frameSize = size
            imageSize = "\(frame.width) × \(frame.height) px"
        }
        if !hasFrame { hasFrame = true }
        if captureError != nil { captureError = nil }
        if lastCapture == nil { lastCapture = .now }
        frameRevision = UUID()
    }
    
    private func clearImage() {
        captureError = nil
        inputError = nil
        frame = nil
        hasFrame = false
        frameSize = .zero
        imageDeviceID = nil
        imageSize = ""
        lastCapture = nil
        frameRevision = UUID()
    }
}

nonisolated struct SimulatorVideoFrame: Sendable {
    let image: CGImage
    let inputOrientation: UInt32
}

nonisolated struct SimulatorTouchEvent: Sendable {
    let point: CGPoint
    let phase: SimulatorTouchPhase
    let inputOrientation: UInt32
}

nonisolated struct SimulatorFrameStream: Sendable {
    let id = UUID()
    let frames: AsyncThrowingStream<SimulatorVideoFrame, Error>
    let stop: @Sendable () -> Void
    let sendTouch: @Sendable (SimulatorTouchEvent, @escaping @Sendable (Error?) -> Void) -> Void
    var sendCrown: @Sendable (Bool, @escaping @Sendable (Error?) -> Void) -> Void = { _, _ in }
    var rotateCrown: @Sendable (Double, @escaping @Sendable (Error?) -> Void) -> Void = { _, _ in }
}

nonisolated enum SimulatorFrames {
    static func open(deviceID: String, developerDirectory: String, isWatch: Bool = false) -> SimulatorFrameStream {
        let (frames, continuation) = AsyncThrowingStream<SimulatorVideoFrame, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let framebuffer = SimulatorFramebuffer()
        framebuffer.start(
            withDeviceID: deviceID,
            developerDirectory: developerDirectory,
            isWatch: isWatch,
            frameHandler: { continuation.yield(.init(image: $0, inputOrientation: $1)) },
            failureHandler: { continuation.finish(throwing: $0) }
        )
        continuation.onTermination = { _ in framebuffer.stop() }
        return .init(
            frames: frames,
            stop: { framebuffer.stop() },
            sendTouch: { event, completion in
                framebuffer.sendTouch(
                    at: event.point,
                    phase: event.phase,
                    inputOrientation: event.inputOrientation,
                    completion: { completion($0) }
                )
            },
            sendCrown: { isPressed, completion in
                framebuffer.sendCrownPressed(isPressed, completion: { completion($0) })
            },
            rotateCrown: { delta, completion in
                framebuffer.sendCrownRotation(delta, completion: { completion($0) })
            }
        )
    }
}
