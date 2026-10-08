import Foundation
    
nonisolated struct WatchConfiguration: Codable, Equatable, Sendable {
    static let scaleRange = 0.30...0.65
    static let screenshotResolutions: [ScreenshotResolution] = [
        .init(width: 422, height: 514), .init(width: 410, height: 502),
        .init(width: 416, height: 496), .init(width: 396, height: 484),
        .init(width: 368, height: 448), .init(width: 312, height: 390)
    ]
    
    static func closestScreenshotResolution(to source: ScreenshotResolution) -> ScreenshotResolution {
        screenshotResolutions.min {
            let left = pow(Double($0.width - source.width), 2) + pow(Double($0.height - source.height), 2)
            let right = pow(Double($1.width - source.width), 2) + pow(Double($1.height - source.height), 2)
            return left < right
        }!
    }
    
    var isEnabled = false
    var frameID = DeviceFrame.all.first { $0.family == .appleWatch && $0.name.contains("46mm - Aluminum Jet Black + Sport Band") }?.id ?? ""
    var storedFrame: DeviceFrame?
    var scale = 0.36
    var horizontalPosition = 0.5
    var clock = WatchClockConfiguration()
    
    var availableFrames: [DeviceFrame] {
        var frames = DeviceFrame.all.filter { $0.family == .appleWatch }
        if let storedFrame {
            if let index = frames.firstIndex(where: { $0.id == storedFrame.id }) {
                frames[index] = storedFrame
            } else {
                frames.append(storedFrame)
            }
        }
        return frames
    }
    var frame: DeviceFrame? { availableFrames.first { $0.id == frameID } }
    var needsEmbeddedFrame: Bool { isEnabled || storedFrame != nil }
    var isValid: Bool {
        guard Self.scaleRange.contains(scale), (0...1).contains(horizontalPosition), clock.isValid else { return false }
        guard needsEmbeddedFrame else { return true }
        guard let frame, frame.family == .appleWatch,
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
              frame.screenX.isFinite, frame.screenY.isFinite, frame.screenX >= 0, frame.screenY >= 0,
              frame.screenWidth.isFinite, frame.screenHeight.isFinite,
              frame.screenWidth > 0, frame.screenHeight > 0,
              frame.screenX + frame.screenWidth <= frame.width,
              frame.screenY + frame.screenHeight <= frame.height else { return false }
        return true
    }
}
    
extension WatchConfiguration {
    nonisolated private enum CodingKeys: String, CodingKey {
        case isEnabled, frameID, storedFrame, scale, horizontalPosition, clock, offsetX
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        frameID = try values.decode(String.self, forKey: .frameID)
        storedFrame = try values.decodeIfPresent(DeviceFrame.self, forKey: .storedFrame)
        let storedScale = try values.decode(Double.self, forKey: .scale)
        scale = (0.22...Self.scaleRange.upperBound).contains(storedScale)
            ? max(Self.scaleRange.lowerBound, storedScale) : storedScale
        horizontalPosition = try values.decodeIfPresent(Double.self, forKey: .horizontalPosition)
            ?? min(1, max(0, 0.5 + (values.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0) / 0.3))
        clock = try values.decode(WatchClockConfiguration.self, forKey: .clock)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(frameID, forKey: .frameID)
        try values.encodeIfPresent(storedFrame, forKey: .storedFrame)
        try values.encode(scale, forKey: .scale)
        try values.encode(horizontalPosition, forKey: .horizontalPosition)
        try values.encode(clock, forKey: .clock)
    }
}
    
nonisolated struct WatchClockConfiguration: Codable, Equatable, Sendable {
    var isEnabled = false
    var time = "9:41"
    
    var isValid: Bool { time.count <= 8 }
}
