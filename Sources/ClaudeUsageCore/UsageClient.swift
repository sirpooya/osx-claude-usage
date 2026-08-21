import Foundation

public enum UsageClientError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case emptyResponse
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "The access token was rejected. Claude Code may need to sign in again."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited. Retrying in \(Int(retryAfter))s."
            }
            return "Rate limited by the usage endpoint."
        case .httpStatus(let code):
            return "Usage endpoint returned HTTP \(code)."
        case .emptyResponse:
            return "Usage endpoint returned no data."
        case .decoding(let detail):
            return "Could not read the usage response: \(detail)"
        case .transport(let detail):
            return "Network error: \(detail)"
        }
    }
}

/// Talks to the authoritative OAuth usage endpoint.
///
/// The `User-Agent` below is load bearing. Without it the endpoint answers an
/// instant and persistent 429 even for a perfectly valid token, which is the
/// trap that pushed most other menu bar trackers onto cookie scraping. Do not
/// remove it and do not make it configurable.
public struct UsageClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let betaHeader = "oauth-2025-04-20"
    static let userAgent = "claude-cli/2.0.0 (external, cli)"

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpAdditionalHeaders = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Fetches one snapshot. The token is passed in per call rather than held
    /// by the client, so a rotated keychain entry is picked up immediately.
    public func fetch(accessToken: String, now: Date = Date()) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageClientError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299:
                break
            case 401, 403:
                throw UsageClientError.unauthorized
            case 429:
                let header = http.value(forHTTPHeaderField: "Retry-After")
                throw UsageClientError.rateLimited(retryAfter: header.flatMap(TimeInterval.init))
            default:
                throw UsageClientError.httpStatus(http.statusCode)
            }
        }

        guard !data.isEmpty else { throw UsageClientError.emptyResponse }
        return try Self.decodeSnapshot(from: data, fetchedAt: now)
    }

    /// Split out so tests can feed recorded payloads straight in.
    public static func decodeSnapshot(from data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        do {
            let decoded = try ISO8601.makeDecoder().decode(UsageEndpointResponse.self, from: data)
            return UsageSnapshot(
                fetchedAt: fetchedAt,
                limits: decoded.limits ?? [],
                spend: decoded.spend
            )
        } catch {
            throw UsageClientError.decoding(String(describing: error))
        }
    }
}
