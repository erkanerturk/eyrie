import Darwin
import Foundation

/// Fetches the public IP. Called only while the panel is open; cancellation
/// (panel close) must tear the request down promptly.
public protocol ExternalIPFetching: Sendable {
    func fetch() async throws -> String
}

/// Plain-text "what is my IP" services, tried in order.
public struct LiveExternalIPFetcher: ExternalIPFetching {
    private static let endpoints = [
        URL(string: "https://api.ipify.org")!,
        URL(string: "https://checkip.amazonaws.com")!,
    ]

    public init() {}

    public func fetch() async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var lastError: any Error = URLError(.cannotFindHost)
        for endpoint in Self.endpoints {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(from: endpoint)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let text = String(data: data, encoding: .utf8),
                      let ip = IPValidator.normalize(text) else {
                    lastError = URLError(.badServerResponse)
                    continue
                }
                return ip
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

/// Validates that a response body really is a bare IP address — a captive
/// portal returning an HTML login page must never end up on the card.
public enum IPValidator {
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count < 46 else { return nil }

        var v4 = in_addr()
        if inet_pton(AF_INET, trimmed, &v4) == 1 { return trimmed }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, trimmed, &v6) == 1 { return trimmed }
        return nil
    }
}
