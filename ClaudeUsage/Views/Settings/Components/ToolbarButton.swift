//
//  ToolbarButton.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// One settings tab item: glyph over a caption, with a rounded selection pill.
///
/// Matches the toolbar style shared by osx-download-manager / osx-launchpad / osx-auth-qr:
/// the selected item is accent-tinted (icon and label together) over a barely-there neutral
/// pill. Items hug their intrinsic width (plus a minWidth floor) rather than splitting the
/// bar evenly, so the gap between items is the one the spacing actually says.
struct ToolbarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, 9)
            .frame(minWidth: 52)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.05)
                          : (isHovering ? Color.primary.opacity(0.035) : .clear))
            )
            // A .frame alone is not hit-testable; the gap around the glyph would swallow clicks.
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .focusable(false)
    }
}
