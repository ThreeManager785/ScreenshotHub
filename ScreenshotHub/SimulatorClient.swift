import Foundation

nonisolated struct RunningSimulator: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let runtime: String
    let isIPad: Bool
    var isWatch = false
    
    var label: String { "\(name) · \(runtime)" }
}

actor SimulatorClient {
    nonisolated enum ClientError: LocalizedError {
        case commandFailed(String)
        case timedOut
        case invalidDeviceList
        case invalidScreenshot
        case statusBarFailed
        
        var errorDescription: String? {
            switch self {
            case .commandFailed:
                "Unable to read simulators. Complete Xcode setup, start a simulator in Device Hub, and try again."
            case .timedOut:
                "The simulator timed out. Make sure it is running and try again."
            case .invalidDeviceList:
                "Unable to read the running simulators. Refresh the list and try again."
            case .invalidScreenshot:
                "Unable to capture the simulator screen. Make sure the device is running."
            case .statusBarFailed:
                "Unable to update the simulator status bar. Make sure the device is running and supports status bar overrides."
            }
        }
    }
    
    private let executable: URL
    private let argumentPrefix: [String]
    private let timeout: Duration
    
    init(
        executable: URL = .init(fileURLWithPath: "/usr/bin/xcrun"),
        argumentPrefix: [String] = ["simctl"],
        timeout: Duration = .seconds(10)
    ) {
        self.executable = executable
        self.argumentPrefix = argumentPrefix
        self.timeout = timeout
    }
    
    func runningDevices() async throws -> [RunningSimulator] {
        let data = try await run(["list", "devices", "booted", "--json"])
        return try Self.decodeDevices(data)
    }
    
    func developerDirectory() async throws -> String {
        if let directory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory)
            return url.pathExtension == "app" ? url.appendingPathComponent("Contents/Developer").path : directory
        }
        let command = SimulatorCommand(
            executable: .init(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["--print-path"]
        )
        let data = try await command.run(timeout: timeout)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func screenshot(deviceID: String) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("screen.png")
        _ = try await run(["io", deviceID, "screenshot", "--type=png", "--mask=ignored", imageURL.path])
        try Task.checkCancellation()
        guard let data = try? Data(contentsOf: imageURL), data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw ClientError.invalidScreenshot
        }
        return data
    }
    
    func applyStatusBar(_ configuration: SimulatorStatusBarConfiguration, deviceID: String) async throws {
        let arguments = try configuration.arguments()
        try await runStatusBarCommand(["status_bar", deviceID, "override"] + arguments)
    }
    
    func clearStatusBar(deviceID: String) async throws {
        try await runStatusBarCommand(["status_bar", deviceID, "clear"])
    }
    
    private func runStatusBarCommand(_ arguments: [String]) async throws {
        do {
            _ = try await run(arguments)
        } catch ClientError.commandFailed {
            throw ClientError.statusBarFailed
        }
    }
    
    nonisolated static func decodeDevices(_ data: Data) throws -> [RunningSimulator] {
        guard let list = try? JSONDecoder().decode(DeviceList.self, from: data) else {
            throw ClientError.invalidDeviceList
        }
        return list.devices.flatMap { runtime, devices in
            let identifier = runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            let parts = identifier.split(separator: "-", maxSplits: 1)
            let runtimeName = parts.count == 2 ? "\(parts[0]) \(parts[1].replacingOccurrences(of: "-", with: "."))" : identifier
            return devices.compactMap { device -> RunningSimulator? in
                guard device.state == "Booted", device.isAvailable != false else { return nil }
                let type = device.deviceTypeIdentifier ?? device.name
                let isIPad = type.contains("iPad")
                let isWatch = type.contains("Watch") || runtime.contains("watchOS")
                guard isIPad || type.contains("iPhone") || isWatch else { return nil }
                return .init(id: device.udid, name: device.name, runtime: runtimeName, isIPad: isIPad, isWatch: isWatch)
            }
        }
        .sorted { ($0.name, $0.runtime, $0.id) < ($1.name, $1.runtime, $1.id) }
    }
    
    private func run(_ arguments: [String]) async throws -> Data {
        let command = SimulatorCommand(executable: executable, arguments: argumentPrefix + arguments)
        return try await command.run(timeout: timeout)
    }
    
    nonisolated private struct DeviceList: Decodable {
        let devices: [String: [Device]]
        
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
            let isAvailable: Bool?
            let deviceTypeIdentifier: String?
        }
    }
}

// The lock serializes cancellation with launch; output is configured before either can run.
nonisolated private final class SimulatorCommand: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    
    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
    }
    
    private var isCancelled = false
    private var didTimeOut = false
    
    func run(timeout: Duration) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? errors.close()
        }
        process.standardOutput = output
        process.standardError = errors
        let timer = Task {
            do {
                try await Task.sleep(for: timeout)
                cancel(timedOut: true)
            } catch { }
        }
        defer { timer.cancel() }
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                lock.withLock {
                    guard !isCancelled else {
                        continuation.resume(throwing: didTimeOut ? SimulatorClient.ClientError.timedOut : CancellationError())
                        return
                    }
                    process.terminationHandler = { process in
                        continuation.resume(returning: process.terminationStatus)
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            self.cancel(timedOut: false)
        }
        if lock.withLock({ didTimeOut }) { throw SimulatorClient.ClientError.timedOut }
        try Task.checkCancellation()
        guard status == 0 else {
            let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            throw SimulatorClient.ClientError.commandFailed(message)
        }
        return try Data(contentsOf: outputURL)
    }
    
    private func cancel(timedOut: Bool) {
        lock.withLock {
            isCancelled = true
            didTimeOut = didTimeOut || timedOut
            if process.isRunning { process.terminate() }
        }
    }
}
