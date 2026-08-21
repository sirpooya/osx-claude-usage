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

                // Display content picker
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.SettingsGeneral.displayContent)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { settings.iconDisplayMode == .iconOnly || settings.iconDisplayMode == .both },
                            set: { showIcon in
                                let showPercentage = settings.iconDisplayMode == .percentageOnly || settings.iconDisplayMode == .both
                                if showIcon && showPercentage {
                                    settings.iconDisplayMode = .both
                                } else if showIcon {
                                    settings.iconDisplayMode = .iconOnly
                                } else {
                                    settings.iconDisplayMode = .percentageOnly
                                }
                            }
                        )) {
                            Text(L.Display.showIcon)
                        }
                        .toggleStyle(.checkbox)
                        .focusable(false)
                        .disabled(settings.iconDisplayMode == .iconOnly)

                        Toggle(isOn: Binding(
                            get: { settings.iconDisplayMode == .percentageOnly || settings.iconDisplayMode == .both },
                            set: { showPercentage in
                                let showIcon = settings.iconDisplayMode == .iconOnly || settings.iconDisplayMode == .both
                                if showIcon && showPercentage {
                                    settings.iconDisplayMode = .both
                                } else if showPercentage {
                                    settings.iconDisplayMode = .percentageOnly
                                } else {
                                    settings.iconDisplayMode = .iconOnly
                                }
                            }
                        )) {
                            Text(L.Display.showPercentage)
                        }
                        .toggleStyle(.checkbox)
                        .focusable(false)
                        .disabled(settings.iconDisplayMode == .percentageOnly)
                    }

                    // Inline rather than the section's hint slot: SettingSection renders its hint
                    // last, which would put this line under Show Remaining and read as if it
                    // described that switch instead of these checkboxes.
                    Text(L.SettingsGeneral.menubarHint)
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
            }
        }
    }
}
