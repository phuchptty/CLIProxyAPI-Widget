import Foundation

struct ManagementClient: Sendable {
    let baseURL: URL
    let key: String

    static func validatedURL(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" || url.path == "/v8/management" || url.path == "/v8/management/"
        else { throw ManagementError.invalidURL }
        return url
    }

    static func requiresHTTPConfirmation(for url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return false }
        let host = (url.host ?? "").lowercased()
        let octets = host.split(separator: ".")
        if octets.count == 4,
           let firstOctet = UInt8(octets[0]),
           octets.allSatisfy({ UInt8($0) != nil }),
           firstOctet == 100 || firstOctet == 127 { return false }
        if host == "localhost" || host == "::1" || host == "[::1]" { return false }
        return true
    }

    static func requiresHTTPConfirmation(for value: String) throws -> Bool {
        requiresHTTPConfirmation(for: try validatedURL(value))
    }

    func credentials() async throws -> [Credential] {
        let result: CredentialsResponse = try await get(["credentials"])
        return result.files
    }

    func quota(for credential: Credential) async throws -> QuotaResponse {
        guard let plugin = credential.quotaPluginID, !plugin.isEmpty,
              let index = credential.authIndex, !index.isEmpty else {
            throw ManagementError.unsupportedQuota
        }
        return try await get(["plugins", plugin, "quota"], query: [URLQueryItem(name: "auth_index", value: index)])
    }

    /// Reads the tail of the instance's file log. This reads the log files it rotates; it never
    /// drains the destructive usage queue.
    func logs(limit: Int) async throws -> [String] {
        do {
            let response: LogsResponse = try await get(["observability", "logs"], query: [URLQueryItem(name: "limit", value: String(limit))])
            return response.lines
        } catch ManagementError.http(400) {
            // The only documented 400 here is file logging being switched off; the limit is valid.
            throw ManagementError.requestLogsUnavailable
        }
    }

    /// Downloads the per-request log file for one request ID and returns the model named in its
    /// `REQUEST BODY` section. Only that section is parsed; headers and the rest of the file are
    /// dropped. A 404 means the instance kept no file for that request (request logging is off).
    func requestModel(requestID: String) async throws -> String? {
        let data = try await perform(path: ["observability", "logs", "requests", requestID], query: [], method: "GET", body: nil)
        return RequestModel.model(inLogFile: data)
    }

    /// Forwards one request to an upstream provider through the instance, substituting the
    /// credential's access token for the literal `$TOKEN$` header value.
    func apiCall(authIndex: String, method: String, url: String, headers: [String: String], body: String?) async throws -> APICallResult {
        guard !authIndex.isEmpty else { throw ManagementError.unsupportedQuota }
        let payload = APICallRequest(authIndex: authIndex, method: method, url: url, header: headers, data: body)
        return try await post(["requests", "api-call"], body: payload)
    }

    private func get<T: Decodable>(_ path: [String], query: [URLQueryItem] = []) async throws -> T {
        try await send(path: path, query: query, method: "GET", body: nil)
    }

    private func post<T: Decodable>(_ path: [String], body: some Encodable) async throws -> T {
        try await send(path: path, query: [], method: "POST", body: try JSONEncoder().encode(body))
    }

    private func send<T: Decodable>(path: [String], query: [URLQueryItem], method: String, body: Data?) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await perform(path: path, query: query, method: method, body: body))
    }

    /// Performs an authenticated request and returns its raw body. Non-2xx responses surface only
    /// their status code: server bodies can contain credentials and are never shown or logged.
    private func perform(path: [String], query: [URLQueryItem], method: String, body: Data?) async throws -> Data {
        var url = baseURL
        if !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty {
            // A full management base is accepted; do not append it a second time.
        } else {
            url.appendPathComponent("v8")
            url.appendPathComponent("management")
        }
        for component in path { url.appendPathComponent(component) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ManagementError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let requestURL = components.url else { throw ManagementError.invalidURL }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpBody = body
        // An api-call waits on a third-party provider, so it needs more headroom than a local read.
        request.timeoutInterval = method == "GET" ? 15 : 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ManagementError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw ManagementError.http(response.statusCode)
        }
        return data
    }
}
