import Foundation

/// Reply from the instance's v8 `requests/api-call` route. The body stays a string because
/// the upstream response is opaque to the instance; `body` decodes only when the caller asked
/// JSON of a provider it understands.
struct APICallResult: Decodable, Sendable {
    let statusCode: Int
    let body: String?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case body
    }
}
