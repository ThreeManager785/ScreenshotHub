import AppKit
import Observation

@main
struct ValidateSimulator {
    @MainActor
    static func main() async throws {
        let fixture = CommandLine.arguments[1]
        let client = SimulatorClient(executable: .init(fileURLWithPath: "/usr/bin/python3"), argumentPrefix: [fixture])
        let devices = try await client.runningDevices()
        precondition(Set(devices.map(\.id)) == ["PHONE", "IPAD", "WATCH"])
        precondition(devices.first { $0.id == "PHONE" }?.runtime == "iOS 27.0")
        precondition(devices.first { $0.id == "IPAD" }?.isIPad == true)
        precondition(devices.first { $0.id == "PHONE" }?.isIPad == false)
        precondition(devices.first { $0.id == "WATCH" }?.isWatch == true)
        do {
            _ = try SimulatorClient.decodeDevices(Data("invalid".utf8))
            preconditionFailure("Malformed device lists must fail.")
        } catch SimulatorClient.ClientError.invalidDeviceList { }
        let first = try await client.screenshot(deviceID: "PHONE")
        let second = try await client.screenshot(deviceID: "PHONE")
        precondition(first != second, "Each request must capture a fresh frame.")
        do {
            _ = try await client.screenshot(deviceID: "ERROR")
            preconditionFailure("Command failures must propagate.")
        } catch SimulatorClient.ClientError.commandFailed(let message) {
            precondition(message.contains("synthetic failure"))
        }
        do {
            _ = try await client.screenshot(deviceID: "INVALID")
            preconditionFailure("Non-PNG output must fail.")
        } catch SimulatorClient.ClientError.invalidScreenshot { }
        
        let cancellation = Task { try await client.screenshot(deviceID: "SLOW") }
        try await Task.sleep(for: .milliseconds(50))
        let clock = ContinuousClock()
        let start = clock.now
        cancellation.cancel()
        do {
            _ = try await cancellation.value
            preconditionFailure("Cancelled captures must not publish a frame.")
        } catch is CancellationError { }
        precondition(start.duration(to: clock.now) < .seconds(1))
        
        let timedClient = SimulatorClient(
            executable: .init(fileURLWithPath: "/usr/bin/python3"),
            argumentPrefix: [fixture],
            timeout: .milliseconds(100)
        )
        do {
            _ = try await timedClient.screenshot(deviceID: "SLOW")
            preconditionFailure("Hung captures must time out.")
        } catch SimulatorClient.ClientError.timedOut { }
        
        let root = URL(fileURLWithPath: fixture).deletingLastPathComponent()
        let log = root.appendingPathComponent("status-commands.jsonl")
        var statusBar = SimulatorStatusBarConfiguration()
        statusBar.time = "10:08"
        statusBar.dataNetwork = .fifthGenerationUC
        statusBar.wifiMode = .failed
        statusBar.wifiBars = 0
        statusBar.cellularMode = .active
        statusBar.cellularBars = 2
        statusBar.operatorName = "中国移动 $(literal)"
        statusBar.batteryState = .charging
        statusBar.batteryLevel = 42
        let preferencesSuite = "ScreenshotHub.StatusBarValidation.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: preferencesSuite)!
        defer { preferences.removePersistentDomain(forName: preferencesSuite) }
        precondition(SimulatorStatusBarConfiguration.load(from: preferences) == .init())
        statusBar.save(to: preferences)
        let reopenedPreferences = UserDefaults(suiteName: preferencesSuite)!
        precondition(SimulatorStatusBarConfiguration.load(from: reopenedPreferences) == statusBar,
                     "Every status-bar field must survive recreation of the preferences store.")
        var draft = statusBar
        draft.time = ""
        draft.save(to: preferences)
        precondition(SimulatorStatusBarConfiguration.load(from: reopenedPreferences) == draft,
                     "Unapplied edits must also be restored.")
        preferences.set(Data("invalid".utf8), forKey: "simulatorStatusBarConfiguration")
        precondition(SimulatorStatusBarConfiguration.load(from: reopenedPreferences) == .init(),
                     "Unreadable saved settings must fall back to the default preset.")
        try await client.applyStatusBar(statusBar, deviceID: "PHONE")
        try await client.clearStatusBar(deviceID: "PHONE")
        let commands = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode([String].self, from: Data($0.utf8))
        }
        precondition(commands[0] == ["status_bar", "PHONE", "override", "--time", "10:08", "--dataNetwork", "5g-uc",
                                     "--wifiMode", "failed", "--wifiBars", "0", "--cellularMode", "active", "--cellularBars", "2",
                                     "--operatorName", "中国移动 $(literal)", "--batteryState", "charging", "--batteryLevel", "42"])
        precondition(commands[1] == ["status_bar", "PHONE", "clear"])
        let logBeforeInvalidValue = try Data(contentsOf: log)
        statusBar.batteryLevel = 101
        do {
            try await client.applyStatusBar(statusBar, deviceID: "PHONE")
            preconditionFailure("Invalid status-bar values must not reach the command runner.")
        } catch { }
        let logAfterInvalidValue = try Data(contentsOf: log)
        precondition(logAfterInvalidValue == logBeforeInvalidValue)
        statusBar = .init()
        try await client.applyStatusBar(statusBar, deviceID: "IPAD")
        for network in SimulatorStatusBarConfiguration.DataNetwork.allCases {
            statusBar.dataNetwork = network
            try await client.applyStatusBar(statusBar, deviceID: "PHONE")
        }
        do {
            try await client.clearStatusBar(deviceID: "ERROR")
            preconditionFailure("Status-bar command errors must be reported.")
        } catch SimulatorClient.ClientError.statusBarFailed { }
        do {
            try await timedClient.clearStatusBar(deviceID: "SLOW")
            preconditionFailure("Status-bar commands must respect the command timeout.")
        } catch SimulatorClient.ClientError.timedOut { }
        
        let touches = TestTouches()
        let feed = SimulatorFeed(client: client, frameSource: { TestFrames.open(deviceID: $0, directory: $1, touches: touches) })
        feed.selectedDeviceID = "OFF"
        await feed.refreshDevices(automaticallySelectsDevice: false)
        precondition(!feed.devices.isEmpty && feed.selectedDeviceID == nil,
                     "Restoring a stopped simulator must not select a different running device.")
        feed.selectedDeviceID = "PHONE"
        await feed.refreshDevices(automaticallySelectsDevice: false)
        precondition(feed.selectedDeviceID == "PHONE")
        feed.selectedDeviceID = nil
        await feed.refreshDevices()
        precondition(feed.selectedDevice != nil, "Interactive discovery should still select an available device.")
        feed.selectedDeviceID = "PHONE"
        let streaming = Task { await feed.stream(deviceID: "PHONE") }
        while feed.lastCapture == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(feed.devices.allSatisfy { !$0.isWatch })
        let watchTouches = TestTouches()
        let watchFeed = SimulatorFeed(client: client, isWatch: true,
                                      frameSource: { TestFrames.open(deviceID: $0, directory: $1, touches: watchTouches) })
        await watchFeed.refreshDevices()
        precondition(watchFeed.devices.map(\.id) == ["WATCH"] && watchFeed.selectedDeviceID == "WATCH")
        let watchStreaming = Task { await watchFeed.stream(deviceID: "WATCH") }
        while !watchFeed.hasCurrentFrame { try await Task.sleep(for: .milliseconds(10)) }
        precondition(watchFeed.inputSessionID != feed.inputSessionID)
        watchFeed.sendTouch(.init(point: .init(x: 0.3, y: 0.4), phase: .began, inputOrientation: 1),
                            sessionID: watchFeed.inputSessionID!)
        precondition(watchTouches.count == 1 && touches.count == 0,
                     "Phone and Watch streams must route input to independent sessions.")
        let watchSession = watchFeed.inputSessionID!
        watchFeed.sendCrown(isPressed: true, sessionID: watchSession)
        watchFeed.sendCrown(isPressed: false, sessionID: watchSession)
        watchFeed.sendCrown(isPressed: true, sessionID: feed.inputSessionID!)
        feed.sendCrown(isPressed: true, sessionID: feed.inputSessionID!)
        precondition(watchTouches.crownEvents == [true, false] && touches.crownEvents.isEmpty,
                     "Crown presses must reach only the selected Watch session.")
        watchFeed.rotateCrown(by: 12.5, sessionID: watchSession)
        watchFeed.rotateCrown(by: -3, sessionID: watchSession)
        watchFeed.rotateCrown(by: 10, sessionID: feed.inputSessionID!)
        feed.rotateCrown(by: 10, sessionID: feed.inputSessionID!)
        for delta in [0, Double.nan, .infinity, -.infinity] {
            watchFeed.rotateCrown(by: delta, sessionID: watchSession)
        }
        watchFeed.selectedDeviceID = nil
        watchFeed.rotateCrown(by: 10, sessionID: watchSession)
        watchFeed.selectedDeviceID = "WATCH"
        precondition(watchTouches.crownRotations == [12.5, -3] && touches.crownRotations.isEmpty,
                     "Crown rotation must preserve deltas and reject invalid or unselected sessions.")
        watchStreaming.cancel()
        await watchStreaming.value
        precondition(watchFeed.inputSessionID == nil)
        watchFeed.sendCrown(isPressed: true, sessionID: watchSession)
        watchFeed.rotateCrown(by: 10, sessionID: watchSession)
        precondition(watchTouches.crownRotations == [12.5, -3], "Stopped Watch sessions must reject rotation.")
        precondition(watchTouches.crownEvents == [true, false], "Stopped Watch sessions must reject crown input.")
        let sessionID = feed.inputSessionID!
        let touch = SimulatorTouchEvent(point: .init(x: 0.25, y: 0.75), phase: .began, inputOrientation: 1)
        feed.sendTouch(touch, sessionID: sessionID)
        precondition(touches.count == 1)
        feed.selectedDeviceID = "IPAD"
        feed.sendTouch(touch, sessionID: sessionID)
        precondition(touches.count == 1, "Input must not target a device that is no longer selected.")
        feed.selectedDeviceID = "PHONE"
        let metadataChanges = TestTouches()
        withObservationTracking {
            _ = feed.hasCurrentFrame
            _ = feed.frameSize
            _ = feed.imageSize
            _ = feed.inputOrientation
            _ = feed.captureError
        } onChange: {
            metadataChanges.record(touch)
        }
        let revision = feed.frameRevision
        try await Task.sleep(for: .milliseconds(650))
        precondition(feed.frameRevision != revision)
        precondition(metadataChanges.count == 0, "Live frames must not invalidate unchanged configuration-panel metadata.")
        streaming.cancel()
        await streaming.value
        precondition(feed.inputSessionID == nil)
        feed.sendTouch(touch, sessionID: sessionID)
        precondition(touches.count == 1, "A stopped input session must reject stale mouse events.")
        let previewRevision = feed.frameRevision
        let image = try await feed.captureForExport(deviceID: "PHONE")
        precondition(image.size == .init(width: 12, height: 24))
        precondition(feed.frameRevision == previewRevision, "Export must retain a stream frame without triggering a screenshot.")
        
        feed.selectedDeviceID = "IPAD"
        precondition(feed.currentFrame == nil, "A previous device's frame must not be shown for the next device.")
        let stale = Task { await feed.stream(deviceID: "IPAD") }
        feed.selectedDeviceID = "PHONE"
        try await Task.sleep(for: .milliseconds(80))
        stale.cancel()
        await stale.value
        precondition(feed.imageDeviceID != "IPAD", "Late frames from the old device must be discarded.")
        do {
            _ = try await feed.captureForExport(deviceID: "IPAD")
            preconditionFailure("Export cannot use another device's frame.")
        } catch is CancellationError { }
        
        feed.selectedDeviceID = "ERROR"
        await feed.stream(deviceID: "ERROR")
        precondition(feed.captureError != nil && feed.currentFrame == nil)
        let stopped = URL(fileURLWithPath: fixture).deletingLastPathComponent().appendingPathComponent("stop-devices")
        try Data().write(to: stopped)
        await feed.refreshDevices()
        precondition(feed.devices.isEmpty && feed.selectedDeviceID == nil)
        await watchFeed.refreshDevices(automaticallySelectsDevice: false)
        precondition(watchFeed.devices.isEmpty && watchFeed.selectedDeviceID == nil)
        precondition(feed.currentFrame == nil && feed.captureError == nil)
        print("Validated independent phone/Watch discovery, streams and input sessions, running-device filtering, CLI capture errors, streamed updates/export, stale-frame rejection, cancellation, timeouts, stale input-session rejection, quiet metadata updates, status-bar persistence/apply/clear/validation, and stream failure using a simulated simctl fixture.")
    }
}

nonisolated private enum TestFrames {
    static func open(deviceID: String, directory: String, touches: TestTouches) -> SimulatorFrameStream {
        let (frames, continuation) = AsyncThrowingStream<SimulatorVideoFrame, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        if deviceID == "ERROR" {
            continuation.finish(throwing: SimulatorClient.ClientError.invalidScreenshot)
            return .init(frames: frames, stop: {}, sendTouch: { _, completion in completion(nil) })
        }
        let task = Task.detached {
            var revision: UInt8 = 0
            while !Task.isCancelled {
                revision &+= 1
                let pixels = Data(repeating: revision, count: 12 * 24 * 4)
                let provider = CGDataProvider(data: pixels as CFData)!
                let image = CGImage(
                    width: 12, height: 24, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: .init(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
                )!
                continuation.yield(.init(image: image, inputOrientation: 1))
                do { try await Task.sleep(for: .milliseconds(30)) }
                catch { break }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return .init(frames: frames, stop: { task.cancel() }, sendTouch: { event, completion in
            touches.record(event)
            completion(nil)
        }, sendCrown: { isPressed, completion in
            touches.recordCrown(isPressed)
            completion(nil)
        }, rotateCrown: { delta, completion in
            touches.recordRotation(delta)
            completion(nil)
        })
    }
}

nonisolated private final class TestTouches: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SimulatorTouchEvent] = []
    private var crowns: [Bool] = []
    private var rotations: [Double] = []
    
    var crownRotations: [Double] { lock.withLock { rotations } }
    
    func recordRotation(_ delta: Double) {
        lock.withLock { rotations.append(delta) }
    }
    
    var crownEvents: [Bool] { lock.withLock { crowns } }
    
    func recordCrown(_ isPressed: Bool) {
        lock.withLock { crowns.append(isPressed) }
    }
    
    var count: Int { lock.withLock { events.count } }
    
    func record(_ event: SimulatorTouchEvent) {
        lock.withLock { events.append(event) }
    }
}
