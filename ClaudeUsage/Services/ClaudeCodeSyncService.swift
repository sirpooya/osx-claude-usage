//
//  ClaudeCodeSyncService.swift
//  ClaudeUsage
//
//  "CLI Account Sync"：把 Claude Code CLI 已经登录好的账号直接接过来用，
//  用户不需要再粘 sessionKey、也不需要再走一遍浏览器 OAuth。
//
//  与手动/浏览器登录的关系：
//  - 三条路互不干扰，任一条配好即可出数据（同 Claude.ai cookie / API Console / CLI 三分法）。
//  - CLI 同步来的账户标 credentialSource == .claudeCodeCLI，取 token 时每次都重读钥匙串，
//    因为 Claude Code 自己会在我们背后轮换它。
//

import Combine
import Foundation
import OSLog

@MainActor
final class ClaudeCodeSyncService: ObservableObject {

    static let shared = ClaudeCodeSyncService()

    enum SyncState: Equatable {
        case notSynced
        case syncing
        case synced(at: Date)
        case failed(message: String)
    }

    // MARK: - Published

    @Published private(set) var state: SyncState = .notSynced
    /// 当前读到的凭据（界面只展示打码后的 token / 订阅类型 / scopes）
    @Published private(set) var credentials: ClaudeCodeCredentials?
    /// 机器上所有可用的 Claude Code 钥匙串条目
    @Published private(set) var availableEntries: [ClaudeCodeKeychain.Entry] = []

    /// 用户在"凭据来源"里锁定的钥匙串条目；nil 表示自动（默认条目优先）
    @Published var pinnedService: String? {
        didSet {
            guard pinnedService != oldValue else { return }
            if let pinnedService {
                UserDefaults.standard.set(pinnedService, forKey: Self.pinnedServiceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pinnedServiceKey)
            }
        }
    }

    private static let pinnedServiceKey = "cliSync.pinnedService"

    private init() {
        pinnedService = UserDefaults.standard.string(forKey: Self.pinnedServiceKey)
        availableEntries = ClaudeCodeKeychain.listEntries()
    }

    // MARK: - 查询

    /// 机器上是否存在 Claude Code 的凭据条目（只看条目在不在，不读机密数据，因此不会弹授权框）
    var isAvailable: Bool { !availableEntries.isEmpty }

    /// 当前已同步的 CLI 账户（如果有）
    var syncedAccount: Account? {
        UserSettings.shared.accounts.first { $0.credentialSource.isCLISynced }
    }

    var isSynced: Bool { syncedAccount != nil }

    /// 重新枚举钥匙串条目（"Refresh" 按钮 / 打开设置页时调用）
    func refreshEntries() {
        availableEntries = ClaudeCodeKeychain.listEntries()
    }

    // MARK: - 同步

    /// 启动时的静默同步：只在"还没有任何 CLI 账户、但机器上存在 CLI 凭据"时接管，
    /// 成功后调用方就不必再弹登录窗口了。
    /// - Returns: 是否成功建立了可用账户
    func syncOnLaunchIfNeeded() async -> Bool {
        refreshEntries()
        guard isAvailable else { return false }

        // 已有 CLI 账户：只把 token 对齐到钥匙串里的最新值，不重建账户
        if let existing = syncedAccount {
            realignStoredToken(for: existing)
            state = .synced(at: Date())
            return true
        }

        // 用户已经手动配好了 Claude 账户，就别擅自替换他的选择
        guard UserSettings.shared.accounts.isEmpty else { return false }

        return await sync()
    }

    /// 执行一次同步（首次接入 / "Re-sync" 按钮 / 换 pinned 条目）
    /// - Returns: 是否成功
    @discardableResult
    func sync() async -> Bool {
        state = .syncing
        refreshEntries()

        guard let credentials = readResolvedCredentials() else {
            self.credentials = nil
            state = .failed(message: L.CLISync.errorNoCredentials)
            Logger.settings.error("CLI sync: no readable Claude Code credentials found")
            return false
        }
        self.credentials = credentials

        guard !credentials.refreshToken.isEmpty else {
            // 只有 access_token 的条目撑不过一小时，拒绝建账户，免得用户以为配好了
            state = .failed(message: L.CLISync.errorNoRefreshToken)
            Logger.settings.error("CLI sync: keychain item has no refresh_token, refusing to create an account")
            return false
        }

        let profile = await fetchProfile(credentials: credentials)
        upsertAccount(credentials: credentials, profile: profile)
        state = .synced(at: Date())
        Logger.settings.notice("CLI sync: synced the Claude Code account from keychain service \(credentials.serviceName, privacy: .public)")
        return true
    }

    /// 解除同步：删掉 CLI 同步来的账户，并清空本服务状态。
    /// 只动我们自己的账户列表，绝不碰 Claude Code 的钥匙串条目。
    func removeSync() {
        if let account = syncedAccount {
            UserSettings.shared.removeAccount(account)
        }
        credentials = nil
        state = .notSynced
        Logger.settings.notice("CLI sync: removed the synced account (the Claude Code keychain item was left untouched)")
    }

    // MARK: - 供 API 层调用

    /// 读取当前应使用的 CLI 凭据（每次轮询都重读，不缓存 token）
    nonisolated static func currentCredentials(preferredService: String?) -> ClaudeCodeCredentials? {
        if let preferredService,
           let credentials = ClaudeCodeKeychain.readCredentials(service: preferredService) {
            return credentials
        }
        return ClaudeCodeKeychain.readCredentials()
    }

    // MARK: - Private

    /// 按 pinned 设置解析出该读哪个条目
    private func readResolvedCredentials() -> ClaudeCodeCredentials? {
        Self.currentCredentials(preferredService: pinnedService)
    }

    /// Claude Code 轮换 token 后，把账户里存的那份对齐过去，
    /// 避免我们拿着一个早已失效的 refresh_token 去刷新。
    private func realignStoredToken(for account: Account) {
        guard let credentials = Self.currentCredentials(preferredService: account.keychainService ?? pinnedService) else { return }
        self.credentials = credentials
        guard !credentials.refreshToken.isEmpty, credentials.refreshToken != account.sessionKey else { return }
        UserSettings.shared.silentlyUpdateCurrentClaudeSessionToken(credentials.refreshToken)
    }

    /// 拉 profile 补齐账户显示名，失败不阻断同步
    private func fetchProfile(credentials: ClaudeCodeCredentials) async -> (email: String, orgId: String, orgName: String)? {
        guard credentials.isAccessTokenUsable else { return nil }
        return await withCheckedContinuation { continuation in
            ClaudeOAuthService.fetchProfile(accessToken: credentials.accessToken) { result in
                switch result {
                case .success(let profile): continuation.resume(returning: profile)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 建立或更新 CLI 同步账户
    private func upsertAccount(
        credentials: ClaudeCodeCredentials,
        profile: (email: String, orgId: String, orgName: String)?
    ) {
        let settings = UserSettings.shared
        let email = profile?.email ?? ""
        let orgId = profile?.orgId ?? ""
        let displayName = email.isEmpty ? L.CLISync.defaultAccountName : email
        // 与浏览器 OAuth 登录保持同一去重标识：组织 uuid，缺失时退回 email，
        // 都没有就用钥匙串 service 名兜底（保证同一条目不会重复建号）
        let stableOrgId = !orgId.isEmpty ? orgId : (!email.isEmpty ? email : credentials.serviceName)

        // 同一标识的旧账户先移除（addAccount 遇到已存在的 organizationId 会直接跳过）
        if let existing = settings.accounts.first(where: {
            $0.organizationId == stableOrgId || $0.credentialSource.isCLISynced
        }) {
            settings.removeAccount(existing)
        }

        let account = Account(
            sessionKey: credentials.refreshToken,
            organizationId: stableOrgId,
            organizationName: displayName,
            alias: nil,
            provider: .claude,
            credentialSource: .claudeCodeCLI,
            keychainService: credentials.serviceName
        )
        settings.addAccount(account)
        settings.switchToAccount(account)
    }
}
