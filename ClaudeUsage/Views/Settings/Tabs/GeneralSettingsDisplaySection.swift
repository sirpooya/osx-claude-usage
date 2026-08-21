//
//  GeneralSettingsDisplaySection.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// The "display settings" card on the general settings page: the menu bar icon style plus the icon/percentage switches
/// Split out of GeneralSettingsView to keep single file size manageable
struct GeneralSettingsDisplaySection: View {
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        SettingSection(
            icon: "gauge.with.dots.needle.0percent",
            iconColor: .blue,
            title: L.SettingsGeneral.displaySection
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // One switch rather than two sibling radios: naming the modes as peers
                // ("Color Translucent" vs "Monochrome") asks the user to decode an
                // implementation detail. Off keeps the status colors, which carry the
                // information, so monochrome is the opt-in for a uniform menu bar.
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { settings.iconStyleMode == .monochrome },
                        set: { settings.iconStyleMode = $0 ? .monochrome : .colorTranslucent }
                    )) {
                        Text(L.IconStyle.monochrome)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text(L.IconStyle.monochromeToggleHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Battery style display: remaining capacity instead of used percentage
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $settings.showRemainingPercentage) {
                        Text(L.Display.showRemaining)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text(L.Display.showRemainingDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Pace-aware colors: escalate on the projected end-of-window figure
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $settings.paceAwareBarColors) {
                        Text(L.Display.paceAwareColors)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text(L.Display.paceAwareColorsDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Time marker: a tick at how far through the period we are
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $settings.showTimeMarker) {
                        Text(L.Display.showTimeMarker)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text(L.Display.showTimeMarkerDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
