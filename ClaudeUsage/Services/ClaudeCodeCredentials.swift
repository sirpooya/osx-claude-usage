//
//  ClaudeCodeCredentials.swift
//  ClaudeUsage
//
//  读取 Claude Code CLI 自己存在 macOS 钥匙串里的 OAuth 凭据，
//  从而免去用户手动粘贴 sessionKey / 走一遍浏览器登录（"CLI Account Sync"）。
//
//  钥匙串条目形如：
//    service = "Claude Code-credentials"（多 CLAUDE_CONFIG_DIR 时带后缀，
//              例如 "Claude Code-credentials-1100457a"）
//    account = macOS 用户名
//    data    = {"claudeAiOauth":{"accessToken":…,"refreshToken":…,
//               "expiresAt":<毫秒时间戳>,"scopes":[…],"subscriptionType":"team"}}
//
//  注意：读取别的 App 创建的钥匙串条目要求本 App **不开** App Sandbox
//  （沙箱内只能访问自己 access group 里的条目）。见 Config/ClaudeUsage.entitlements。
//

import Foundation
import OSLog
import Security

/// Claude Code 钥匙串条目里的 OAuth 凭据
struct ClaudeCodeCredentials: Equatable {
    /// 钥匙串 service 名（"Claude Code-credentials" 或带 config-dir 后缀的变体）
    let serviceName: String
    /// 钥匙串 account 名（通常是 macOS 用户名）
    let accountName: String

    let accessToken: String
    let refreshToken: String
    /// access_token 过期时间；条目里缺失时为 nil
    let expiresAt: Date?
    let scopes: [String]
    /// 订阅类型（"team" / "max" / "pro" …），缺失时为空串
    let subscriptionType: String

    /// 该 access_token 是否还能用（留 2 分钟余量，避免临界值）
    var isAccessTokenUsable: Bool {
        guard !accessToken.isEmpty else { return false }
        guard let expiresAt else { return true }  // 没给过期时间就先当作可用
        return expiresAt > Date().addingTimeInterval(2 * 60)
    }

    /// 打码后的 token，仅用于界面展示（前 12 位 + 后 4 位，中间省略）
    /// 完整 token 永不落盘、不写日志。
    var maskedAccessToken: String {
        Self.mask(accessToken)
    }

    static func mask(_ token: String) -> String {
        guard token.count > 20 else { return String(repeating: "•", count: max(token.count, 8)) }
        return "\(token.prefix(12))\(String(repeating: "•", count: 6))\(token.suffix(4))"
    }
}

/// Claude Code 钥匙串条目的读写
///
/// 只用 Security 框架，不 spawn `security(1)`：后者会把明文 token 放进另一个进程的
/// 输出管道，也拿不到"是否被用户拒绝"这类具体错误码。
enum ClaudeCodeKeychain {

    /// Claude Code 钥匙串 service 名前缀（带后缀的变体对应非默认 CLAUDE_CONFIG_DIR）
    static let servicePrefix = "Claude Code-credentials"

    /// 默认（无后缀）service 名
    static let defaultService = "Claude Code-credentials"

    /// 一个可用的钥匙串条目（只含属性，不含机密数据）
    struct Entry: Identifiable, Hashable {
        var id: String { "\(service)\u{1F}\(account)" }
        let service: String
        let account: String

        /// 是否为默认 config dir 对应的条目
        var isDefault: Bool { service == ClaudeCodeKeychain.defaultService }

        /// 供选择器展示：默认条目显示为 service 名，带后缀的把后缀标出来
        var displayName: String {
            guard !isDefault else { return service }
            return service
        }
    }

    // MARK: - 枚举条目（不读机密数据，因此不会触发钥匙串授权弹窗）

    /// 列出所有 Claude Code 凭据条目，默认条目排在最前
    static func listEntries() -> [Entry] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status != errSecItemNotFound {
                Logger.settings.error("CLI sync: keychain enumeration failed, OSStatus \(status)")
            }
            return []
        }

        let entries: [Entry] = items.compactMap { item in
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(servicePrefix) else { return nil }
            let account = item[kSecAttrAccount as String] as? String ?? ""
            return Entry(service: service, account: account)
        }

        return entries.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.service < rhs.service
        }
    }

    // MARK: - 读取凭据

    /// 读取指定条目的凭据。`service` 为 nil 时按 listEntries 的顺序取第一个可用条目。
    /// - Note: 这一步会读机密数据，未授权时 macOS 会弹一次钥匙串授权框（用户点"总是允许"后不再弹）。
    static func readCredentials(service: String? = nil) -> ClaudeCodeCredentials? {
        let candidates: [Entry]
        if let service {
            candidates = listEntries().filter { $0.service == service }
        } else {
            candidates = listEntries()
        }

        for entry in candidates {
            if let credentials = readCredentials(entry: entry) {
                return credentials
            }
        }
        return nil
    }

    /// 读取某个具体条目
    static func readCredentials(entry: Entry) -> ClaudeCodeCredentials? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: entry.service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        if !entry.account.isEmpty {
            query[kSecAttrAccount as String] = entry.account
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            Logger.settings.error("CLI sync: failed to read keychain item, OSStatus \(status)")
            return nil
        }

        return parse(data: data, service: entry.service, account: entry.account)
    }

    /// 解析钥匙串条目里的 JSON
    static func parse(data: Data, service: String, account: String) -> ClaudeCodeCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else {
            Logger.settings.error("CLI sync: keychain payload is not in the expected claudeAiOauth shape")
            return nil
        }

        let accessToken = oauth["accessToken"] as? String ?? ""
        let refreshToken = oauth["refreshToken"] as? String ?? ""
        guard !accessToken.isEmpty || !refreshToken.isEmpty else {
            Logger.settings.error("CLI sync: keychain payload carries neither accessToken nor refreshToken")
            return nil
        }

        return ClaudeCodeCredentials(
            serviceName: service,
            accountName: account,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiryDate(from: oauth["expiresAt"]),
            scopes: oauth["scopes"] as? [String] ?? [],
            subscriptionType: oauth["subscriptionType"] as? String ?? ""
        )
    }

    /// Claude Code 写的 expiresAt 是毫秒时间戳；这里对秒/毫秒都做兼容
    /// （阈值 1e11 秒 ≈ 公元 5138 年，任何真实的秒级时间戳都在其下）
    private static func expiryDate(from raw: Any?) -> Date? {
        guard let number = raw as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 1e11 ? value / 1000 : value)
    }

    // MARK: - 写回轮换后的 token

    /// 把刷新后的 token 写回 Claude Code 的钥匙串条目。
    ///
    /// 为什么必须写回：refresh_token 在服务端是**一次性**的。我们用它换了新 token 之后，
    /// Claude Code 手里那份就失效了；不写回，用户的 CLI 会在下次刷新时被登出。
    /// 写回时保留条目里其余未知字段，避免抹掉 Claude Code 后续新增的键。
    /// - Returns: 是否写入成功（失败不致命，调用方只记日志）
    @discardableResult
    static func writeBack(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date?,
        to credentials: ClaudeCodeCredentials
    ) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentials.serviceName,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        if !credentials.accountName.isEmpty {
            query[kSecAttrAccount as String] = credentials.accountName
        }

        // 先取当前内容，保留 claudeAiOauth 之外/之内的其它字段
        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
        guard readStatus == errSecSuccess, let data = result as? Data,
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else {
            Logger.settings.error("CLI sync: could not re-read the keychain item before write-back, OSStatus \(readStatus)")
            return false
        }

        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        if let expiresAt {
            // Claude Code 用毫秒时间戳，写回要保持同一单位
            oauth["expiresAt"] = Int(expiresAt.timeIntervalSince1970 * 1000)
        }
        root["claudeAiOauth"] = oauth

        guard let newData = try? JSONSerialization.data(withJSONObject: root) else { return false }

        var updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentials.serviceName
        ]
        if !credentials.accountName.isEmpty {
            updateQuery[kSecAttrAccount as String] = credentials.accountName
        }

        let updateStatus = SecItemUpdate(
            updateQuery as CFDictionary,
            [kSecValueData as String: newData] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            Logger.settings.error("CLI sync: keychain write-back failed, OSStatus \(updateStatus)")
            return false
        }

        Logger.settings.notice("CLI sync: rotated tokens written back to the Claude Code keychain item")
        return true
    }
}
