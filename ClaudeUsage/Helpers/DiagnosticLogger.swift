//
//  DiagnosticLogger.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-11.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// 诊断日志记录器
/// 提供详细的运行时日志，帮助追踪和诊断问题
@MainActor
class DiagnosticLogger {

    // MARK: - Singleton

    static let shared = DiagnosticLogger()

    // MARK: - Properties

    /// 日志级别
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// 日志文件URL
    private var logFileURL: URL?

    /// 日志队列（用于异步写入）
    private let logQueue = DispatchQueue(label: "com.f-is-h.ClaudeUsage.logging", qos: .utility)

    /// 最大日志文件大小（5MB）
    private let maxLogFileSize: UInt64 = 5 * 1024 * 1024

    /// 是否启用日志记录
    private var isEnabled: Bool = true

    /// 系统日志器
    private let osLogger = Logger(subsystem: "com.f-is-h.ClaudeUsage", category: "Diagnostics")

    // MARK: - Initialization

    private init() {
        setupLogFile()
    }

    // MARK: - Public Methods

    /// 记录调试信息
    func debug(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .debug, file: file, line: line, function: function)
    }

    /// 记录一般信息
    func info(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .info, file: file, line: line, function: function)
    }

    /// 记录警告信息
    func warning(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .warning, file: file, line: line, function: function)
    }

    /// 记录错误信息
    func error(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, level: .error, file: file, line: line, function: function)
    }

    /// 获取日志文件路径
    func getLogFilePath() -> String? {
        return logFileURL?.path
    }

    /// 读取日志内容
    func readLogs(maxLines: Int = 1000) -> String {
        guard let logFileURL = logFileURL,
              FileManager.default.fileExists(atPath: logFileURL.path) else {
            return "No logs available"
        }

        do {
            let content = try String(contentsOf: logFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            let recentLines = lines.suffix(maxLines)
            return recentLines.joined(separator: "\n")
        } catch {
            return "Error reading logs: \(error.localizedDescription)"
        }
    }

    /// 清空日志
    func clearLogs() {
        guard let logFileURL = logFileURL else { return }

        logQueue.async {
            do {
                try "".write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                self.osLogger.error("Failed to clear logs: \(error.localizedDescription)")
            }
        }
    }

    /// 导出日志文件
    func exportLogs() -> URL? {
        return logFileURL
    }

    // MARK: - Private Methods

    /// 设置日志文件
    private func setupLogFile() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            osLogger.error("Failed to get Application Support directory")
            return
        }

        let logDirectory = appSupport.appendingPathComponent("ClaudeUsage/logs")

        // 创建日志目录
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            osLogger.error("Failed to create log directory: \(error.localizedDescription)")
            return
        }

        // 设置日志文件路径
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFileURL = logDirectory.appendingPathComponent("claudeusage_\(dateString).log")

        // 检查并轮转日志
        checkAndRotateLogIfNeeded()
    }

    /// 核心日志记录方法
    private func log(_ message: String, level: LogLevel, file: String, line: Int, function: String) {
        guard isEnabled else { return }

        // Release 版本丢弃 debug，但保留 info。
        //
        // 原先这里把 info 也一起丢掉，结果是 Release 版本在崩溃或被杀之前
        // 没有任何面包屑可看，而“突然退出”恰恰只发生在 Release 版本上。
        // info 已经经过脱敏，量也有限（每次轮询几行），保留它才能看出退出
        // 前应用正在做什么。
        #if !DEBUG
        guard level != .debug else { return }
        #endif

        // 脱敏处理
        let sanitizedMessage = sanitize(message)

        // 提取文件名
        let fileName = (file as NSString).lastPathComponent

        // 构建日志消息
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(sanitizedMessage)\n"

        // 输出到控制台（仅在Debug模式）
        #if DEBUG
        print(logMessage, terminator: "")
        #endif

        // 输出到系统日志
        osLogger.log(level: osLogLevel(for: level), "\(sanitizedMessage)")

        // warning 和 error 同步落盘，其余异步。
        //
        // 异步写入配合 .utility 队列意味着进程被杀时队列里的内容全部丢失，
        // 而丢掉的恰好是崩溃前最后几行。所以严重级别走同步路径并 fsync：
        // 代价是每条几毫秒，换来的是这几行一定在磁盘上。
        let needsDurability = (level == .warning || level == .error)
        writeToFile(logMessage, synchronous: needsDurability)
    }

    /// 立即把待写日志刷到磁盘。
    /// 在已知即将退出的时刻调用（applicationWillTerminate），确保尾部不丢。
    func flush() {
        logQueue.sync { }
    }

    /// 写入日志到文件
    /// - Parameter synchronous: true 时阻塞到内容 fsync 落盘，用于崩溃前必须
    ///   保留的严重日志
    private func writeToFile(_ message: String, synchronous: Bool = false) {
        guard let logFileURL = logFileURL else { return }

        let work = {
            do {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    // 文件存在，追加内容
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    defer { try? fileHandle.close() }

                    try fileHandle.seekToEnd()
                    if let data = message.data(using: .utf8) {
                        try fileHandle.write(contentsOf: data)
                    }
                    if synchronous {
                        // 越过文件系统缓存。没有这一步，进程被 SIGKILL 时
                        // 内容仍在内核缓冲区里，磁盘上什么都没有。
                        try fileHandle.synchronize()
                    }
                } else {
                    // 文件不存在，创建新文件
                    try message.write(to: logFileURL, atomically: true, encoding: .utf8)
                }

                // 检查文件大小
                Task { @MainActor in
                    self.checkAndRotateLogIfNeeded()
                }
            } catch {
                self.osLogger.error("Failed to write log: \(error.localizedDescription)")
            }
        }

        if synchronous {
            logQueue.sync(execute: work)
        } else {
            logQueue.async(execute: work)
        }
    }

    /// 检查并轮转日志文件
    private func checkAndRotateLogIfNeeded() {
        guard let logFileURL = logFileURL else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            if let fileSize = attributes[.size] as? UInt64, fileSize > maxLogFileSize {
                // 文件过大，进行轮转
                rotateLog()
            }
        } catch {
            // 文件不存在或无法读取，忽略
        }
    }

    /// 轮转日志文件
    private func rotateLog() {
        guard let logFileURL = logFileURL else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let archiveURL = logFileURL.deletingLastPathComponent()
            .appendingPathComponent("claudeusage_\(timestamp).log.old")

        do {
            // 重命名当前日志文件
            try FileManager.default.moveItem(at: logFileURL, to: archiveURL)

            // 删除旧的归档文件（保留最近5个）
            cleanupOldLogs()
        } catch {
            osLogger.error("Failed to rotate log: \(error.localizedDescription)")
        }
    }

    /// 清理旧日志文件
    private func cleanupOldLogs() {
        guard let logFileURL = logFileURL else { return }

        let logDirectory = logFileURL.deletingLastPathComponent()

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: logDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            // 只保留.old文件
            let oldLogs = fileURLs.filter { $0.pathExtension == "old" }

            // 按创建时间排序
            let sortedLogs = try oldLogs.sorted { url1, url2 in
                let date1 = try url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 > date2
            }

            // 删除超过5个的旧日志
            if sortedLogs.count > 5 {
                for logURL in sortedLogs.dropFirst(5) {
                    try FileManager.default.removeItem(at: logURL)
                }
            }
        } catch {
            osLogger.error("Failed to cleanup old logs: \(error.localizedDescription)")
        }
    }

    /// 脱敏敏感信息
    private func sanitize(_ message: String) -> String {
        // 使用统一的敏感数据脱敏工具
        return SensitiveDataRedactor.redactText(message)
    }

    /// 转换为系统日志级别
    private func osLogLevel(for level: LogLevel) -> OSLogType {
        switch level {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}

// MARK: - Convenience Global Functions

/// 全局便捷日志函数
@MainActor
func logDebug(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.debug(message, file: file, line: line, function: function)
}

@MainActor
func logInfo(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.info(message, file: file, line: line, function: function)
}

@MainActor
func logWarning(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.warning(message, file: file, line: line, function: function)
}

@MainActor
func logError(_ message: String, file: String = #file, line: Int = #line, function: String = #function) {
    DiagnosticLogger.shared.error(message, file: file, line: line, function: function)
}
