import SwiftUI

struct SimulatorStatusBarControls: View {
    let feed: SimulatorFeed
    
    @State private var configuration = SimulatorStatusBarConfiguration.load()
    @State private var isUpdating = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Time") {
                    TextField("9:41", text: $configuration.time)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                Picker("Data Network", selection: $configuration.dataNetwork) {
                    ForEach(SimulatorStatusBarConfiguration.DataNetwork.allCases) { network in
                        Text(network.label).tag(network)
                    }
                }
                Picker("Wi-Fi Status", selection: $configuration.wifiMode) {
                    ForEach(SimulatorStatusBarConfiguration.WiFiMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Stepper("Wi-Fi Signal: \(configuration.wifiBars) of 3", value: $configuration.wifiBars, in: 0...3)
                Picker("Cellular Status", selection: $configuration.cellularMode) {
                    ForEach(SimulatorStatusBarConfiguration.CellularMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Stepper("Cellular Signal: \(configuration.cellularBars) of 4", value: $configuration.cellularBars, in: 0...4)
                LabeledContent("Carrier") {
                    TextField("Leave blank to hide", text: $configuration.operatorName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                Picker("Battery Status", selection: $configuration.batteryState) {
                    ForEach(SimulatorStatusBarConfiguration.BatteryState.allCases) { state in
                        Text(state.label).tag(state)
                    }
                }
                Stepper("Battery Level: \(configuration.batteryLevel)%", value: $configuration.batteryLevel, in: 0...100)
                VStack(alignment: .leading, spacing: 8) {
                    Button(isUpdating ? "Updating…" : "Apply to Simulator") { updateStatusBar(clearing: false) }
                    Button("Reset Status Bar") { updateStatusBar(clearing: true) }
                }
                Text("Changes apply to the selected simulator and appear in the preview and exported screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .disabled(feed.selectedDeviceID == nil || isUpdating)
        } label: {
            Label("Simulator Status Bar", systemImage: "cellularbars")
                .font(.headline)
        }
        .onChange(of: configuration) { _, configuration in
            configuration.save()
        }
        .onChange(of: feed.selectedDeviceID) { _, _ in
            resultMessage = nil
            errorMessage = nil
        }
    }
    
    private func updateStatusBar(clearing: Bool) {
        guard let deviceID = feed.selectedDeviceID, !isUpdating else { return }
        let configuration = configuration
        isUpdating = true
        resultMessage = nil
        errorMessage = nil
        Task {
            defer { isUpdating = false }
            do {
                if clearing {
                    try await feed.clearStatusBar(deviceID: deviceID)
                } else {
                    try await feed.applyStatusBar(configuration, deviceID: deviceID)
                }
                guard feed.selectedDeviceID == deviceID else { return }
                resultMessage = clearing ? "Status bar reset." : "Status bar overrides applied."
            } catch is CancellationError {
            } catch {
                guard feed.selectedDeviceID == deviceID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
