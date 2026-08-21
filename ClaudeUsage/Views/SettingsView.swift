//
//  SettingsView.swift
//  ClaudeUsage
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Settings view
/// A toolbar style layout with three tabs: general settings, authentication and about
struct SettingsView: View {
    @ObservedObject private var settings = UserSettings.shared
    @State private var selectedTab: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared

    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar style tab navigation
            HStack(spacing: 0) {
                // General settings button
                ToolbarButton(
                    icon: "gearshape",
                    title: L.SettingsTab.general,
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }

                // Separator
                TabDivider()

                // Authentication settings button
                ToolbarButton(
                    icon: "key.horizontal",
                    title: L.SettingsTab.auth,
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }

                // Separator
                TabDivider()

                // About button
                ToolbarButton(
                    icon: "info.circle",
                    title: L.SettingsTab.about,
                    isSelected: selectedTab == 2
                ) {
                    selectedTab = 2
                }
            }
            .padding(.horizontal)
            .padding(.top, 7)
            .padding(.bottom, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content area
            Group {
                switch selectedTab {
                case 0:
                    GeneralSettingsView()
                case 1:
                    AuthSettingsView()
                case 2:
                    AboutView()
                default:
                    GeneralSettingsView()
                }
            }
        }
        .frame(width: 500, height: 550)
        .id(localization.updateTrigger)  // Rebuild the view when the language changes
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
