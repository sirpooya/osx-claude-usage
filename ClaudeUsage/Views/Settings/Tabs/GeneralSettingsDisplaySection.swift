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
                SettingToggleRow(
                    title: L.IconStyle.monochrome,
                    description: L.IconStyle.monochromeToggleHint,
                    isOn: Binding(
                        get: { settings.iconStyleMode == .monochrome },
                        set: { settings.iconStyleMode = $0 ? .monochrome : .colorTranslucent }
                    )
                )

                Divider()

                // Battery style display: remaining capacity instead of used percentage
                SettingToggleRow(
                    title: L.Display.showRemaining,
                    description: L.Display.showRemainingDesc,
                    isOn: $settings.showRemainingPercentage
                )

                Divider()

                // Pace-aware colors: escalate on the projected end-of-window figure
                SettingToggleRow(
                    title: L.Display.paceAwareColors,
                    description: L.Display.paceAwareColorsDesc,
                    isOn: $settings.paceAwareBarColors
                )

                Divider()

                // Time marker: a tick at how far through the period we are
                SettingToggleRow(
                    title: L.Display.showTimeMarker,
                    description: L.Display.showTimeMarkerDesc,
                    isOn: $settings.showTimeMarker
                )

                Divider()

                // Display content picker, last in the section
                VStack(alignment: .leading, spacing: 8) {
                    // Same face as the toggle row titles above, so it reads as a peer
                    Text(L.SettingsGeneral.displayContent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

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
                }
            }
        }
    }
}
