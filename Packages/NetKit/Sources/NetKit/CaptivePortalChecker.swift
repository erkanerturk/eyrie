import Foundation

public enum InternetReachability: Sendable, Equatable {
    case fullInternet
    /// Link is up but something intercepts traffic (hotel/café login page).
    case captivePortal
    case noInternet
}

public protocol CaptivePortalChecking: Sendable {
    func check() async -> InternetReachability
}

/// Pure: a redirect or tampered body is itself the captive-portal signal.
public enum CaptiveResponseClassifier {
    public static func classify(statusCode: Int?, body: String?) -> InternetReachability {
        guard let statusCode else { return .noInternet }
        if (300..<400).contains(statusCode) { return .captivePortal }
        if statusCode == 200, let body, body.contains("Success") { return .fullInternet }
        return .captivePortal
    }
}

/// Apple's own hotspot probe, fetched the way the system does it: plain HTTP
/// (portals must be able to intercept it — hence the scoped ATS exception in
/// project.yml) and redirects refused, since a 302 answers the question.
public struct LiveCaptivePortalChecker: CaptivePortalChecking {
    public init() {}

    public func check() async -> InternetReachability {
        var request = URLRequest(url: URL(string: "http://captive.apple.com/hotspot-detect.html")!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        let session = URLSession(
            configuration: configuration,
            delegate: RedirectRefuser(),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            return CaptiveResponseClassifier.classify(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        } catch {
            return .noInternet
        }
    }
}

private final class RedirectRefuser: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
