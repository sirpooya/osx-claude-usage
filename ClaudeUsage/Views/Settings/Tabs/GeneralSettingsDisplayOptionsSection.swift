//
//  GeneralSettingsDisplayOptionsSection.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// The "display options" card on the general settings page: the smart/custom display mode plus the custom type checkboxes
/// Split out of GeneralSettingsView to keep single file size manageable
struct GeneralSettingsDisplayOptionsSection: View {
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        SettingCard(
            icon: "rectangle.3.group",
            iconColor: .purple,
            title: L.DisplayOptions.title,
            hint: settings.displayMode == .smart ? L.DisplayOptions.smartDisplayDescription : L.DisplayOptions.customDisplayDescription
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Display mode picker
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.DisplayOptions.displayModeLabel)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Picker("", selection: $settings.displayMode) {
                        Text(L.DisplayOptions.smartDisplay).tag(DisplayMode.smart)
                        Text(L.DisplayOptions.customDisplay).tag(DisplayMode.custom)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .focusable(false)
                }

                // Custom selection (shown in custom mode only)
                if settings.displayMode == .custom {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.DisplayOptions.selectLimitTypes)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(LimitType.allCases, id: \.self) { limitType in
                                LimitTypeCheckbox(
                                    limitType: limitType,
                                    isSelected: settings.customDisplayTypes.contains(limitType),
                                    isDisabled: shouldDisableCheckbox(for: limitType)
                                ) {
                                    toggleLimitType(limitType)
                                }
                            }
                        }
                        .padding(.leading, 20)

                        // Constraint hints
                        if hasOnlyOneCircularIcon {
                            Text(L.DisplayOptions.circularIconConstraint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 20)
                        }

                        // Theme availability hint
                        if !canUseColoredTheme {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(L.DisplayOptions.coloredThemeUnavailable)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.leading, 20)
                        }

                        Divider()

                        // The "menu bar only" switch: when on, the popover uses the smart display
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $settings.customDisplayMenuBarOnly) {
                                Text(L.DisplayOptions.menuBarOnlyToggle)
                                    .font(.subheadline)
                            }
                            .toggleStyle(.checkbox)

                            Text(L.DisplayOptions.menuBarOnlyDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Display Options Helpers

    /// Decide whether only one circular icon is left
    private var hasOnlyOneCircularIcon: Bool {
        let circularTypes: Set<LimitType> = [.fiveHour, .sevenDay, .codexPrimary, .codexSecondary]
        let selectedCircular = settings.customDisplayTypes.intersection(circularTypes)
        return selectedCircular.count == 1
    }

    /// Decide whether a color theme can be used
    private var canUseColoredTheme: Bool {
        // Every limit type supports colored display now
        // A color theme works as long as some limit type is selected
        return !settings.customDisplayTypes.isEmpty
    }

    /// Decide whether a checkbox should be disabled
    private func shouldDisableCheckbox(for limitType: LimitType) -> Bool {
        #if DEBUG
        // In Debug mode, when "show every shape separately" is on, deselecting every limit is allowed
        if settings.debugShowAllShapesIndividually {
            return false
        }
        #endif

        let circularTypes: Set<LimitType> = [.fiveHour, .sevenDay, .codexPrimary, .codexSecondary]

        // Disable it when this is the last selected circular icon
        if circularTypes.contains(limitType) {
            let selectedCircular = settings.customDisplayTypes.intersection(circularTypes)
            return selectedCircular.count == 1 && selectedCircular.contains(limitType)
        }

        return false
    }

    /// Toggle a limit type's selection
    private func toggleLimitType(_ limitType: LimitType) {
        if settings.customDisplayTypes.contains(limitType) {
            // Check whether it can be deselected
            if !shouldDisableCheckbox(for: limitType) {
                settings.customDisplayTypes.remove(limitType)
            }
        } else {
            settings.customDisplayTypes.insert(limitType)
        }
    }
}

// MARK: - Limit Type Checkbox Component

/// Limit type checkbox
struct LimitTypeCheckbox: View {
    let limitType: LimitType
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: {
            if !isDisabled {
                onToggle()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isDisabled ? .secondary : (isSelected ? .blue : .primary))
                    .font(.body)

                HStack(spacing: 6) {
                    // Limit type icon
                    limitTypeIcon
                        .font(.caption)

                    // Limit type name
                    Text(limitType.displayName)
                        .foregroundColor(isDisabled ? .secondary : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(isDisabled ? L.DisplayOptions.circularIconConstraint : "")
        .fixedSize()
    }

    @ViewBuilder
    private var limitTypeIcon: some View {
        // Draw the icon on a Canvas, the same way the detail UI does
        Canvas { context, canvasSize in
            let lineWidth: CGFloat = 1.8
            let path = shapePath(for: limitType, in: CGRect(origin: .zero, size: canvasSize))

            // Draw the background border
            context.stroke(path, with: .color(Color.gray.opacity(0.3)), lineWidth: lineWidth)

            // Draw a full progress ring (100%)
            context.stroke(path, with: .color(iconColor(for: limitType)), lineWidth: lineWidth)
        }
        .frame(width: 14, height: 14)
    }

    private func shapePath(for type: LimitType, in rect: CGRect) -> Path {
        return IconShapePaths.pathForLimitType(type, in: rect)
    }

    private func iconColor(for type: LimitType) -> Color {
        switch type {
        case .fiveHour: return .green
        case .sevenDay: return .purple
        case .extraUsage: return .pink
        case .opusWeekly: return .orange
        case .sonnetWeekly: return .blue
        case .codexPrimary:  return Color(red: 45/255.0, green: 212/255.0, blue: 191/255.0)
        case .codexSecondary: return Color(red: 96/255.0, green: 165/255.0, blue: 250/255.0)
        case .codexExtraUsage: return Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0)
        }
    }
}
