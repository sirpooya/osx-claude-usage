//
//  CodexColumnView.swift
//  ClaudeUsage
//
//  Created by f-is-h on 2026-04-27.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Codex 用量列视图（双 Provider 模式右列）
struct CodexColumnView: View {
    let codexUsageData: CodexUsageData
    @Binding var showRemainingMode: Bool
    let refreshState: RefreshState
    var onToggleRemainingMode: (() -> Void)?

    private var activeCodexTypes: [LimitType] {
        UserSettings.shared.getActiveDisplayTypes(usageData: nil, codexUsageData: codexUsageData)
            .filter { $0.provider == .codex }
    }

    private var isCodexRefreshing: Bool {
        refreshState.isRefreshingProvider(.codex)
    }

    // MARK: - Body

    var body: some View {
        // 每条限制一行整宽进度条，与 Claude 列同一套布局
        VStack(spacing: 12) {
            ForEach(activeCodexTypes, id: \.self) { type in
                UnifiedLimitRow(
                    type: type,
                    codexData: codexUsageData,
                    showRemainingMode: showRemainingMode,
                    isRefreshing: isCodexRefreshing
                )
            }
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleRemainingMode?()
        }
    }
}
