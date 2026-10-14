import Foundation

/// Reply from the instance's v8 `observability/logs` route. Only the raw lines are consumed: the
/// route also answers with `line-count`, `latest-timestamp`, and `next-cursor` for incremental
/// reads, which this widget does not need because it re-reads the tail of the log each time.
struct LogsResponse: Decodable, Sendable {
    let lines: [String]
}
