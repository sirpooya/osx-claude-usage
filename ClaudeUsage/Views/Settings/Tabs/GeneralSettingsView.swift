//
//  GeneralSettingsView.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import ServiceManagement

/// General settings page
/// A card layout covering launch at login, display settings, refresh settings and language
/// Each card's content is split by topic into GeneralSettings*Section.swift, to keep this file manageable
struct GeneralSettingsView: View {
    @ObservedObject private var settings = UserSettings.shared
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GeneralSettingsDisplaySection()
                GeneralSettingsDisplayOptionsSection()

                // Refresh settings card
                SettingCard(
                    icon: "clock.arrow.trianglehead.2.counterclockwise.rotate.90",
                    iconColor: .green,
                    title: L.SettingsGeneral.refreshSection,
                    hint: settings.refreshMode == .smart ? L.SettingsGeneral.refreshHintSmart : L.SettingsGeneral.refreshHintFixed
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Refresh mode picker
                        Picker("", selection: $settings.refreshMode) {
                            ForEach(RefreshMode.allCases, id: \.self) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .focusable(false)

                        // Fixed interval picker (shown in fixed mode only)
                        if settings.refreshMode == .fixed {
                            HStack {
                                Text(L.SettingsGeneral.refreshInterval)
                                    .foregroundColor(.secondary)

                                Picker("", selection: $settings.refreshInterval) {
                                    ForEach(RefreshInterval.allCases, id: \.rawValue) { interval in
                                        Text(interval.localizedName).tag(interval.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                            .padding(.leading, 20)
                        }
                    }
                }

                // Notification settings card
                SettingCard(
                    icon: "bell.badge",
                    iconColor: .red,
                    title: L.SettingsNotification.section,
                    hint: L.SettingsNotification.hint
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("", isOn: $settings.notificationsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .focusable(false)
                                .labelsHidden()
                            Text(L.SettingsNotification.enable)
                            Spacer()
                        }
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(L.SettingsNotification.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Time format settings card
                SettingCard(
                    icon: "clock",
                    iconColor: .cyan,
                    title: L.SettingsGeneralTimeFormat.section,
                    hint: L.SettingsGeneralTimeFormat.hint
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $settings.timeFormatPreference) {
                            ForEach(TimeFormatPreference.allCases, id: \.self) { format in
                                Text(format.localizedName).tag(format)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .focusable(false)

                        // Current time preview
                        HStack(spacing: 4) {
                            Text(L.SettingsGeneralTimeFormat.preview + ":")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(timePreviewString)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        .padding(.leading, 20)
                    }
                }

                // Language settings card
                SettingCard(
                    icon: "globe",
                    iconColor: .orange,
                    title: L.SettingsGeneral.languageSection,
                    hint: L.SettingsGeneral.languageHint
                ) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.localizedName).tag(lang)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .focusable(false)
                }

                // Launch at login settings card
                SettingCard(
                    icon: "power",
                    iconColor: .orange,
                    title: L.SettingsGeneral.launchSection,
                    hint: L.SettingsGeneral.launchHint
                ) {
                    HStack {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .focusable(false)
                            .labelsHidden()

                        Text(L.SettingsGeneral.launchAtLogin)

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .foregroundColor(statusColor)
                                .font(.caption)
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Reset button
                HStack {
                    Spacer()
                    Button(L.SettingsGeneral.resetButton) {
                        settings.resetToDefaults()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)

                #if DEBUG
                GeneralSettingsDebugSection()
                #endif
            }
            .padding()
        }
        .onAppear {
            // Sync the state when the settings page opens
            settings.syncLaunchAtLoginStatus()

            // Listen for the error notification
            NotificationCenter.default.addObserver(
                forName: .launchAtLoginError,
                object: nil,
                queue: .main
            ) { notification in
                handleLaunchError(notification)
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text(L.LaunchAtLogin.errorTitle),
                message: Text(errorMessage),
                dismissButton: .default(Text(L.Update.okButton))
            )
        }
    }

    // MARK: - Computed Properties

    /// Time preview string
    private var timePreviewString: String {
        let now = Date()
        return TimeFormatHelper.formatTimeOnly(now)
    }

    /// Status icon
    private var statusIcon: String {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return "checkmark.circle.fill"
        case .requiresApproval:
            return "exclamationmark.circle.fill"
        case .notRegistered:
            return "circle"
        case .notFound:
            return "xmark.circle.fill"
        @unknown default:
            // An unknown state is treated as not enabled, and the real state is synced in onAppear
            return "circle"
        }
    }

    /// Status color
    private var statusColor: Color {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return .green
        case .requiresApproval:
            return .orange
        case .notRegistered:
            return .secondary
        case .notFound:
            return .red
        @unknown default:
            // Treat an unknown state as not enabled
            return .secondary
        }
    }

    /// Status text
    private var statusText: String {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return L.LaunchAtLogin.statusEnabled
        case .requiresApproval:
            return L.LaunchAtLogin.statusRequiresApproval
        case .notRegistered:
            return L.LaunchAtLogin.statusDisabled
        case .notFound:
            return L.LaunchAtLogin.statusNotFound
        @unknown default:
            // Treat an unknown state as not enabled
            return L.LaunchAtLogin.statusDisabled
        }
    }

    // MARK: - Error Handling

    /// Handle a launch at login error
    private func handleLaunchError(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let error = userInfo["error"] as? Error,
              let operation = userInfo["operation"] as? String else {
            return
        }

        let operationType = operation == "enable" ? L.LaunchAtLogin.errorEnable : L.LaunchAtLogin.errorDisable
        errorMessage = "\(operationType)\n\n\(error.localizedDescription)"
        showErrorAlert = true
    }
}
