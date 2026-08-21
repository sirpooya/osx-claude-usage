//
//  SetupStepView.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Setup Step (Authentication)
// 从 WelcomeView.swift 拆出，便于保持单文件体量可控
// 首次配置只保留一条路径：用 claude.ai 账户通过浏览器登录。
// 版式为标准的欢迎窗：图标 / 标题 / 一句话卖点 / 单个主操作 / 一行说明。
// 手动粘贴 Session Key 的入口已移除，需要多账户可在设置里添加。

struct SetupStepView: View {
    /// 登录成功后的回调。账户已由 ClaudeOAuthCoordinator 写入设置，这里只负责收尾。
    let onSignedIn: () -> Void
    /// 进入手动填 Session Key 的第二页
    let onManualEntry: () -> Void

    /// 标题取 App 自身的名字，改名后不用再同步文案
    private var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "ClaudeUsage"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 只留中间一个可伸缩的 Spacer，上下用固定间距：
            // 标题区贴近顶部，操作区贴近底部，富余空间集中在中间。
            Spacer().frame(height: 26)

            appMark

            Spacer().frame(height: 14)

            Text(appName)
                .font(.system(size: 22, weight: .semibold))

            Spacer().frame(height: 5)

            Text(L.Welcome.tagline)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 20)

            browserSignIn

            Spacer().frame(height: 10)

            manualEntryButton

            Spacer().frame(height: 12)

            Text(L.Welcome.signInNote)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 22)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sections

    /// App 图标。AppIcon 的兜底逻辑收敛在 ImageHelper.namedImage 里。
    @ViewBuilder
    private var appMark: some View {
        if let icon = ImageHelper.createAppIcon(size: 72) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 72, height: 72)
        }
    }

    /// 浏览器登录按钮（唯一入口，占满整行）
    private var browserSignIn: some View {
        Button(action: {
            WebLoginWindowManager.shared.showLoginWindow { _ in
                onSignedIn()
            }
        }) {
            Text(L.WebLogin.browserLoginRecommended)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(UsageColorScheme.brand)
    }

    /// 次要入口：进阶用户手动粘贴 Session Key，内容在第二页
    private var manualEntryButton: some View {
        Button(action: onManualEntry) {
            Text(L.Welcome.manualSessionKey)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.black)
    }
}
