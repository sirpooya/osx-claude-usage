//
//  ManualSessionKeyView.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2026-08-21.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Manual Session Key (登录窗口的第二页)

/// 手动粘贴 Session Key 的进阶入口。
/// 主页面只放浏览器登录，这一页从主页面的次要按钮进来，左上角带返回。
struct ManualSessionKeyView: View {
    @Binding var sessionKey: String
    @Binding var isShowingPassword: Bool
    /// 正在校验 Session Key 并创建账户
    let isSubmitting: Bool
    /// 校验失败的提示，nil 表示没有错误
    let errorMessage: String?
    let onBack: () -> Void
    let onSubmit: () -> Void

    @ObservedObject private var settings = UserSettings.shared

    private var canSubmit: Bool {
        !sessionKey.isEmpty && settings.isValidSessionKey(sessionKey) && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton

            Spacer().frame(height: 16)

            Text(L.Welcome.manualSessionKey)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 16)

            Text(L.Welcome.sessionKey)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer().frame(height: 6)

            keyField

            Spacer().frame(height: 6)

            // 提示语与校验结果共用一行高度，避免输入时布局跳动
            statusLine
                .frame(height: 15, alignment: .leading)

            Spacer().frame(height: 12)

            helpLink

            Spacer(minLength: 12)

            if let errorMessage {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundColor(.orange)

                Spacer().frame(height: 10)
            }

            submitButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                Text(L.Welcome.back)
            }
            .font(.callout)
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    private var keyField: some View {
        HStack(spacing: 8) {
            Group {
                if isShowingPassword {
                    TextField(L.Welcome.sessionKeyPlaceholder, text: $sessionKey)
                } else {
                    SecureField(L.Welcome.sessionKeyPlaceholder, text: $sessionKey)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
            .disabled(isSubmitting)

            Button(action: { isShowingPassword.toggle() }) {
                Image(systemName: isShowingPassword ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

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
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var helpLink: some View {
        Button(action: {
            if let url = URL(string: WelcomeDocLinks.initialSetupURL(for: settings.language)) {
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

    private var submitButton: some View {
        Button(action: onSubmit) {
            HStack(spacing: 6) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                    Text(L.Welcome.configuring)
                } else {
                    Text(L.Welcome.finish)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(UsageColorScheme.brand)
        .disabled(!canSubmit)
    }
}
