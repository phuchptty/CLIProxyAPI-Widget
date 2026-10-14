import Foundation

/// One proxied API request read from the instance's file log.
///
/// The instance writes `[timestamp] [request-id] [level] [caller] <message>`, and a Gin access
/// line's message is `200 |    1.23s | 127.0.0.1 | POST    "/v1/chat/completions"`. Only lines
/// with that shape whose path is one of the paths the instance itself treats as API traffic become
/// entries, so its own management traffic and ordinary app lines do not crowd out client requests.
struct RequestLogEntry: Sendable {
    /// The instance's wall clock exactly as written; the log line carries no zone.
    let timestamp: String
    /// `HH:MM:SS` taken from `timestamp`.
    let timeOfDay: String
    /// Absent when the instance logged the line without a request ID.
    let requestID: String?
    let status: Int
    let latency: String
    let clientIP: String
    let method: String
    /// Request path without its query string.
    let path: String
    /// `[credits]`, a trailing error message, or nil.
    let note: String?
    /// The whole line, for the row's help text.
    let rawLine: String

    /// The newest `limit` requests in `lines`, which the instance returns oldest first.
    static func history(from lines: [String], limit: Int) -> [RequestLogEntry] {
        var entries: [RequestLogEntry] = []
        for line in lines.reversed() {
            guard entries.count < limit else { break }
            if let entry = RequestLogEntry.entry(for: line) { entries.append(entry) }
        }
        return entries
    }

    static func entry(for line: String) -> RequestLogEntry? {
        let head: [String]
        let rest: String
        if let four = prefixFields(of: line, count: 4), isCaller(four.fields[3]) {
            (head, rest) = (four.fields, four.rest)
        } else if let three = prefixFields(of: line, count: 3) {
            (head, rest) = (three.fields, three.rest)
        } else {
            return nil
        }
        guard isLogTimestamp(head[0]), head[1] == emptyRequestID || isRequestID(head[1]),
              levels.contains(head[2].trimmingCharacters(in: .whitespaces)),
              let access = accessLog(rest) else { return nil }
        return RequestLogEntry(
            timestamp: head[0],
            timeOfDay: String(head[0].suffix(8)),
            requestID: head[1] == emptyRequestID ? nil : head[1],
            status: access.status,
            latency: access.latency,
            clientIP: access.clientIP,
            method: access.method,
            path: access.path,
            note: access.note,
            rawLine: line
        )
    }

    /// The instance's own definition of API traffic: the paths it generates a request ID for
    /// (`aiAPIPrefixes` in `internal/logging/gin_logger.go`). Everything else is management or
    /// health traffic rather than a client request.
    private static let apiPathPrefixes = ["/v1", "/v1beta", "/openai/v1", "/backend-api/codex"]
    private static let levels: Set<String> = ["trace", "debug", "info", "warn", "warning", "error", "fatal", "panic"]
    private static let emptyRequestID = "--------"

    private struct AccessLog {
        let status: Int
        let latency: String
        let clientIP: String
        let method: String
        let path: String
        let note: String?
    }

    /// Splits the leading `[...]` fields of a formatter line from the message that follows them.
    private static func prefixFields(of line: String, count: Int) -> (fields: [String], rest: String)? {
        var remaining = line[...]
        var fields: [String] = []
        for _ in 0..<count {
            guard remaining.first == "[", let close = remaining.firstIndex(of: "]") else { return nil }
            fields.append(String(remaining[remaining.index(after: remaining.startIndex)..<close]))
            remaining = remaining[remaining.index(after: close)...]
            if remaining.first == " " { remaining = remaining.dropFirst() }
        }
        return (fields, String(remaining))
    }

    /// Recognizes the Gin access line and keeps only paths the instance proxies.
    private static func accessLog(_ message: String) -> AccessLog? {
        // Status, latency, client IP, and the rest; the path cannot contain `|`, and any trailing
        // error message stays with the last field because the split is limited.
        let fields = message.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count == 4 else { return nil }
        let statusField = fields[0].trimmingCharacters(in: .whitespaces)
        guard statusField.count == 3, statusField.allSatisfy({ $0.isASCII && $0.isNumber }),
              let status = Int(statusField) else { return nil }
        let latency = fields[1].trimmingCharacters(in: .whitespaces)
        let clientIP = fields[2].trimmingCharacters(in: .whitespaces)
        guard !latency.isEmpty, !clientIP.isEmpty else { return nil }
        let tail = fields[3].trimmingCharacters(in: .whitespaces)
        guard let openQuote = tail.firstIndex(of: "\"") else { return nil }
        let method = tail[tail.startIndex..<openQuote].trimmingCharacters(in: .whitespaces)
        guard !method.isEmpty, method.allSatisfy({ $0.isUppercase || $0 == "-" }) else { return nil }
        let afterOpen = tail[tail.index(after: openQuote)...]
        guard let closeQuote = afterOpen.firstIndex(of: "\"") else { return nil }
        let loggedPath = afterOpen[..<closeQuote]
        let path = loggedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard apiPathPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return nil }
        let trailing = afterOpen[afterOpen.index(after: closeQuote)...].trimmingCharacters(in: CharacterSet(charactersIn: " |"))
        return AccessLog(
            status: status,
            latency: latency,
            clientIP: clientIP,
            method: String(method),
            path: path,
            note: trailing.isEmpty ? nil : trailing
        )
    }

    private static func isLogTimestamp(_ value: String) -> Bool {
        guard value.count == 19 else { return false }
        for (index, character) in value.enumerated() {
            switch index {
            case 4, 7:
                if character != "-" { return false }
            case 10:
                if character != " " { return false }
            case 13, 16:
                if character != ":" { return false }
            default:
                if !(character.isASCII && character.isNumber) { return false }
            }
        }
        return true
    }

    private static func isRequestID(_ value: String) -> Bool {
        value.count == 8 && value.allSatisfy { $0.isASCII && ($0.isHexDigit || $0 == "-") }
    }

    /// The formatter prints the caller as `file.go:line`.
    private static func isCaller(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        return parts.count == 2 && parts[0].hasSuffix(".go") && !parts[1].isEmpty && parts[1].allSatisfy { $0.isASCII && $0.isNumber }
    }
}
