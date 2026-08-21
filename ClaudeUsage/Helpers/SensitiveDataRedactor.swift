//
//  SensitiveDataRedactor.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-01.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// 敏感数据脱敏工具
/// 提供统一的敏感信息脱敏方法，用于日志记录和诊断报告
/// 支持 Organization ID、Session Key 和文本中的敏感信息脱敏
class SensitiveDataRedactor {
    // MARK: - Public Methods

    /// 脱敏 Organization ID
    /// - Parameter id: 原始 Organization ID
    /// - Returns: 脱敏后的字符串
    /// - Note: 对于短于8位的ID，全部替换为星号；否则保留前4位和后4位
    /// - Example: "12345678-1234-1234-1234-123456789012" -> "1234...9012"
    static func redactOrganizationId(_ id: String) -> String {
        guard id.count > 8 else {
            return String(repeating: "*", count: id.count)
        }
        let prefix = id.prefix(4)
        let suffix = id.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    /// 脱敏 Session Key
    /// - Parameter key: 原始 Session Key
    /// - Returns: 脱敏后的字符串
    /// - Note: 对于 sk-ant- 开头的 key，保留前缀并显示长度；其他情况返回 "***"
    /// - Example: "sk-ant-sid...XXXXX" -> "sk-ant-***...*** (128 chars)"
    static func redactSessionKey(_ key: String) -> String {
        guard key.count > 20 else {
            return "***"
        }

        // 保留前缀 "sk-ant-"
        if key.hasPrefix("sk-ant-") {
            return "sk-ant-***...*** (\(key.count) chars)"
        }

        // 其他格式的 key
        return "***...*** (\(key.count) chars)"
    }

    /// 脱敏 Codex Session Token（JWE 长串）
    /// - Parameter token: __Secure-next-auth.session-token 的值
    /// - Returns: 脱敏后的字符串，保留前8位和后4位
    static func redactCodexSessionToken(_ token: String) -> String {
        guard token.count > 12 else {
            return String(repeating: "*", count: token.count)
        }
        return "\(token.prefix(8))...\(token.suffix(4)) (\(token.count) chars)"
    }

    /// 脱敏 JWT Access Token（三段式 header.payload.signature）
    /// - Parameter token: Bearer accessToken 字符串
    /// - Returns: 脱敏后的字符串，每段只保留前6字符
    static func redactAccessToken(_ token: String) -> String {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            guard token.count > 12 else { return "***" }
            return "\(token.prefix(8))...\(token.suffix(4)) (\(token.count) chars)"
        }
        let h = String(parts[0].prefix(6))
        let p = String(parts[1].prefix(6))
        let s = String(parts[2].prefix(6))
        return "\(h)...\(p)...\(s)... (\(token.count) chars)"
    }

    /// 脱敏文本中的敏感信息
    /// 使用正则表达式查找并替换文本中的 Organization ID 和 Session Key
    /// - Parameter text: 包含敏感信息的原始文本
    /// - Returns: 脱敏后的文本
    /// - Note: 用于日志和诊断输出，自动识别并脱敏常见格式
    static func redactText(_ text: String) -> String {
        var sanitized = text

        // 脱敏 Session Key (保留前4位和后4位)
        // 匹配模式: sessionKey=xxx 或 sessionKey: xxx
        let sessionKeyPattern = "sessionKey[=:]\\s*[\"']?([a-zA-Z0-9-]{20,})[\"']?"
        if let regex = try? NSRegularExpression(pattern: sessionKeyPattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "sessionKey=***REDACTED***"
            )
        }

        // 脱敏 Organization ID (UUID 格式)
        // 匹配模式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        let orgIdPattern = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        if let regex = try? NSRegularExpression(pattern: orgIdPattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "********-****-****-****-************"
            )
        }

        // 脱敏 Cookie 中的 sessionKey
        // 匹配模式: Cookie: sessionKey=xxx
        let cookiePattern = "Cookie:\\s*sessionKey=([a-zA-Z0-9-]{20,})"
        if let regex = try? NSRegularExpression(pattern: cookiePattern, options: .caseInsensitive) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "Cookie: sessionKey=***REDACTED***"
            )
        }

        // 脱敏裸 token。
        //
        // 上面几条都要求 token 前面带 sessionKey= / Cookie: 这类标签，
        // 但日志里最常见的其实是没有标签的裸串：异常 reason、URL、错误
        // 描述里直接带出一个 sk-ant-...。少了这一条，"永不记录 token"
        // 这条规则实际上是漏的。
        let bareTokenPatterns = [
            // Anthropic key / OAuth token: sk-ant-*
            "sk-ant-[A-Za-z0-9_-]{8,}",
            // Authorization: Bearer <任意长串>
            "(?i)(bearer)\\s+[A-Za-z0-9._~+/=-]{12,}",
            // JWT 三段式，Codex 的 session token 是这个形状
            "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{4,}",
            // OAuth refresh / access token 字段
            "(?i)(access_token|refresh_token|accessToken|refreshToken)[\"']?\\s*[=:]\\s*[\"']?[A-Za-z0-9._~+/=-]{12,}",
        ]
        for pattern in bareTokenPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            // $1 保留标签（Bearer / access_token），只吃掉后面的值，
            // 这样日志还能看出是哪种凭据出了问题。
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "$1***REDACTED***"
            )
        }

        return sanitized
    }
}
