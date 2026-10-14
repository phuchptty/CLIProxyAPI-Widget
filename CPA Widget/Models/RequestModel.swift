import Foundation

/// Extracts the requested model from one per-request log file.
///
/// The file is the instance's request transcript: `=== REQUEST INFO ===`, `=== HEADERS ===`, then
/// `=== REQUEST BODY ===` holding the client's JSON body. Only the body is read, and only its
/// top-level `model` string is kept. Headers and everything else are never retained.
enum RequestModel {
    private static let bodyMarker = Data("=== REQUEST BODY ===\n".utf8)
    private static let sectionMarker = Data("\n=== ".utf8)

    static func model(inLogFile file: Data) -> String? {
        guard let start = file.range(of: bodyMarker) else { return nil }
        var body = file[start.upperBound...]
        // The body ends where the next section header begins.
        if let end = body.range(of: sectionMarker) { body = body[..<end.lowerBound] }
        guard let object = try? JSONSerialization.jsonObject(with: Data(body)) as? [String: Any],
              let model = object["model"] as? String, !model.isEmpty else { return nil }
        return model
    }
}
