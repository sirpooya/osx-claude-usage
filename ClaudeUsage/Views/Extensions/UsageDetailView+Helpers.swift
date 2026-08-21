//
//  UsageDetailView+Helpers.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Helper Methods Extension

extension UsageDetailView {

    // MARK: - Animation Methods

    /// 启动旋转动画
    func startRotationAnimation() {
        // 清除旧的定时器
        stopRotationAnimation()

        // 重置角度
        rotationAngle = 0

        // 创建新的定时器，每 0.016 秒更新一次（约 60fps）
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            withAnimation(.linear(duration: 0.016)) {
                rotationAngle += 6  // 每帧旋转 6 度，1秒完成一圈
                if rotationAngle >= 360 {
                    rotationAngle -= 360
                }
            }
        }
    }

    /// 停止旋转动画
    func stopRotationAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        withAnimation(.default) {
            rotationAngle = 0
        }
    }

    // MARK: - Text Helper Methods

    /// 创建彩虹文字
    /// - Parameter text: 要显示的文本
    /// - Returns: 带彩虹效果的文本视图
    @ViewBuilder
    func rainbowText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(
                LinearGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    /// 创建菜单更新文本（部分文字带颜色）
    /// - Returns: 带颜色的AttributedString
    func createUpdateMenuText() -> AttributedString {
        let baseText = L.Menu.checkUpdates
        let badgeText = L.Update.Notification.badgeShort
        let fullText = baseText + "   " + badgeText

        var attributedString = AttributedString(fullText)

        // 找到徽章文本的范围并设置颜色
        if let range = attributedString.range(of: badgeText) {
            attributedString[range].foregroundColor = .orange
        }

        return attributedString
    }
}
