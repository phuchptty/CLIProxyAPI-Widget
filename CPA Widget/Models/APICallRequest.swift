import Foundation

/// Body for one upstream request forwarded by the instance's v8 `requests/api-call` route.
struct APICallRequest: Encodable, Sendable {
    let authIndex: String
    let method: String
    let url: String
    let header: [String: String]
    let data: String?

    enum CodingKeys: String, CodingKey {
        case authIndex = "auth_index"
        case method, url, header, data
    }
}
