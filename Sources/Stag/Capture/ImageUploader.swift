import Foundation

/// Configuration for uploading a PNG to a user-controlled endpoint. Stag never
/// uploads anything on its own — sharing is entirely opt-in and points wherever
/// the user configures (their own server, an S3-compatible bucket gateway, an
/// image host with an API key, etc.). This keeps the privacy promise intact.
struct UploadConfig {
    var endpoint: String
    var method: String           // "POST" or "PUT"
    var fieldName: String        // non-empty → multipart/form-data; empty → raw body
    var headers: [String: String]
    var responseURLKey: String   // JSON key path (dot-separated) to the link; empty → whole body

    var isConfigured: Bool { !endpoint.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Parses a "Key: Value" per line block into header pairs.
    static func parseHeaders(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { out[key] = value }
        }
        return out
    }
}

enum UploadError: LocalizedError {
    case notConfigured
    case badEndpoint
    case server(status: Int, body: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:           return "No upload endpoint configured."
        case .badEndpoint:             return "The upload endpoint URL is invalid."
        case .server(let status, _):   return "Upload failed (HTTP \(status))."
        case .emptyResponse:           return "Upload succeeded but returned no link."
        }
    }
}

enum ImageUploader {
    /// Uploads PNG data and returns the resulting share link.
    static func upload(_ png: Data, config: UploadConfig) async throws -> String {
        guard config.isConfigured else { throw UploadError.notConfigured }
        guard let url = URL(string: config.endpoint.trimmingCharacters(in: .whitespaces)) else {
            throw UploadError.badEndpoint
        }

        var req = URLRequest(url: url)
        req.httpMethod = config.method.isEmpty ? "POST" : config.method
        for (k, v) in config.headers { req.setValue(v, forHTTPHeaderField: k) }

        if config.fieldName.isEmpty {
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("image/png", forHTTPHeaderField: "Content-Type")
            }
            req.httpBody = png
        } else {
            let boundary = "Boundary-\(UUID().uuidString)"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(config.fieldName)\"; filename=\"stag.png\"\r\n")
            body.appendString("Content-Type: image/png\r\n\r\n")
            body.append(png)
            body.appendString("\r\n--\(boundary)--\r\n")
            req.httpBody = body
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UploadError.server(status: http.statusCode,
                                     body: String(data: data, encoding: .utf8) ?? "")
        }

        if !config.responseURLKey.isEmpty,
           let link = extract(from: data, keyPath: config.responseURLKey) {
            return link
        }
        let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !body.isEmpty else { throw UploadError.emptyResponse }
        return body
    }

    /// Extracts a dot-separated key path from a JSON response body, e.g. "data.link".
    private static func extract(from data: Data, keyPath: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var current: Any? = obj
        for part in keyPath.split(separator: ".") {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[String(part)]
        }
        if let s = current as? String { return s }
        if let n = current as? NSNumber { return n.stringValue }
        return nil
    }
}

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}
