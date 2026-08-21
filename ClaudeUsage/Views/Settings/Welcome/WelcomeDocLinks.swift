//
//  WelcomeDocLinks.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2026-08-21.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

// MARK: - Welcome Doc Links

/// 按当前语言拼出上游 README 的锚点链接。
/// 注意仓库名是 Usage4Claude（上游）；本 fork 改名后曾经指向不存在的 f-is-h/ClaudeUsage，
/// 那些链接全是 404。等本 fork 有了自己的仓库和文档，这里要一起改。
enum WelcomeDocLinks {
    private static let baseURL = "https://github.com/f-is-h/Usage4Claude/blob/main"

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
