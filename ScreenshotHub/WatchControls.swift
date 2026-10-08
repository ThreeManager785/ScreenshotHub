import AppKit
import SwiftUI
import UniformTypeIdentifiers
    
struct WatchControls: View {
    @Binding var configuration: WatchConfiguration
    @Binding var screenshotData: Data?
    @Binding var sourceName: String
    @Binding var source: ScreenshotSource
    var isDraft: Bool
    var feed: SimulatorFeed
    var onRetry: () -> Void
    
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Include Apple Watch", isOn: $configuration.isEnabled)
                if configuration.isEnabled {
                    Picker("Watch Frame", selection: $configuration.frameID) {
                        ForEach(configuration.availableFrames) { frame in
                            Text(frame.displayName).tag(frame.id)
                        }
                    }
                    if isDraft {
                        Picker("Watch Screenshot Source", selection: $source) {
                            Text("Image File").tag(ScreenshotSource.file)
                            Text("Device Hub").tag(ScreenshotSource.simulator)
                        }
                        .pickerStyle(.segmented)
                    }
                    if source == .file {
                        Button(screenshotData == nil ? "Choose Watch Screenshot…" : sourceName) { isImporting = true }
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if screenshotData != nil {
                            Button("Remove Watch Screenshot", role: .destructive) {
                                screenshotData = nil
                                sourceName = ""
                            }
                        }
                    } else {
                        HStack {
                            Text("Running Apple Watches").font(.subheadline)
                            Spacer()
                            Button { Task { await feed.refreshDevices() } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Refresh Watch List")
                        }
                        Picker("Apple Watch", selection: Binding(get: { feed.selectedDeviceID }, set: { feed.selectedDeviceID = $0 })) {
                            Text(feed.devices.isEmpty ? "No Running Apple Watches" : "Select an Apple Watch").tag(nil as String?)
                            ForEach(feed.devices) { device in
                                Text(device.label).tag(Optional(device.id))
                            }
                        }
                        .labelsHidden()
                        if let message = feed.listError ?? feed.captureError ?? feed.inputError {
                            Text(message).font(.caption).foregroundStyle(.red)
                            Button("Retry Connection", action: onRetry)
                        } else if feed.devices.isEmpty {
                            Text("Start an Apple Watch simulator in Device Hub.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Replace Displayed Time", isOn: $configuration.clock.isEnabled)
                    if configuration.clock.isEnabled {
                        TextField("Time", text: $configuration.clock.time)
                            .onChange(of: configuration.clock.time) { _, value in
                                if value.count > 8 { configuration.clock.time = String(value.prefix(8)) }
                            }

                    }
                    DisclosureGroup("Watch Layout") {
                        slider("Size", value: $configuration.scale, range: WatchConfiguration.scaleRange)
                        slider("Horizontal Position", value: $configuration.horizontalPosition, range: 0...1)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Apple Watch", systemImage: "applewatch").font(.headline)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            do { try importImage(result.get()) }
            catch { errorMessage = error.localizedDescription }
        }
        .alert("Unable to Import Watch Screenshot", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Slider(value: value, in: range)
        }
        .padding(.top, 6)
    }
    
    private func importImage(_ url: URL) throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        guard let image = NSImage(data: try Data(contentsOf: url)), image.size.width > 0, image.size.height > 0 else {
            throw SimulatorClient.ClientError.invalidScreenshot
        }
        screenshotData = try DeviceFrameImages.pngData(for: image)
        sourceName = url.lastPathComponent
    }
}
