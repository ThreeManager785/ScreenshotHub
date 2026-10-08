import Foundation

nonisolated struct SimulatorStatusBarConfiguration: Codable, Equatable, Sendable {
    private static let persistenceKey = "simulatorStatusBarConfiguration"
    
    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: persistenceKey),
              let configuration = try? JSONDecoder().decode(Self.self, from: data) else {
            return .init()
        }
        return configuration
    }
    
    var time = "9:41"
    var dataNetwork = DataNetwork.wifi
    var wifiMode = WiFiMode.active
    var wifiBars = 3
    var cellularMode = CellularMode.active
    var cellularBars = 4
    var operatorName = ""
    var batteryState = BatteryState.charged
    var batteryLevel = 100
    
    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.persistenceKey)
    }
    
    func arguments() throws -> [String] {
        guard !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyTime
        }
        guard (0...3).contains(wifiBars), (0...4).contains(cellularBars), (0...100).contains(batteryLevel) else {
            throw ValidationError.invalidLevel
        }
        return [
            "--time", time,
            "--dataNetwork", dataNetwork.rawValue,
            "--wifiMode", wifiMode.rawValue,
            "--wifiBars", String(wifiBars),
            "--cellularMode", cellularMode.rawValue,
            "--cellularBars", String(cellularBars),
            "--operatorName", operatorName,
            "--batteryState", batteryState.rawValue,
            "--batteryLevel", String(batteryLevel)
        ]
    }
    
    enum DataNetwork: String, Codable, CaseIterable, Identifiable, Sendable {
        case hide
        case wifi
        case thirdGeneration = "3g"
        case fourthGeneration = "4g"
        case lte
        case lteAdvanced = "lte-a"
        case ltePlus = "lte+"
        case fifthGeneration = "5g"
        case fifthGenerationPlus = "5g+"
        case fifthGenerationUWB = "5g-uwb"
        case fifthGenerationUC = "5g-uc"
        
        var id: Self { self }
        var label: String {
            switch self {
            case .hide: "Hidden"
            case .wifi: "Wi-Fi"
            case .thirdGeneration: "3G"
            case .fourthGeneration: "4G"
            case .lte: "LTE"
            case .lteAdvanced: "LTE-A"
            case .ltePlus: "LTE+"
            case .fifthGeneration: "5G"
            case .fifthGenerationPlus: "5G+"
            case .fifthGenerationUWB: "5G UWB"
            case .fifthGenerationUC: "5G UC"
            }
        }
    }
    
    enum WiFiMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case searching
        case failed
        case active
        
        var id: Self { self }
        var label: String {
            switch self {
            case .searching: "Searching"
            case .failed: "Unavailable"
            case .active: "Connected"
            }
        }
    }
    
    enum CellularMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case notSupported
        case searching
        case failed
        case active
        
        var id: Self { self }
        var label: String {
            switch self {
            case .notSupported: "Not Supported"
            case .searching: "Searching"
            case .failed: "No Service"
            case .active: "Connected"
            }
        }
    }
    
    enum BatteryState: String, Codable, CaseIterable, Identifiable, Sendable {
        case charging
        case charged
        case discharging
        
        var id: Self { self }
        var label: String {
            switch self {
            case .charging: "Charging"
            case .charged: "Fully Charged"
            case .discharging: "On Battery"
            }
        }
    }
    
    private enum ValidationError: LocalizedError {
        case emptyTime
        case invalidLevel
        
        var errorDescription: String? {
            switch self {
            case .emptyTime: "Enter a status bar time, such as 9:41."
            case .invalidLevel: "Wi-Fi signal must be 0–3 bars, cellular signal 0–4 bars, and battery level 0–100%."
            }
        }
    }
}
