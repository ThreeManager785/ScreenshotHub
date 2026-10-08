import AppKit
import SwiftUI

nonisolated struct SnapshotExportProgress: Sendable {
    var completedCount: Int
    var totalCount: Int
    var filename: String?
    
    var fractionCompleted: Double {
        totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }
}

nonisolated enum SnapshotImageExporter {
    static func filename(
        for snapshot: ScreenshotSnapshot,
        index: Int = 1,
        groupName: String? = nil,
        resolution: ScreenshotResolution? = nil,
        isWatchVariant: Bool = false
    ) -> String {
        let resolution = resolution ?? snapshot.configuration.resolution
        let category = snapshot.configuration.family == .iPhone
            ? PhoneResolutionCategory.allCases.first { $0.resolutions.contains(resolution) }?.label : nil
        let variant = isWatchVariant ? "Apple Watch" : category ?? resolution.id
        let group = groupName.map(ScreenshotGroup.filenameComponent).flatMap { $0.isEmpty ? nil : $0 }
        return ([group].compactMap { $0 } + [String(index), snapshot.configuration.family.label, variant])
            .joined(separator: "-")
    }
    
    @MainActor
    static func filename(for snapshot: ScreenshotSnapshot, in document: ScreenshotHubDocument) -> String {
        filename(for: snapshot, index: document.index(of: snapshot),
                 groupName: document.groups.first { $0.id == snapshot.groupID }?.name)
    }
    
    static func imageData(
        for snapshot: ScreenshotSnapshot,
        frameImages: DeviceFrameImages?,
        watchFrameImages: DeviceFrameImages? = nil
    ) throws -> Data {
        try autoreleasepool {
            let bitmap = try render(snapshot, frameImages: frameImages, watchFrameImages: watchFrameImages)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw ScreenshotRenderer.RenderError.pngEncoding
            }
            return data
        }
    }
    
    @concurrent
    static func prepareImageData(
        for snapshot: ScreenshotSnapshot,
        frameImages: DeviceFrameImages?,
        watchFrameImages: DeviceFrameImages?
    ) async throws -> Data {
        try Task.checkCancellation()
        return try imageData(for: snapshot, frameImages: frameImages, watchFrameImages: watchFrameImages)
    }
    
    private static func render(
        _ snapshot: ScreenshotSnapshot,
        frameImages: DeviceFrameImages?,
        watchFrameImages: DeviceFrameImages?
    ) throws -> NSBitmapImageRep {
        guard let image = ScreenshotRenderer.image(for: snapshot.screenshotData) else { throw CocoaError(.fileReadCorruptFile) }
        return try ScreenshotRenderer.render(
            configuration: snapshot.configuration,
            screenshot: image,
            frameImages: frameImages,
            watchScreenshot: snapshot.watchScreenshotData.flatMap(ScreenshotRenderer.image(for:)),
            watchFrameImages: watchFrameImages
        )
    }
    
    static func watchImageData(for snapshot: ScreenshotSnapshot) throws -> Data {
        guard let data = snapshot.watchScreenshotData,
              let bitmap = NSBitmapImageRep(data: data), let source = bitmap.cgImage else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let sourceResolution = ScreenshotResolution(width: source.width, height: source.height)
        let resolution = WatchConfiguration.closestScreenshotResolution(to: sourceResolution)
        let clock = snapshot.configuration.watch.clock
        if sourceResolution == resolution, !clock.isEnabled { return data }
        let layout = clock.isEnabled ? WatchClockRenderer.analyze(source) : nil
        let patch = try layout.flatMap {
            try WatchClockRenderer.patch(configuration: clock, sourceSize: sourceResolution.size, source: source, layout: $0)
        }
        return try variantImageData(from: bitmap, resolution: resolution, backgroundColor: .black, clockPatch: patch)
    }
    
    @MainActor
    static func exportAll(_ document: ScreenshotHubDocument, to directory: URL) async throws -> URL {
        try await exportSnapshots(document.orderedSnapshots, frames: document.frames, groups: document.groups,
                                  orderedSnapshots: document.snapshots, to: directory)
    }
    
    @concurrent
    static func exportSnapshots(
        _ snapshots: [ScreenshotSnapshot],
        frames: [String: DeviceFrameImages],
        groups: [ScreenshotGroup] = [],
        orderedSnapshots: [ScreenshotSnapshot]? = nil,
        to directory: URL,
        onProgress: @MainActor @Sendable (SnapshotExportProgress) -> Void = { _ in }
    ) async throws -> URL {
        try Task.checkCancellation()
        let totalCount = snapshots.reduce(0) { $0 + 1 + $1.configuration.variantCount }
        var completedCount = 0
        await onProgress(.init(completedCount: 0, totalCount: totalCount))
        let manager = FileManager.default
        var folder = directory.appendingPathComponent("Screenshot Hub Export", isDirectory: true)
        var suffix = 2
        while manager.fileExists(atPath: folder.path) {
            folder = directory.appendingPathComponent("Screenshot Hub Export \(suffix)", isDirectory: true)
            suffix += 1
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            let allSnapshots = orderedSnapshots ?? snapshots
            for snapshot in snapshots {
                let index = (allSnapshots.filter { $0.groupID == snapshot.groupID }.firstIndex { $0.id == snapshot.id } ?? 0) + 1
                let groupName = groups.first { $0.id == snapshot.groupID }?.name
                try Task.checkCancellation()
                let bitmap = try autoreleasepool {
                    try render(snapshot, frameImages: frames[snapshot.configuration.frameID],
                               watchFrameImages: frames[snapshot.configuration.watch.frameID])
                }
                let primaryFilename = "\(filename(for: snapshot, index: index, groupName: groupName)).png"
                try autoreleasepool {
                    guard let data = bitmap.representation(using: .png, properties: [:]) else {
                        throw ScreenshotRenderer.RenderError.pngEncoding
                    }
                    try Task.checkCancellation()
                    try data.write(to: folder.appendingPathComponent(primaryFilename), options: .atomic)
                }
                completedCount += 1
                await onProgress(.init(completedCount: completedCount, totalCount: totalCount, filename: primaryFilename))
                if !snapshot.configuration.variantResolutions.isEmpty {
                    for resolution in snapshot.configuration.variantResolutions {
                        try Task.checkCancellation()
                        let filename = "\(filename(for: snapshot, index: index, groupName: groupName, resolution: resolution)).png"
                        try autoreleasepool {
                            let variant = try variantImageData(
                                from: bitmap,
                                resolution: resolution,
                                backgroundColor: NSColor(snapshot.configuration.backgroundColor)
                            )
                            try Task.checkCancellation()
                            try variant.write(to: folder.appendingPathComponent(filename), options: .atomic)
                        }
                        completedCount += 1
                        await onProgress(.init(completedCount: completedCount, totalCount: totalCount, filename: filename))
                    }
                }
                if snapshot.configuration.hasWatchVariant {
                    try Task.checkCancellation()
                    let name = "\(filename(for: snapshot, index: index, groupName: groupName, isWatchVariant: true)).png"
                    try autoreleasepool {
                        let data = try watchImageData(for: snapshot)
                        try Task.checkCancellation()
                        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                    }
                    completedCount += 1
                    await onProgress(.init(completedCount: completedCount, totalCount: totalCount, filename: name))
                }
            }
            try Task.checkCancellation()
            return folder
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }
    
    static func variantImageData(
        from source: NSBitmapImageRep,
        resolution: ScreenshotResolution,
        backgroundColor: NSColor,
        clockPatch: WatchClockPatch? = nil
    ) throws -> Data {
        guard let image = source.cgImage,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: resolution.width,
                pixelsHigh: resolution.height,
                bitsPerSample: 8,
                samplesPerPixel: 3,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 32
              ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ScreenshotRenderer.RenderError.bitmapCreation
        }
        let context = graphics.cgContext
        let size = resolution.size
        context.setFillColor(backgroundColor.cgColor)
        context.fill(.init(origin: .zero, size: size))
        let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let scaledSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.interpolationQuality = .high
        let scaledRect = CGRect(
            x: (size.width - scaledSize.width) / 2,
            y: (size.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
        context.draw(image, in: scaledRect)
        if let clockPatch {
            let rect = clockPatch.rect(in: scaledRect)
            // Clock detection uses a top-left origin; this bitmap context draws from the bottom.
            context.draw(clockPatch.image, in: .init(
                x: rect.minX,
                y: size.height - rect.maxY,
                width: rect.width,
                height: rect.height
            ))
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotRenderer.RenderError.pngEncoding
        }
        return data
    }
}
