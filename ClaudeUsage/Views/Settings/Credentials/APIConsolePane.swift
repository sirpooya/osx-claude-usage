//
//  APIConsolePane.swift
//  ClaudeUsage
//
//  API Billing pane: console.anthropic.com pay as you go spend and prepaid credits.
//  Three step configuration, matching the Claude.ai pane: paste the console session key,
//  pick the organization it can see, confirm.
//

import AppKit
import SwiftUI

struct APIConsolePane: View {
    @ObservedObject private var console = ConsoleAPIService.shared

    @State private var step: CredentialStep = .enterKey
    @State private var sessionKey = ""
    @State private var organizations: [ConsoleOrganization] = []
    @State private var selectedOrganization: ConsoleOrganization?
    @State private var isFetching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CredentialPageHeader(
                title: L.APIConsole.paneTitle,
                subtitle: L.APIConsole.paneSubtitle
            )

            statusCard

            if console.isConfigured {
                figuresCard
            } else {
                configurationCard
            }

            CredentialInfoBox(
                title: L.APIConsole.aboutTitle,
                points: [L.APIConsole.aboutPoint1, L.APIConsole.aboutPoint2, L.APIConsole.aboutPoint3]
            )
        }
        .onAppear {
            if console.isConfigured { Task { await console.refresh() } }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        CredentialStatusCard(
            isConnected: console.isConfigured,
            title: console.isConfigured ? L.CredentialsNav.connected : L.CredentialsNav.notConnected,
            detail: console.isConfigured ? console.credentials.maskedSessionKey : nil
        ) {
            if console.isConfigured {
                Button(role: .destructive) {
                    console.remove()
                    resetWizard()
                } label: {
                    Label(L.CLISync.remove, systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Figures once configured

    private var figuresCard: some View {
        CredentialCard {
            HStack {
                Text(L.APIConsole.currentPeriod)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    Task { await console.refresh() }
                } label: {
                    Label(L.CLISync.refresh, systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(console.isBusy)
            }
        } content: {
            CredentialDetailRow(
                icon: "building.2.fill",
                iconColor: .blue,
                label: L.APIConsole.organization,
                value: console.credentials.organizationName
            )

            if let spend = console.currentSpend {
                CredentialDetailRow(
                    icon: "dollarsign.circle.fill",
                    iconColor: .green,
                    label: L.APIConsole.currentSpend,
                    value: formatted(spend.dollars)
                )
            }

            if let credits = console.prepaidCredits {
                CredentialDetailRow(
                    icon: "creditcard.fill",
                    iconColor: .orange,
                    label: L.APIConsole.prepaidCredits,
                    value: formatted(credits.dollars, currency: credits.currency)
                )
            }

            if console.isBusy {
                ProgressView().controlSize(.small)
            }

            if let error = console.lastError {
                inlineError(error)
            }
        }
    }

    // MARK: - Configuration wizard

    private var configurationCard: some View {
        CredentialCard {
            Text(L.APIConsole.configuration)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            CredentialStepIndicator(current: step, titles: [
                .enterKey: L.APIConsole.stepEnterKey,
                .selectOrganization: L.APIConsole.stepSelectOrg,
                .confirm: L.APIConsole.stepConfirm
            ])
        } content: {
            switch step {
            case .enterKey: enterKeyStep
            case .selectOrganization: selectOrganizationStep
            case .confirm: confirmStep
            }
        }
    }

    private var enterKeyStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.APIConsole.signInHint)
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/billing")!)
            } label: {
                Label(L.APIConsole.openConsole, systemImage: "globe")
            }
            .controlSize(.regular)

            HStack(spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                Text(L.APIConsole.or).font(.caption2).foregroundColor(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
            }

            Text(L.APIConsole.manualKeyTitle)
                .font(.caption)
                .fontWeight(.medium)

            SecureField("sk-ant-api03-...", text: $sessionKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            Text(L.APIConsole.manualKeyHint)
                .font(.caption2)
                .foregroundColor(.secondary)

            if let errorMessage { inlineError(errorMessage) }

            HStack {
                Spacer()
                Button {
                    fetchOrganizations()
                } label: {
                    if isFetching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L.APIConsole.fetchOrganizations)
                        }
                    } else {
                        Label(L.APIConsole.fetchOrganizations, systemImage: "building.2")
                    }
                }
                .controlSize(.regular)
                .disabled(sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFetching)
            }
        }
    }

    private var selectOrganizationStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.APIConsole.selectOrgHint)
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(organizations) { organization in
                Button {
                    selectedOrganization = organization
                    step = .confirm
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(organization.name)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(L.Account.cancel) { resetWizard() }
                .controlSize(.small)
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let organization = selectedOrganization {
                CredentialDetailRow(
                    icon: "building.2.fill",
                    iconColor: .blue,
                    label: L.APIConsole.organization,
                    value: organization.name
                )
            }

            HStack {
                Button(L.APIConsole.back) { step = .selectOrganization }
                    .controlSize(.small)
                Spacer()
                Button {
                    guard let organization = selectedOrganization else { return }
                    let key = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await console.save(sessionKey: key, organization: organization)
                        sessionKey = ""
                    }
                } label: {
                    Label(L.APIConsole.connect, systemImage: "checkmark.circle")
                }
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Helpers

    private func fetchOrganizations() {
        let key = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isFetching = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await console.fetchOrganizations(sessionKey: key)
                isFetching = false
                guard !fetched.isEmpty else {
                    errorMessage = L.APIConsole.errorNoOrganizations
                    return
                }
                organizations = fetched
                // A single organization needs no picking, go straight to confirmation
                if fetched.count == 1 {
                    selectedOrganization = fetched[0]
                    step = .confirm
                } else {
                    step = .selectOrganization
                }
            } catch {
                isFetching = false
                errorMessage = L.APIConsole.errorInvalidKey
            }
        }
    }

    private func resetWizard() {
        step = .enterKey
        organizations = []
        selectedOrganization = nil
        errorMessage = nil
        sessionKey = ""
    }

    private func formatted(_ amount: Double, currency: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
