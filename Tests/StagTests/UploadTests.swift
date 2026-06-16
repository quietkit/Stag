import XCTest
@testable import Stag

/// `UploadConfig` parsing plus the full `ImageUploader.upload` request-building and
/// response-parsing pipeline, exercised against a stubbed `URLProtocol` so no real
/// network is touched. This also covers the private JSON key-path `extract`.
final class UploadTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    // MARK: - parseHeaders

    func testParseHeadersBasic() {
        let headers = UploadConfig.parseHeaders("Authorization: Bearer abc\nX-Foo: bar")
        XCTAssertEqual(headers["Authorization"], "Bearer abc")
        XCTAssertEqual(headers["X-Foo"], "bar")
    }

    func testParseHeadersTrimsWhitespaceAndKeepsColonsInValue() {
        let headers = UploadConfig.parseHeaders("  Key  :  http://a.b:8080/x  ")
        XCTAssertEqual(headers["Key"], "http://a.b:8080/x")
    }

    func testParseHeadersSkipsLinesWithoutColonOrEmptyKey() {
        let headers = UploadConfig.parseHeaders("nocolon\n: emptyKey\nGood: yes")
        XCTAssertNil(headers["nocolon"])
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers["Good"], "yes")
    }

    // MARK: - isConfigured

    func testIsConfigured() {
        XCTAssertFalse(UploadConfig(endpoint: "  ", method: "POST", fieldName: "", headers: [:], responseURLKey: "").isConfigured)
        XCTAssertTrue(UploadConfig(endpoint: "https://x", method: "POST", fieldName: "", headers: [:], responseURLKey: "").isConfigured)
    }

    // MARK: - UploadError descriptions

    func testUploadErrorDescriptions() {
        XCTAssertNotNil(UploadError.notConfigured.errorDescription)
        XCTAssertNotNil(UploadError.badEndpoint.errorDescription)
        XCTAssertEqual(UploadError.server(status: 503, body: "x").errorDescription, "Upload failed (HTTP 503).")
        XCTAssertNotNil(UploadError.emptyResponse.errorDescription)
    }

    // MARK: - upload pipeline

    private func config(endpoint: String = "https://example.test/upload",
                        fieldName: String = "",
                        responseURLKey: String = "") -> UploadConfig {
        UploadConfig(endpoint: endpoint, method: "POST", fieldName: fieldName,
                     headers: [:], responseURLKey: responseURLKey)
    }

    private func install(_ handler: @escaping (URLRequest) -> (Int, Data)) {
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.handler = handler
    }

    func testUploadThrowsWhenNotConfigured() async {
        do {
            _ = try await ImageUploader.upload(Data(), config: config(endpoint: ""))
            XCTFail("expected throw")
        } catch {
            guard case UploadError.notConfigured = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testUploadThrowsOnBadEndpoint() async {
        do {
            _ = try await ImageUploader.upload(Data(), config: config(endpoint: "http://exa mple.com"))
            XCTFail("expected throw")
        } catch {
            guard case UploadError.badEndpoint = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testUploadRawBodyReturnsTrimmedBody() async throws {
        install { _ in (200, Data("  https://cdn/img.png \n".utf8)) }
        let link = try await ImageUploader.upload(Data([0x1, 0x2]), config: config())
        XCTAssertEqual(link, "https://cdn/img.png")
    }

    func testUploadMultipartSetsBoundaryContentType() async throws {
        install { req in
            let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(ct.hasPrefix("multipart/form-data; boundary="), "got \(ct)")
            return (200, Data("https://host/x".utf8))
        }
        let link = try await ImageUploader.upload(Data([0xAA]), config: config(fieldName: "file"))
        XCTAssertEqual(link, "https://host/x")
    }

    func testUploadServerErrorThrows() async {
        install { _ in (500, Data("boom".utf8)) }
        do {
            _ = try await ImageUploader.upload(Data(), config: config())
            XCTFail("expected throw")
        } catch {
            guard case UploadError.server(let status, _) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(status, 500)
        }
    }

    func testUploadEmptyResponseThrows() async {
        install { _ in (200, Data()) }
        do {
            _ = try await ImageUploader.upload(Data(), config: config())
            XCTFail("expected throw")
        } catch {
            guard case UploadError.emptyResponse = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testUploadExtractsJSONKeyPath() async throws {
        let json = #"{"status":"ok","data":{"link":"https://json/extracted.png"}}"#
        install { _ in (200, Data(json.utf8)) }
        let link = try await ImageUploader.upload(Data(), config: config(responseURLKey: "data.link"))
        XCTAssertEqual(link, "https://json/extracted.png")
    }

    func testUploadExtractsNumericJSONValueAsString() async throws {
        let json = #"{"id":12345}"#
        install { _ in (200, Data(json.utf8)) }
        let link = try await ImageUploader.upload(Data(), config: config(responseURLKey: "id"))
        XCTAssertEqual(link, "12345")
    }

    func testUploadFallsBackToBodyWhenKeyPathMisses() async throws {
        let json = #"{"data":{"other":"x"}}"#
        install { _ in (200, Data(json.utf8)) }
        // key path not found → falls back to the raw (trimmed) body
        let link = try await ImageUploader.upload(Data(), config: config(responseURLKey: "data.link"))
        XCTAssertEqual(link, json)
    }
}

/// Minimal in-process URL stub. Registered globally so `URLSession.shared`
/// (used by `ImageUploader`) routes through it.
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { handler != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
