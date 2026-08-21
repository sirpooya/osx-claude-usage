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
// 单列表单布局：标题 / 浏览器登录 / 分隔线 / Session Key 输入 / 帮助链接

struct SetupStepView: View {
    @Binding var sessionKey: String
    @Binding var isShowingPassword: Bool
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            browserSignIn
            manualDivider
            sessionKeyField
            helpLink

            Spacer(minLength: 0)

            multiAccountFootnote
        }
        .padding(.horizontal, 32)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    /// 标题行
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.title3)
                .foregroundColor(.blue)
            Text(L.Welcome.authenticationSetup)
                .font(.headline)
        }
    }

    /// 浏览器登录按钮（首选路径，占满整行）
    private var browserSignIn: some View {
        Button(action: {
            WebLoginWindowManager.shared.showLoginWindow { account in
                // 登录成功后自动填充 sessionKey
                sessionKey = account.sessionKey
            }
        }) {
            Text(L.WebLogin.browserLoginRecommended)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    /// “或手动输入”分隔线
    private var manualDivider: some View {
        HStack(spacing: 10) {
            hairline
            Text(L.WebLogin.orManualInput)
                .font(.caption)
                .foregroundColor(.secondary)
                .layoutPriority(1)
            hairline
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 1)
    }

    /// Session Key 输入区：标签在输入框上方，输入框占满整行
    private var sessionKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.Welcome.sessionKey)
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                Group {
                    if isShowingPassword {
                        TextField(L.Welcome.sessionKeyPlaceholder, text: $sessionKey)
                    } else {
                        SecureField(L.Welcome.sessionKeyPlaceholder, text: $sessionKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Button(action: { isShowingPassword.toggle() }) {
                    Image(systemName: isShowingPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 提示语与校验结果共用同一行高度，避免输入时布局跳动
            statusLine
                .frame(height: 15, alignment: .leading)
        }
    }

    /// 输入框下方的状态行：未输入时显示提示，输入后显示校验结果
    @ViewBuilder
    private var statusLine: some View {
        if sessionKey.isEmpty {
            Text(L.Welcome.sessionKeyHint)
                .font(.caption)
                .foregroundColor(.secondary)
        } else if settings.isValidSessionKey(sessionKey) {
            Label(L.Welcome.validFormat, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        } else {
            Label(L.Welcome.invalidFormat, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    /// 帮助链接
    private var helpLink: some View {
        Button(action: {
            if let url = URL(string: getGitHubReadmeURL(section: .initialSetup)) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle")
                Text(L.Welcome.howToGetSessionKey)
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
    }

    /// 多账户提示：移到底部作为脚注，不再和标题抢同一行
    private var multiAccountFootnote: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
            Text(L.Welcome.multiAccountHint)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.secondary)
    }

    // MARK: - GitHub README URL Helper

    /// README 章节枚举
    private enum ReadmeSection {
        case initialSetup
        case faq
    }

    /// 根据当前语言生成 GitHub README URL
    /// - Parameter section: README 章节
    /// - Returns: 对应语言和章节的 GitHub README URL
    private func getGitHubReadmeURL(section: ReadmeSection) -> String {
        let baseURL = "https://github.com/f-is-h/Usage4Claude/blob/main"
        let language = settings.language

        switch language {
        case .english:
            let anchor = section == .initialSetup ? "#initial-setup" : "#-faq"
            return "\(baseURL)/README.md\(anchor)"

        case .german:
            let anchor = section == .initialSetup ? "#erste-konfiguration" : "#-faq"
            return "\(baseURL)/docs/README.de.md\(anchor)"

        case .chinese:
            let anchor = section == .initialSetup ? "#首次配置" : "#-常见问题"
            return "\(baseURL)/docs/README.zh-CN.md\(anchor)"

        case .chineseTraditional:
            let anchor = section == .initialSetup ? "#首次設定" : "#-常見問題"
            return "\(baseURL)/docs/README.zh-TW.md\(anchor)"

        case .japanese:
            let anchor = section == .initialSetup ? "#初期設定" : "#-よくある質問"
            return "\(baseURL)/docs/README.ja.md\(anchor)"

        case .korean:
            let anchor = section == .initialSetup ? "#초기-설정" : "#-자주-묻는-질문"
            return "\(baseURL)/docs/README.ko.md\(anchor)"

        case .french:
            let anchor = section == .initialSetup ? "#configuration-initiale" : "#-faq"
            return "\(baseURL)/docs/README.fr.md\(anchor)"
        }
    }
}
