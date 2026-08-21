//
//  WelcomeDocLinks.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2026-08-21.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

// MARK: - Welcome Doc Links

/// 按当前语言拼出本仓库 README 的锚点链接。
/// 指向 sirpooya/osx-claude-usage 自己的文档，不再指向上游 f-is-h/Usage4Claude。
/// 每个语言的锚点都对应 README 里真实存在的小节标题，改标题时这里要一起改。
enum WelcomeDocLinks {
    private static let baseURL = "https://github.com/sirpooya/osx-claude-usage/blob/main"

    /// “首次配置”章节
    static func initialSetupURL(for language: AppLanguage) -> String {
        switch language {
        case .english:
            return "\(baseURL)/README.md#initial-setup"
        case .german:
            return "\(baseURL)/docs/README.de.md#erste-konfiguration"
        case .chinese:
            return "\(baseURL)/docs/README.zh-CN.md#首次配置"
        case .chineseTraditional:
            return "\(baseURL)/docs/README.zh-TW.md#首次設定"
        case .japanese:
            return "\(baseURL)/docs/README.ja.md#初期設定"
        case .korean:
            return "\(baseURL)/docs/README.ko.md#초기-설정"
        case .french:
            return "\(baseURL)/docs/README.fr.md#configuration-initiale"
        }
    }
}
