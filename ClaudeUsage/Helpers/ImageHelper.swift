//
//  ImageHelper.swift
//  ClaudeUsage
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit

/// 图像处理辅助工具
/// 提供应用图标创建、缓存等功能
enum ImageHelper {
    // MARK: - Named Image Lookup

    /// 按名字取资源图片。
    /// 注意 "AppIcon" 是 appiconset：actool 只把它编译成图标数据，不会生成同名图片资源，
    /// 所以 NSImage(named: "AppIcon") 恒为 nil（弹窗标题、关于页、账户行、彩色菜单栏
    /// 图标都因此拿不到图，只能退到占位图形）。这里兜底读 Bundle 自身的图标，
    /// 拿到的就是 Finder 里显示的那一张。
    static func namedImage(_ name: String) -> NSImage? {
        if let image = NSImage(named: name) { return image }
        guard name == "AppIcon" else { return nil }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    // MARK: - App Icon

    /// 创建应用图标（非模板模式）
    /// - Parameter size: 图标大小
    /// - Returns: 指定大小的应用图标，如果无法加载则返回 nil
    static func createAppIcon(size: CGFloat) -> NSImage? {
        guard let appIcon = namedImage("AppIcon") else { return nil }
        guard let iconCopy = appIcon.copy() as? NSImage else { return nil }
        iconCopy.isTemplate = false
        iconCopy.size = NSSize(width: size, height: size)
        return iconCopy
    }

    /// 创建应用图标（非模板模式，指定宽高）
    /// - Parameters:
    ///   - width: 图标宽度
    ///   - height: 图标高度
    /// - Returns: 指定尺寸的应用图标，如果无法加载则返回 nil
    static func createAppIcon(width: CGFloat, height: CGFloat) -> NSImage? {
        guard let appIcon = namedImage("AppIcon") else { return nil }
        guard let iconCopy = appIcon.copy() as? NSImage else { return nil }
        iconCopy.isTemplate = false
        iconCopy.size = NSSize(width: width, height: height)
        return iconCopy
    }

    // MARK: - Codex Icon

    static func createCodexIcon(size: CGFloat) -> NSImage? {
        createSquareIcon(named: "CodexIcon", size: size, isTemplate: false, sourceInset: 2)
    }

    /// 从资源中创建正方形图标。部分透明 PNG 的边缘 RGB 不是透明白，
    /// 直接缩放时会被 AppKit 采样成细暗线，因此这里先居中裁方并略微内收。
    static func createSquareIcon(named name: String, size: CGFloat, isTemplate: Bool, sourceInset: CGFloat = 0) -> NSImage? {
        guard let source = namedImage(name) else { return nil }
        let targetSize = NSSize(width: size, height: size)
        let image = NSImage(size: targetSize)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        let sourceSize = source.size
        let side = min(sourceSize.width, sourceSize.height) - sourceInset * 2
        let cropRect = NSRect(
            x: (sourceSize.width - side) / 2,
            y: (sourceSize.height - side) / 2,
            width: side,
            height: side
        )

        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: cropRect,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: false,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        )
        image.unlockFocus()
        image.isTemplate = isTemplate
        return image
    }

    // MARK: - System Images

    /// 创建系统符号图像
    /// - Parameters:
    ///   - systemName: SF Symbols 名称
    ///   - size: 图像大小
    ///   - weight: 符号粗细
    /// - Returns: 创建的系统图像，如果无法加载则返回 nil
    static func createSystemImage(
        systemName: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
