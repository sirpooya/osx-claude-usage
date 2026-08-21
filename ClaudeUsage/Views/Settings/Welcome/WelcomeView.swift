//
//  WelcomeView.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// 首次启动登录界面
/// 两页：主页面只放 claude.ai 浏览器登录，第二页是进阶的手动 Session Key，带返回。
/// 页面内容拆到 SetupStepView.swift / ManualSessionKeyView.swift，保持本文件体量可控
struct WelcomeView: View {
    /// 登录窗口的固定尺寸。
    /// 窗口创建处也用这个值设置 contentSize，两边必须一致，否则居中会算错。
    static let contentSize = NSSize(width: 300, height: 400)

    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared

    /// 是否停在手动 Session Key 那一页
    @State private var showManualEntry = false
    @State private var sessionKey: String = ""
    @State private var isShowingPassword: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?

    var body: some View {
        Group {
            if showManualEntry {
                ManualSessionKeyView(
                    sessionKey: $sessionKey,
                    isShowingPassword: $isShowingPassword,
                    isSubmitting: isSubmitting,
                    errorMessage: submitError,
                    onBack: leaveManualEntry,
                    onSubmit: submitSessionKey
                )
            } else {
                SetupStepView(
                    onSignedIn: finishSetup,
                    onManualEntry: { showManualEntry = true }
                )
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .animation(.easeInOut(duration: 0.18), value: showManualEntry)
        .id(localization.updateTrigger)
    }

    // MARK: - Navigation Methods

    /// 返回主页面。保留已经输入的 Session Key，只清掉错误提示。
    private func leaveManualEntry() {
        submitError = nil
        showManualEntry = false
    }

    /// 结束首次配置。
    /// OAuth 登录成功时账户已由 ClaudeOAuthCoordinator 落库，所以那条路径不用再建账户。
    /// 关掉窗口同样会走到这里（见 showWelcomeWindow 里的 willClose），等同于稍后再配。
    private func finishSetup() {
        settings.isFirstLaunch = false

        // 发送通知以启动数据刷新
        NotificationCenter.default.post(name: .openSettings, object: nil)

        dismiss()
    }

    /// 手动路径：Session Key 只是凭据，账户要靠它去查 Organization 才能建出来。
    /// 失败时留在本页显示错误，让用户改，而不是直接关窗。
    private func submitSessionKey() {
        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        submitError = nil

        ClaudeAPIService.shared.fetchOrganizations(sessionKey: trimmedKey) { result in
            DispatchQueue.main.async {
                isSubmitting = false

                switch result {
                case .success(let organizations) where !organizations.isEmpty:
                    for org in organizations {
                        let newAccount = Account(
                            sessionKey: trimmedKey,
                            organizationId: org.uuid,
                            organizationName: org.name,
                            alias: nil
                        )
                        settings.addAccount(newAccount)
                    }
                    finishSetup()

                case .success, .failure:
                    submitError = L.Welcome.fetchOrgIdFailed
                }
            }
        }
    }
}
