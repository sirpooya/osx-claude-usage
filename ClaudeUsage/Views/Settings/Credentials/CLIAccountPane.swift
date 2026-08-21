//
//  CLIAccountPane.swift
//  ClaudeUsage
//
//  CLI Account pane: adopt the account Claude Code is already signed in to.
//  Status, then the synced account details, then the credentials source picker for
//  people running more than one CLAUDE_CONFIG_DIR, then the explainer.
//

import SwiftUI

struct CLIAccountPane: View {
    @ObservedObject private var cliSync = ClaudeCodeSyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CredentialPageHeader(
                title: L.CLISync.title,
                subtitle: L.CredentialsNav.cliPaneSubtitle
            )

            statusCard

            if cliSync.isSynced, let credentials = cliSync.credentials {
                accountDetailsCard(credentials: credentials)
            } else {
                connectCard
            }

            if cliSync.availableEntries.count > 1 {
                credentialsSourceCard
            }

            CredentialInfoBox(
                title: L.CLISync.aboutTitle,
                points: [L.CLISync.aboutPoint1, L.CLISync.aboutPoint2, L.CLISync.aboutPoint3]
            )
        }
        .onAppear { cliSync.refreshEntries() }
    }

    // MARK: - Status

    private var statusCard: some View {
        CredentialStatusCard(
            isConnected: cliSync.isSynced,
            title: statusTitle,
            detail: nil
        ) {
            if case .syncing = cliSync.state {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var statusTitle: String {
        switch cliSync.state {
        case .synced: return L.CLISync.statusSynced
        case .syncing: return L.CLISync.statusSyncing
        case .failed(let message): return message
        case .notSynced:
            if cliSync.isSynced { return L.CLISync.statusSynced }
            return cliSync.isAvailable ? L.CLISync.statusAvailable : L.CLISync.statusUnavailable
        }
    }

    // MARK: - Synced details

    private func accountDetailsCard(credentials: ClaudeCodeCredentials) -> some View {
        CredentialCard {
            Text(L.CLISync.accountDetails)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(L.CLISync.accountDetailsSubtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        } content: {
            // Masked only: the full token is never displayed, copied or logged
            CredentialDetailRow(
                icon: "key.fill",
                iconColor: .red,
                label: L.CLISync.accessToken,
                value: credentials.maskedAccessToken,
                monospaced: true
            )

            if !credentials.subscriptionType.isEmpty {
                CredentialDetailRow(
                    icon: "person.crop.circle.badge.checkmark",
                    iconColor: .blue,
                    label: L.CLISync.subscription,
                    value: credentials.subscriptionType
                )
            }

            if !credentials.scopes.isEmpty {
                CredentialDetailRow(
                    icon: "checkmark.shield.fill",
                    iconColor: .green,
                    label: L.CLISync.scopes,
                    value: credentials.scopes.joined(separator: ", ")
                )
            }

            HStack(spacing: 8) {
                Button {
                    Task { await cliSync.sync() }
                } label: {
                    Label(L.CLISync.resync, systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    cliSync.removeSync()
                } label: {
                    Label(L.CLISync.remove, systemImage: "trash")
                }
                .controlSize(.small)

                Spacer()
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Not synced yet

    private var connectCard: some View {
        CredentialCard {
            Text(L.CLISync.configuration)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        } content: {
            Text(cliSync.isAvailable ? L.CLISync.readyHint : L.CLISync.notFoundHint)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    Task { await cliSync.sync() }
                } label: {
                    Label(L.CLISync.syncNow, systemImage: "arrow.down.circle")
                }
                .controlSize(.regular)
                .disabled(!cliSync.isAvailable)

                Button {
                    cliSync.refreshEntries()
                } label: {
                    Label(L.CLISync.refresh, systemImage: "arrow.clockwise")
                }
                .controlSize(.small)

                Spacer()
            }
        }
    }

    // MARK: - Credentials source

    private var credentialsSourceCard: some View {
        CredentialCard {
            Text(L.CLISync.advancedTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(L.CLISync.advancedHint)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } content: {
            HStack(spacing: 8) {
                Text(L.CLISync.keychainEntry)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { cliSync.pinnedService ?? "" },
                    set: { cliSync.pinnedService = $0.isEmpty ? nil : $0 }
                )) {
                    Text(L.CLISync.automatic).tag("")
                    ForEach(cliSync.availableEntries) { entry in
                        Text(entry.displayName).tag(entry.service)
                    }
                }
                .labelsHidden()

                Button {
                    cliSync.refreshEntries()
                } label: {
                    Label(L.CLISync.refresh, systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
    }
}
