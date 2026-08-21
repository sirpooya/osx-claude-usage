//
//  Account.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-02-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// 凭据来源
/// 决定刷新时从哪里取 token：手动粘贴 / 浏览器 OAuth 的凭据存在账户里，
/// CLI 同步的账户则每次轮询都重新读 Claude Code 的钥匙串条目（CLI 会在我们背后轮换它）。
enum CredentialSource: String, Codable {
    /// 手动粘贴的 sessionKey，或应用自己走浏览器 OAuth 拿到的 refresh_token
    case manual
    /// 从 Claude Code CLI 的钥匙串条目同步而来
    case claudeCodeCLI

    var isCLISynced: Bool { self == .claudeCodeCLI }
}

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var sessionKey: String
    var organizationId: String
    var organizationName: String
    var alias: String?
    let createdAt: Date
    var provider: ProviderType
    /// 凭据来源（旧数据无此字段，解码时默认 .manual）
    var credentialSource: CredentialSource
    /// CLI 同步账户对应的钥匙串 service 名（其余来源为 nil）
    var keychainService: String?

    var displayName: String {
        if let alias = alias, !alias.isEmpty {
            return alias
        }
        return organizationName
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id, sessionKey, organizationId, organizationName, alias, createdAt, provider
        case credentialSource, keychainService
    }

    // MARK: - Codable

    // 自定义解码：旧版 JSON 不含 provider 字段时默认为 .claude，确保旧账号数据零迁移
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionKey = try container.decode(String.self, forKey: .sessionKey)
        organizationId = try container.decode(String.self, forKey: .organizationId)
        organizationName = try container.decode(String.self, forKey: .organizationName)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        provider = try container.decodeIfPresent(ProviderType.self, forKey: .provider) ?? .claude
        credentialSource = try container.decodeIfPresent(CredentialSource.self, forKey: .credentialSource) ?? .manual
        keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService)
    }

    // MARK: - Initialization

    init(
        sessionKey: String,
        organizationId: String,
        organizationName: String,
        alias: String? = nil,
        provider: ProviderType = .claude,
        credentialSource: CredentialSource = .manual,
        keychainService: String? = nil
    ) {
        self.id = UUID()
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.alias = alias
        self.createdAt = Date()
        self.provider = provider
        self.credentialSource = credentialSource
        self.keychainService = keychainService
    }

    init(
        id: UUID,
        sessionKey: String,
        organizationId: String,
        organizationName: String,
        alias: String?,
        createdAt: Date,
        provider: ProviderType = .claude,
        credentialSource: CredentialSource = .manual,
        keychainService: String? = nil
    ) {
        self.id = id
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.alias = alias
        self.createdAt = createdAt
        self.provider = provider
        self.credentialSource = credentialSource
        self.keychainService = keychainService
    }

    // MARK: - Equatable

    static func == (lhs: Account, rhs: Account) -> Bool {
        return lhs.id == rhs.id
    }
}
