import SwiftUI
import Foundation
import CoreGraphics

@main
struct ValidatePreviewInteraction {
    static func main() {
        let ideal = CGSize(width: 360, height: 480)
        precondition(ProposedViewSize.unspecified.viewportSize(idealSize: ideal) == ideal)
        precondition(ProposedViewSize.zero.viewportSize(idealSize: ideal) == .zero)
        precondition(ProposedViewSize.infinity.viewportSize(idealSize: ideal) == ideal)
        precondition(ProposedViewSize(width: .nan, height: -1).viewportSize(idealSize: ideal) == .init(width: 360, height: 0))
        for width in stride(from: 0, through: 1800, by: 17) {
            let bounds = ProposedViewSize(width: CGFloat(width), height: 650).viewportSize(idealSize: ideal)
            precondition(bounds == .init(width: width, height: 650))
            let geometry = PreviewScreenGeometry(
                bounds: .init(origin: .zero, size: bounds),
                canvasSize: .init(width: 1284, height: 2778),
                screenRect: .init(x: 150, y: 500, width: 980, height: 2000),
                sourceSize: .init(width: 1170, height: 2532)
            )
            precondition(geometry.canvasRect.width.isFinite && geometry.canvasRect.height.isFinite)
            precondition(geometry.canvasRect.width <= bounds.width && geometry.canvasRect.height <= bounds.height)
        }
        let portrait = PreviewScreenGeometry(
            bounds: .init(x: 0, y: 0, width: 800, height: 600),
            canvasSize: .init(width: 1000, height: 2000),
            screenRect: .init(x: 100, y: 500, width: 800, height: 1200),
            sourceSize: .init(width: 1000, height: 1000)
        )
        check(portrait.canvasRect.origin, .init(x: 250, y: 0))
        check(portrait.normalizedPoint(for: .init(x: 400, y: 330))!, .init(x: 0.5, y: 0.5))
        check(portrait.normalizedPoint(for: .init(x: 280, y: 330))!, .init(x: 1.0 / 6, y: 0.5))
        check(portrait.normalizedPoint(for: .init(x: 520, y: 330), clamping: true)!, .init(x: 5.0 / 6, y: 0.5))
        precondition(portrait.normalizedPoint(for: .init(x: 100, y: 200)) == nil)
        precondition(portrait.normalizedPoint(for: .init(x: 400, y: 60)) == nil)
        check(portrait.normalizedPoint(for: .init(x: 10000, y: -10000), clamping: true)!, .init(x: 5.0 / 6, y: 0))
        let landscape = PreviewScreenGeometry(
            bounds: .init(x: 23, y: 17, width: 800, height: 600),
            canvasSize: .init(width: 2000, height: 1000),
            screenRect: .init(x: 400, y: 300, width: 1200, height: 600),
            sourceSize: .init(width: 1000, height: 2000)
        )
        check(landscape.canvasRect.origin, .init(x: 23, y: 117))
        check(landscape.normalizedPoint(for: .init(x: 423, y: 237))!, .init(x: 0.5, y: 0.375))
        check(landscape.normalizedPoint(for: .init(x: 423, y: 477), clamping: true)!, .init(x: 0.5, y: 0.625))
        let zero = PreviewScreenGeometry(bounds: .zero, canvasSize: .zero, screenRect: .zero, sourceSize: .zero)
        precondition(zero.normalizedPoint(for: .zero, clamping: true) == nil)
        precondition(portrait.normalizedPoint(for: .init(x: CGFloat.nan, y: 100), clamping: true) == nil)
        print("Validated stable native viewport sizing for zero, unspecified, unbounded, and changing window proposals, preview scaling, letterboxing, aspect-fill cropping, landscape coordinates, outside-screen rejection, and drag clamping.")
    }
    
    private static func check(_ actual: CGPoint, _ expected: CGPoint) {
        precondition(abs(actual.x - expected.x) < 1e-10 && abs(actual.y - expected.y) < 1e-10)
    }
}
