import Foundation
import Testing
@testable import ClaudeUsageCore

@Suite("Keychain payload parsing")
struct KeychainParsingTests {
    private func payload(_ json: String) -> Data { json.data(using: .utf8)! }

    @Test("Reads the access token and expiry out of the real item shape")
    func readsToken() throws {
        let data = payload("""
        {"claudeAiOauth": {"accessToken": "abc123", "refreshToken": "def456",
          "expiresAt": 1787411399000, "scopes": ["user:inference"]}}
        """)
        let credentials = try KeychainTokenStore.parse(data)
        #expect(credentials.accessToken == "abc123")
        #expect(credentials.expiresAt != nil)
    }

    @Test("An item with no oauth block is reported as malformed")
    func rejectsMissingBlock() {
        #expect(throws: KeychainError.malformedPayload) {
            try KeychainTokenStore.parse(payload(#"{"somethingElse": true}"#))
        }
    }

    @Test("An empty token is rejected rather than sent as a bearer")
    func rejectsEmptyToken() {
        #expect(throws: KeychainError.tokenMissing) {
            try KeychainTokenStore.parse(payload(#"{"claudeAiOauth": {"accessToken": ""}}"#))
        }
    }

    @Test("Non JSON contents are reported as malformed, not crashed on")
    func rejectsGarbage() {
        #expect(throws: KeychainError.malformedPayload) {
            try KeychainTokenStore.parse(payload("not json at all"))
        }
    }

    @Test("A missing expiry is allowed, since the token may still be good")
    func allowsMissingExpiry() throws {
        let credentials = try KeychainTokenStore.parse(payload(#"{"claudeAiOauth": {"accessToken": "t"}}"#))
        #expect(credentials.expiresAt == nil)
        #expect(credentials.isExpired == false)
    }

    @Test("A past expiry is reported as expired")
    func detectsExpiry() throws {
        let past = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        let credentials = try KeychainTokenStore.parse(payload(
            "{\"claudeAiOauth\": {\"accessToken\": \"t\", \"expiresAt\": \(past)}}"
        ))
        #expect(credentials.isExpired)
    }
}
