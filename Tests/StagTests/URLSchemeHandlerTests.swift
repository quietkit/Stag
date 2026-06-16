import XCTest
@testable import Stag

/// Parsing of `stag://` deep-link URLs into `URLCommand`s.
final class URLSchemeHandlerTests: XCTestCase {

    private func parse(_ s: String) -> URLCommand? {
        guard let url = URL(string: s) else { return nil }
        return URLSchemeHandler.parse(url)
    }

    func testRejectsForeignScheme() {
        XCTAssertNil(parse("https://capture"))
        XCTAssertNil(parse("otherapp://capture"))
    }

    func testCaptureWithoutTypeDefaultsToNil() {
        guard case let .capture(type, delay)? = parse("stag://capture") else {
            return XCTFail("expected .capture")
        }
        XCTAssertNil(type)
        XCTAssertEqual(delay, 0)
    }

    func testCaptureAreaHostDefaultsToAreaType() {
        guard case let .capture(type, _)? = parse("stag://capture-area") else {
            return XCTFail("expected .capture")
        }
        XCTAssertEqual(type, .area)
    }

    func testCaptureWithExplicitTypeAndDelay() {
        guard case let .capture(type, delay)? = parse("stag://capture?type=window&delay=2.5") else {
            return XCTFail("expected .capture")
        }
        XCTAssertEqual(type, .window)
        XCTAssertEqual(delay, 2.5, accuracy: 0.0001)
    }

    func testCaptureTypeIsCaseInsensitive() {
        guard case let .capture(type, _)? = parse("stag://capture?type=FULLSCREEN") else {
            return XCTFail("expected .capture")
        }
        XCTAssertEqual(type, .fullscreen)
    }

    func testCaptureWithUnknownTypeYieldsNilType() {
        guard case let .capture(type, _)? = parse("stag://capture?type=banana") else {
            return XCTFail("expected .capture")
        }
        XCTAssertNil(type)
    }

    func testInvalidDelayFallsBackToZero() {
        guard case let .capture(_, delay)? = parse("stag://capture?delay=notanumber") else {
            return XCTFail("expected .capture")
        }
        XCTAssertEqual(delay, 0)
    }

    func testPreferencesAndSettingsHosts() {
        if case .preferences? = parse("stag://preferences") {} else { XCTFail() }
        if case .preferences? = parse("stag://settings") {} else { XCTFail() }
    }

    func testHistoryAndPinboardHosts() {
        if case .history? = parse("stag://history") {} else { XCTFail() }
        if case .pinboard? = parse("stag://pinboard") {} else { XCTFail() }
    }

    func testUnknownHostReturnsNil() {
        XCTAssertNil(parse("stag://wat"))
    }
}
