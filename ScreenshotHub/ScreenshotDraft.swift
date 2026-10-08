import Foundation
    
enum ScreenshotSource: String, Codable {
    case file
    case simulator
}
    
struct ScreenshotDraft: Equatable {
    var configuration = ScreenshotConfiguration()
    var screenshotData: Data?
    var sourceName = ""
    var source = ScreenshotSource.file
    var simulatorID: String?
    var watchScreenshotData: Data?
    var watchSourceName = ""
    var watchSource = ScreenshotSource.file
    var watchSimulatorID: String?
    
    mutating func restoreWatchSource(runningSimulatorIDs: [String]) {
        guard watchSource == .simulator else { return }
        guard let watchSimulatorID, runningSimulatorIDs.contains(watchSimulatorID) else {
            watchSource = .file
            watchSimulatorID = nil
            return
        }
    }
    
    mutating func restoreSource(runningSimulatorIDs: [String]) {
        guard source == .simulator else { return }
        guard let simulatorID, runningSimulatorIDs.contains(simulatorID) else {
            source = .file
            simulatorID = nil
            return
        }
    }
}
