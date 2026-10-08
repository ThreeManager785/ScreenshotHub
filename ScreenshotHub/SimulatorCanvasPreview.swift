import AppKit
import SwiftUI

struct SimulatorCanvasPreview: View {
    var feed: SimulatorFeed
    var overlay: CGImage
    var screenRect: CGRect
    var canvasSize: CGSize
    var backgroundColor: NSColor
    var watchFeed: SimulatorFeed?
    var watchOverlay: CGImage?
    var watchScreenRect: CGRect = .zero
    var watchCrownRect: CGRect = .zero
    var watchScreenMask: CGImage?
    var watchClock: CGImage?
    var watchClockRect: CGRect = .zero
    var watchClockConfiguration: WatchClockConfiguration?
    var streamsPhone = true
    var streamsWatch = false
    
    var body: some View {
        LiveScreenshotPreview(
            frame: streamsPhone ? feed.currentFrame : nil,
            overlay: overlay,
            screenRect: screenRect,
            canvasSize: canvasSize,
            backgroundColor: backgroundColor,
            controlSessionID: streamsPhone ? feed.inputSessionID : nil,
            inputOrientation: feed.inputOrientation,
            onTouch: { [sessionID = feed.inputSessionID] event in
                guard let sessionID else { return }
                feed.sendTouch(event, sessionID: sessionID)
            },
            watch: watchOverlay.map { overlay in
                .init(frame: streamsWatch ? watchFeed?.currentFrame : nil,
                      overlay: overlay, screenRect: watchScreenRect, screenMask: watchScreenMask,
                      clock: watchClock, clockRect: watchClockRect,
                      controlSessionID: streamsWatch ? watchFeed?.inputSessionID : nil,
                      inputOrientation: watchFeed?.inputOrientation ?? 1,
                      onTouch: { [sessionID = watchFeed?.inputSessionID] event in
                          guard let sessionID else { return }
                          watchFeed?.sendTouch(event, sessionID: sessionID)
                      }, clockConfiguration: watchClockConfiguration,
                      crownRect: watchCrownRect,
                      onCrown: { [sessionID = watchFeed?.inputSessionID] isPressed in
                          guard let sessionID else { return }
                          watchFeed?.sendCrown(isPressed: isPressed, sessionID: sessionID)
                      },
                      onCrownRotation: { [sessionID = watchFeed?.inputSessionID] delta in
                          guard let sessionID else { return }
                          watchFeed?.rotateCrown(by: delta, sessionID: sessionID)
                      })
            }
        )
    }
}
