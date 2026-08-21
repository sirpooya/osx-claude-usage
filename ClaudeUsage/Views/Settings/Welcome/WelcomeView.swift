//
//  WelcomeView.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// 首次启动欢迎界面
/// 单页流程：直接进入所有设置（认证 + 主题 + 预览），不再有单独的欢迎页
/// 具体步骤内容拆到 SetupStepView.swift / WelcomeSupportingViews.swift，保持本文件体量可控
struct WelcomeView: View {
    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared
    @State private var sessionKey: String = ""
    @State private var isShowingPassword: Bool = false
    @State private var isFetchingOrgId: Bool = false
    @State private var fetchError: String?

    var body: some View {
        VStack(spacing: 0) {
            // 内容区域
            SetupStepView(
                sessionKey: $sessionKey,
                isShowingPassword: $isShowingPassword
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部导航按钮
            NavigationButtons(
                canProceed: canProceed,
                isFetchingOrgId: isFetchingOrgId,
                fetchError: fetchError,
                onSkip: skipSetup,
                onComplete: completeSetup
            )
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .frame(width: 550, height: 600)
        .id(localization.updateTrigger)
    }

    // MARK: - Computed Properties

    private var canProceed: Bool {
        !sessionKey.isEmpty && settings.isValidSessionKey(sessionKey)
    }

    // MARK: - Navigation Methods

    private func skipSetup() {
        settings.isFirstLaunch = false
        dismiss()
    }

    private func completeSetup() {
        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // 显示加载状态
        isFetchingOrgId = true
        fetchError = nil

        // 获取 Organization ID 并创建账户
        fetchOrganizationAndCreateAccount(sessionKey: trimmedKey) { success in
            DispatchQueue.main.async {
                isFetchingOrgId = false

                if success {
                    // 获取成功，标记首次启动完成
                    settings.isFirstLaunch = false

                    // 发送通知以启动数据刷新
                    NotificationCenter.default.post(name: .openSettings, object: nil)

                    // 关闭窗口
                    dismiss()
                } else {
                    // 获取失败，显示错误但不阻止用户继续
                    // 用户可以稍后在设置中重新配置
                    fetchError = L.Welcome.fetchOrgIdFailed

                    // 3秒后自动关闭错误提示并继续
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        settings.isFirstLaunch = false
                        dismiss()
                    }
                }
            }
        }
    }

    /// 获取 Organization 并创建账户
    /// - Parameters:
    ///   - sessionKey: Session Key
    ///   - completion: 完成回调，返回是否成功
    private func fetchOrganizationAndCreateAccount(sessionKey: String, completion: @escaping (Bool) -> Void) {
        let apiService = ClaudeAPIService.shared
        apiService.fetchOrganizations(sessionKey: sessionKey) { result in
            switch result {
            case .success(let organizations):
                if !organizations.isEmpty {
                    DispatchQueue.main.async {
                        for org in organizations {
                            let newAccount = Account(
                                sessionKey: sessionKey,
                                organizationId: org.uuid,
                                organizationName: org.name,
                                alias: nil
                            )
                            settings.addAccount(newAccount)
                        }
                    }
                    completion(true)
                } else {
                    completion(false)
                }
            case .failure:
                completion(false)
            }
        }
    }

}

