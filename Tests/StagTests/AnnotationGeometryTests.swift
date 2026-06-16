import XCTest
import SwiftUI
@testable import Stag

/// Hit-testing and translation geometry for editor annotations. `Annotation.contains`
/// and `offsetBy` are pure functions over `CGPoint`/`CGSize`, so they can be exercised
/// without any canvas or rendering. The private `distancePointToSegment` and the
/// `CGPoint + CGSize` operator are covered transitively through these.
final class AnnotationGeometryTests: XCTestCase {

    private func make(_ type: AnnotationType, lineWidth: CGFloat = 3) -> Annotation {
        Annotation(type: type, color: .red, fillColor: nil, lineWidth: lineWidth)
    }

    // MARK: - CGRect.expand

    func testRectExpandGrowsSymmetrically() {
        let r = CGRect(x: 10, y: 10, width: 20, height: 20).expand(5)
        XCTAssertEqual(r, CGRect(x: 5, y: 5, width: 30, height: 30))
    }

    // MARK: - contains: line/segment based

    func testArrowHitOnLineAndMiss() {
        let a = make(.arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0)))
        XCTAssertTrue(a.contains(point: CGPoint(x: 50, y: 0)))   // on the segment
        XCTAssertTrue(a.contains(point: CGPoint(x: 50, y: 10)))  // within hitInset + lineWidth
        XCTAssertFalse(a.contains(point: CGPoint(x: 50, y: 80))) // far away
    }

    func testLineHitTestRespectsEndpoints() {
        let a = make(.line(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 100)))
        XCTAssertTrue(a.contains(point: CGPoint(x: 0, y: 100)))
        XCTAssertFalse(a.contains(point: CGPoint(x: 0, y: 200))) // beyond endpoint, clamped distance large
    }

    func testCurvedArrowHitsAlongEitherControlSegment() {
        let a = make(.curvedArrow(start: CGPoint(x: 0, y: 0),
                                  control: CGPoint(x: 50, y: 50),
                                  end: CGPoint(x: 100, y: 0)))
        XCTAssertTrue(a.contains(point: CGPoint(x: 25, y: 25)))   // near start→control
        XCTAssertTrue(a.contains(point: CGPoint(x: 75, y: 25)))   // near control→end
        XCTAssertFalse(a.contains(point: CGPoint(x: 50, y: 200)))
    }

    func testRulerUsesSegmentDistance() {
        let a = make(.ruler(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100)))
        XCTAssertTrue(a.contains(point: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(a.contains(point: CGPoint(x: 0, y: 100)))
    }

    // MARK: - contains: rect-based shapes

    func testRectContainsWithInsetAndStandardization() {
        // Negative size — must be standardized before hit-testing.
        let a = make(.rect(origin: CGPoint(x: 100, y: 100), size: CGSize(width: -50, height: -50)))
        XCTAssertTrue(a.contains(point: CGPoint(x: 75, y: 75)))   // inside the standardized rect
        XCTAssertTrue(a.contains(point: CGPoint(x: 45, y: 45)))   // within the 12pt inset
        XCTAssertFalse(a.contains(point: CGPoint(x: 200, y: 200)))
    }

    func testCircleBlurHighlightMosaicSpotlightAreRectHitTested() {
        let kinds: [AnnotationType] = [
            .circle(origin: .zero, size: CGSize(width: 40, height: 40)),
            .blur(origin: .zero, size: CGSize(width: 40, height: 40)),
            .highlight(origin: .zero, size: CGSize(width: 40, height: 40)),
            .smartHighlight(origin: .zero, size: CGSize(width: 40, height: 40)),
            .mosaic(origin: .zero, size: CGSize(width: 40, height: 40)),
            .spotlight(origin: .zero, size: CGSize(width: 40, height: 40)),
        ]
        for k in kinds {
            let a = make(k)
            XCTAssertTrue(a.contains(point: CGPoint(x: 20, y: 20)), "\(k) should contain center")
            XCTAssertFalse(a.contains(point: CGPoint(x: 500, y: 500)), "\(k) should not contain far point")
        }
    }

    func testTextHitBoxScalesWithLength() {
        let a = make(.text(position: .zero, text: "Hello", fontSize: 20, style: .regular))
        // width ≈ 5 * 20 * 0.6 = 60, height ≈ 28, plus 12 inset
        XCTAssertTrue(a.contains(point: CGPoint(x: 30, y: 14)))
        XCTAssertFalse(a.contains(point: CGPoint(x: 200, y: 14)))
    }

    func testEmojiHitBox() {
        let a = make(.emoji(position: .zero, text: "🔥", fontSize: 30))
        XCTAssertTrue(a.contains(point: CGPoint(x: 10, y: 10)))
        XCTAssertFalse(a.contains(point: CGPoint(x: 300, y: 300)))
    }

    // MARK: - contains: point/radius based

    func testFreehandHitsNearAnyVertex() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)]
        let a = make(.freehand(points: pts))
        XCTAssertTrue(a.contains(point: CGPoint(x: 50, y: 52)))
        XCTAssertFalse(a.contains(point: CGPoint(x: 200, y: 200)))
    }

    func testStepNumberHitsWithinFixedRadius() {
        let a = make(.stepNumber(center: CGPoint(x: 100, y: 100), number: 1))
        XCTAssertTrue(a.contains(point: CGPoint(x: 110, y: 100)))  // within 24
        XCTAssertFalse(a.contains(point: CGPoint(x: 140, y: 100))) // beyond 24
    }

    func testMagnifierCalloutHitsLensLinkAndBubble() {
        let a = make(.magnifierCallout(center: CGPoint(x: 0, y: 0),
                                       calloutPoint: CGPoint(x: 200, y: 0),
                                       radius: 30, scale: 2))
        XCTAssertTrue(a.contains(point: CGPoint(x: 0, y: 0)))      // lens
        XCTAssertTrue(a.contains(point: CGPoint(x: 100, y: 0)))    // connector line
        XCTAssertTrue(a.contains(point: CGPoint(x: 200, y: 0)))    // bubble
        XCTAssertFalse(a.contains(point: CGPoint(x: 0, y: 500)))
    }

    func testFreehandEraseNeverContains() {
        let a = make(.freehandErase)
        XCTAssertFalse(a.contains(point: .zero))
        XCTAssertFalse(a.contains(point: CGPoint(x: 1, y: 1)))
    }

    // MARK: - offsetBy

    func testOffsetByPreservesIdentityAndTranslatesArrow() {
        let original = make(.arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10)))
        let moved = original.offsetBy(CGSize(width: 5, height: 7))
        XCTAssertEqual(original.id, moved.id, "offsetBy must preserve identity")
        if case let .arrow(start, end) = moved.type {
            XCTAssertEqual(start, CGPoint(x: 5, y: 7))
            XCTAssertEqual(end, CGPoint(x: 15, y: 17))
        } else {
            XCTFail("type changed")
        }
    }

    func testOffsetByTranslatesRectOriginNotSize() {
        let original = make(.rect(origin: CGPoint(x: 10, y: 10), size: CGSize(width: 40, height: 30)))
        let moved = original.offsetBy(CGSize(width: -5, height: 5))
        if case let .rect(origin, size) = moved.type {
            XCTAssertEqual(origin, CGPoint(x: 5, y: 15))
            XCTAssertEqual(size, CGSize(width: 40, height: 30))
        } else {
            XCTFail("type changed")
        }
    }

    func testOffsetByTranslatesFreehandPoints() {
        let original = make(.freehand(points: [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)]))
        let moved = original.offsetBy(CGSize(width: 10, height: 10))
        if case let .freehand(points) = moved.type {
            XCTAssertEqual(points, [CGPoint(x: 11, y: 11), CGPoint(x: 12, y: 12)])
        } else {
            XCTFail("type changed")
        }
    }

    func testOffsetByOnFreehandEraseIsNoOpType() {
        let original = make(.freehandErase)
        let moved = original.offsetBy(CGSize(width: 10, height: 10))
        if case .freehandErase = moved.type { /* ok */ } else { XCTFail("type changed") }
    }

    // MARK: - CanvasState equality (compares annotation identity only)

    func testCanvasStateEqualityIgnoresToolAndRotation() {
        let ann = make(.rect(origin: .zero, size: CGSize(width: 1, height: 1)))
        let a = CanvasState(annotations: [ann], currentTool: .rect, selectedAnnotationId: nil, rotation: 0)
        let b = CanvasState(annotations: [ann], currentTool: .arrow, selectedAnnotationId: ann.id, rotation: 90)
        XCTAssertEqual(a, b, "equality is by annotation id list only")

        let other = make(.rect(origin: .zero, size: CGSize(width: 1, height: 1)))
        let c = CanvasState(annotations: [other], currentTool: .rect, selectedAnnotationId: nil, rotation: 0)
        XCTAssertNotEqual(a, c)
    }
}
