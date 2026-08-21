//
//  SettingSection.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2026-08-22.
//

import SwiftUI

/// The General tab's grouped section, in the osx-launchpad / osx-download-manager settings look:
/// a medium section header sitting *above* a rounded card, with the explanatory hint below it.
///
/// Deliberately separate from `SettingCard`, which the Authentication tab still uses: those panes
/// follow the competitor-derived contract in `CredentialsChrome.swift` (in-card title plus a
/// subtitle line), so restyling the shared component would have dragged that layout along too.
///
/// Metrics are copied from launchpad's `SettingsComponents` and match `AboutView`'s private
/// pieces, so all three read as one system: radius 12 continuous, a `labelColor` 0.05 fill that
/// tracks appearance and the increase-contrast setting, and a 12pt row inset that the header and
/// hint align to rather than to the card's edge.
struct SettingSection<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let hint: String
    @ViewBuilder let content: Content

    /// `icon` / `iconColor` are accepted and ignored, exactly as `SettingCard` does, so moving a
    /// call site between the two needs no edit. The header glyphs were dropped from this tab.
    init(
        icon: String,
        iconColor: Color = .blue,
        title: String,
        hint: String = "",
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .padding(.leading, Self.rowInset)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.horizontal, Self.rowInset)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // `.continuous` is the squircle curve; at radius 12 it reads as a smooth corner
                // rather than a tight arc.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .labelColor).opacity(0.05))
            )

            if !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Self.rowInset)
            }
        }
    }

    /// Horizontal inset shared by the card's content, the header and the hint, so all three
    /// line up on one left edge.
    static var rowInset: CGFloat { 12 }
}

/// Hairline separator for use between rows inside a `SettingSection`.
///
/// A plain rectangle, not `Divider()`: the system separator draws under any overlay tint and its
/// colour cannot be lightened, so the exact hairline is set here instead.
struct SettingSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }
}
