import XCTest
import CoreGraphics
@testable import Stag

/// Time-based fade/ripple math for the recording mouse-click visualizer.
/// Uses generous accuracy because `age` reads the wall clock.
final class MouseClickEventTests: XCTestCase {

    private func event(ageSeconds: TimeInterval, duration: TimeInterval = 0.8) -> MouseClickEvent {
        MouseClickEvent(position: .zero, button: 0,
                        timestamp: Date(timeIntervalSinceNow: -ageSeconds),
                        duration: duration)
    }

    func testFreshClickIsFullyOpaqueAndSmall() {
        let e = event(ageSeconds: 0)
        XCTAssertEqual(e.alpha, 1.0, accuracy: 0.05)
        XCTAssertEqual(e.radius, 10, accuracy: 1.0)
        XCTAssertFalse(e.isExpired)
    }

    func testMidLifeAlphaAndRadius() {
        let e = event(ageSeconds: 0.4, duration: 0.8) // ~50% through
        XCTAssertEqual(e.alpha, 0.5, accuracy: 0.08)
        XCTAssertEqual(e.radius, 25, accuracy: 3.0)    // 10 + 0.5 * 30
        XCTAssertFalse(e.isExpired)
    }

    func testExpiredClickClampsAlphaToZero() {
        let e = event(ageSeconds: 1.2, duration: 0.8)
        XCTAssertTrue(e.isExpired)
        XCTAssertEqual(e.alpha, 0.0, accuracy: 0.001) // clamped, never negative
        XCTAssertGreaterThan(e.radius, 10)            // keeps expanding past duration
    }

    func testEquatable() {
        let ts = Date()
        let a = MouseClickEvent(position: CGPoint(x: 1, y: 2), button: 0, timestamp: ts, duration: 0.8)
        let b = MouseClickEvent(position: CGPoint(x: 1, y: 2), button: 0, timestamp: ts, duration: 0.8)
        XCTAssertEqual(a, b)
        let c = MouseClickEvent(position: CGPoint(x: 9, y: 9), button: 1, timestamp: ts, duration: 0.8)
        XCTAssertNotEqual(a, c)
    }
}
