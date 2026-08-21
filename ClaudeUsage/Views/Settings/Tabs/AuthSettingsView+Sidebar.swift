//
//  AuthSettingsView+Sidebar.swift
//  ClaudeUsage
//
//  Two pane credentials layout: a sidebar listing every login method with its own
//  connected dot, and a detail pane for the selected one. Each method is independent,
//  so configuring any single one of them is enough to produce data.
//

import SwiftUI

extension AuthSettingsView {

    /// The login methods, one sidebar row each
    enum CredentialSection: String, CaseIterable, Identifiable {
        case cliAccount
        case claudeAI
        case codex
        case diagnostics

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .cliAccount: return "terminal.fill"
            case .claudeAI: return "key.fill"
            case .codex: return "chevron.left.forwardslash.chevron.right"
            case .diagnostics: return "stethoscope"
            }
        }

        var title: String {
            switch self {
            case .cliAccount: return L.CLISync.title
            case .claudeAI: return L.CredentialsNav.claudeAI
            case .codex: return L.CredentialsNav.codex
            case .diagnostics: return L.CredentialsNav.diagnostics
            }
        }

        /// Pane heading and one line of subtitle
        var paneTitle: String {
            switch self {
            case .cliAccount: return L.CredentialsNav.cliPaneTitle
            case .claudeAI: return L.CredentialsNav.claudePaneTitle
            case .codex: return L.CredentialsNav.codexPaneTitle
            case .diagnostics: return L.CredentialsNav.diagnostics
            }
        }

        var paneSubtitle: String {
            switch self {
            case .cliAccount: return L.CredentialsNav.cliPaneSubtitle
            case .claudeAI: return L.CredentialsNav.claudePaneSubtitle
            case .codex: return L.CredentialsNav.codexPaneSubtitle
            case .diagnostics: return L.CredentialsNav.diagnosticsSubtitle
            }
        }
    }

    // MARK: - Two pane shell

    var credentialsSplitView: some View {
        HStack(alignment: .top, spacing: 0) {
            credentialsSidebar
            Divider()
            credentialsDetailPane
        }
    }

    // MARK: - Sidebar

    private var credentialsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.CredentialsNav.sectionCredentials)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach([CredentialSection.cliAccount, .claudeAI, .codex]) { section in
                sidebarRow(section)
            }

            Text(L.CredentialsNav.sectionTools)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 4)

            sidebarRow(.diagnostics)

            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 168)
    }

    private func sidebarRow(_ section: CredentialSection) -> some View {
        let isSelected = credentialSection == section

        return Button {
            credentialSection = section
        } label: {
            HStack(spacing: 7) {
                Image(systemName: section.icon)
                    .font(.caption)
                    .frame(width: 15)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(section.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Diagnostics is a tool rather than a credential, so it carries no connected dot
                if section != .diagnostics {
                    Circle()
                        .fill(isConnected(section) ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    /// Whether a login method currently holds usable credentials
    func isConnected(_ section: CredentialSection) -> Bool {
        switch section {
        case .cliAccount:
            return cliSync.isSynced
        case .claudeAI:
            // Only manually pasted or browser OAuth accounts count here, a CLI synced one belongs to its own row
            return settings.accounts.contains { !$0.credentialSource.isCLISynced }
        case .codex:
            return !settings.codexAccounts.isEmpty
        case .diagnostics:
            return false
        }
    }

    // MARK: - Detail pane

    private var credentialsDetailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                paneHeader

                if credentialSection != .diagnostics {
                    connectionPill
                }

                paneContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(credentialSection.paneTitle)
                .font(.title3)
                .fontWeight(.semibold)
            Text(credentialSection.paneSubtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// The connected / not connected banner at the top of the pane
    private var connectionPill: some View {
        let connected = isConnected(credentialSection)
        return HStack(spacing: 7) {
            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(connected ? L.CredentialsNav.connected : L.CredentialsNav.notConnected)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var paneContent: some View {
        switch credentialSection {
        case .cliAccount:
            cliAccountCard

        case .claudeAI:
            if isAddingAccount {
                addAccountView
            } else {
                if let message = successMessage {
                    inlineSuccessBanner(message)
                }
                accountListView
                if let currentAccount = settings.currentAccount {
                    currentAccountDetailView(account: currentAccount)
                }
                howToCard
            }

        case .codex:
            if let currentCodexAccount = settings.currentCodexAccount {
                currentCodexAccountDetailView(account: currentCodexAccount)
            } else {
                accountListView
            }

        case .diagnostics:
            diagnosticsCard
        }
    }

    func inlineSuccessBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { successMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }
}
