//
//  WelcomeView.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// 首次启动欢迎界面
/// 单页流程，只提供 claude.ai 浏览器登录一条路径
/// 具体步骤内容拆到 SetupStepView.swift / WelcomeSupportingViews.swift，保持本文件体量可控
struct WelcomeView: View {
    /// 欢迎窗口的固定尺寸。
    /// 窗口创建处也用这个值设置 contentSize，两边必须一致，否则居中会算错。
    static let contentSize = NSSize(width: 300, height: 400)

    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // 内容区域
            SetupStepView(onSignedIn: finishSetup)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .id(localization.updateTrigger)
    }

    // MARK: - Navigation Methods

    /// 结束首次配置。
    /// OAuth 登录成功时账户已由 ClaudeOAuthCoordinator 落库，所以这里不再重复取
    /// Organization 建账户，只标记首次启动结束并触发一次刷新。
    /// 未登录直接点完成也走这里，等同于跳过，可稍后在设置里添加账户。
    private func finishSetup() {
        settings.isFirstLaunch = false

        // 发送通知以启动数据刷新
        NotificationCenter.default.post(name: .openSettings, object: nil)

        dismiss()
    }
}
