import Foundation
import Security

public enum KeychainError: LocalizedError, Equatable {
    case itemNotFound
    case accessDenied
    case malformedPayload
    case tokenMissing
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "No Claude Code credentials in the login keychain. Sign in with the claude CLI first."
        case .accessDenied:
            return "Keychain access was denied. Allow ClaudeUsage to read the Claude Code credentials item."
        case .malformedPayload:
            return "The Claude Code keychain item is not in the expected format."
        case .tokenMissing:
            return "The Claude Code keychain item has no access token."
        case .unexpectedStatus(let status):
            return "Keychain read failed with status \(status)."
        }
    }
}

/// What the Keychain item holds, minus anything we do not need.
public struct OAuthCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

/// Reads the Claude Code OAuth token from the macOS login keychain.
///
/// Claude Code rotates this item underneath us roughly hourly, so the token is
/// read at the point of use on every poll and never held across polls. The
/// token is never logged, never persisted, and never rendered.
public struct KeychainTokenStore: Sendable {
    public static let service = "Claude Code-credentials"

    private let service: String

    public init(service: String = KeychainTokenStore.service) {
        self.service = service
    }

    public func readCredentials() throws -> OAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            throw KeychainError.accessDenied
        default:
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = item as? Data else { throw KeychainError.malformedPayload }
        return try Self.parse(data)
    }

    /// Split out from the Keychain call so it can be unit tested without
    /// touching the real keychain.
    static func parse(_ data: Data) throws -> OAuthCredentials {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any]
        else {
            throw KeychainError.malformedPayload
        }

        guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw KeychainError.tokenMissing
        }

        // expiresAt is milliseconds since epoch in the items observed so far.
        var expiry: Date?
        if let millis = oauth["expiresAt"] as? Double {
            expiry = Date(timeIntervalSince1970: millis / 1000)
        } else if let millis = oauth["expiresAt"] as? Int {
            expiry = Date(timeIntervalSince1970: Double(millis) / 1000)
        }

        return OAuthCredentials(accessToken: token, expiresAt: expiry)
    }
}
