import Domain
import Foundation

public struct OllamaEndpoint: Sendable, Equatable {
    public let url: URL
    public init(_ text: String = "http://127.0.0.1:11434") throws {
        guard let c = URLComponents(string: text), c.scheme == "http", c.host == "127.0.0.1",
              let port = c.port, (1024...65535).contains(port), c.user == nil, c.password == nil,
              c.path.isEmpty, c.query == nil, c.fragment == nil, let url = c.url,
              url.absoluteString == text else { throw InferenceFailure.endpointDenied }
        self.url = url
    }
}
public enum OllamaRoute: String, Sendable { case version, tags, ps, show, chat }
public struct OllamaHTTPRequest: Sendable {
    public let endpoint: OllamaEndpoint
    public let route: OllamaRoute
    public let body: Data?
    public let timeoutSeconds: Double
    public let responseLimit: Int
    public init(endpoint: OllamaEndpoint, route: OllamaRoute, body: Data? = nil, timeoutSeconds: Double = 5, responseLimit: Int = 131_072) throws {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0, timeoutSeconds <= 120,
              (1...131_072).contains(responseLimit), (body?.count ?? 0) <= 16_384,
              (route == .chat || route == .show) == (body != nil) else { throw InferenceFailure.invalidRequest }
        self.endpoint = endpoint; self.route = route; self.body = body; self.timeoutSeconds = timeoutSeconds; self.responseLimit = responseLimit
    }
}
public struct OllamaHTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int = 200, body: Data) { self.status = status; self.body = body }
}
public protocol OllamaHTTPTransport: Sendable { func send(_ request: OllamaHTTPRequest) async throws -> OllamaHTTPResponse }
private final class LocalSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { completionHandler(.cancelAuthenticationChallenge, nil) }
}
/// Ephemeral per-exchange session. No redirects, proxies, cookies, credentials, downloads or application retries.
public struct LocalOllamaHTTPTransport: OllamaHTTPTransport {
    private let networkPolicy: ApplicationNetworkPolicy
    public init(networkPolicy: ApplicationNetworkPolicy = .shared) { self.networkPolicy = networkPolicy }
    public func send(_ request: OllamaHTTPRequest) async throws -> OllamaHTTPResponse {
        guard !Task.isCancelled else { throw InferenceFailure.cancelled }
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]; config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.httpShouldSetCookies = false; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = request.timeoutSeconds; config.timeoutIntervalForResource = request.timeoutSeconds
        let session = URLSession(configuration: config, delegate: LocalSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let ticket = try networkPolicy.begin(request.endpoint.url) { session.invalidateAndCancel() }
        defer { networkPolicy.finish(ticket) }
        let url = request.endpoint.url.appendingPathComponent("api").appendingPathComponent(request.route.rawValue)
        var r = URLRequest(url: url); r.httpMethod = request.body == nil ? "GET" : "POST"; r.httpBody = request.body
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue("application/json", forHTTPHeaderField: "Accept")
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int64(request.timeoutSeconds * 1000)))
        do {
            return try await withTaskCancellationHandler {
                let (stream, response) = try await session.bytes(for: r)
                guard let head = response as? HTTPURLResponse, head.url == url else { throw InferenceFailure.invalidResponse }
                guard !(300...399).contains(head.statusCode) else { throw InferenceFailure.redirectDenied }
                guard head.expectedContentLength <= request.responseLimit else { throw InferenceFailure.oversized }
                guard head.mimeType?.lowercased() == "application/json" else { throw InferenceFailure.invalidResponse }
                var bytes = Data()
                for try await byte in stream {
                    guard !Task.isCancelled else { throw InferenceFailure.cancelled }
                    guard ContinuousClock.now < deadline else { throw InferenceFailure.timeout }
                    guard bytes.count < request.responseLimit else { throw InferenceFailure.oversized }
                    bytes.append(byte)
                }
                guard !Task.isCancelled else { throw InferenceFailure.cancelled }
                guard ContinuousClock.now < deadline else { throw InferenceFailure.timeout }
                return .init(status: head.statusCode, body: bytes)
            } onCancel: { session.invalidateAndCancel() }
        } catch let failure as InferenceFailure { throw failure }
        catch let error as URLError { throw error.code == .timedOut ? InferenceFailure.timeout : error.code == .cancelled ? .cancelled : .unavailable }
        catch { throw InferenceFailure.unavailable }
    }
}
