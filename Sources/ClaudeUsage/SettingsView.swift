import SwiftUI
import ClaudeUsageCore

struct SettingsView: View {
    let viewModel: UsageViewModel
    let preferences: Preferences

    var body: some View {
        TabView {
            GeneralSettingsTab(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountSettingsTab(viewModel: viewModel)
                .tabItem { Label("Account", systemImage: "person.badge.key") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 380)
    }
}

private struct GeneralSettingsTab: View {
    let preferences: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show", selection: Binding(
                    get: { preferences.menuBarStyle },
                    set: { preferences.menuBarStyle = $0 }
                )) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }

                Picker("Track", selection: Binding(
                    get: { preferences.menuBarSource },
                    set: { preferences.menuBarSource = $0 }
                )) {
                    ForEach(MenuBarSource.allCases) { Text($0.title).tag($0) }
                }

                Toggle("Tint the number when usage is high", isOn: Binding(
                    get: { preferences.showColorWhenHigh },
                    set: { preferences.showColorWhenHigh = $0 }
                ))
            }

            Section("Thresholds") {
                Stepper(
                    "Warning at \(preferences.warningThreshold)%",
                    value: Binding(
                        get: { preferences.warningThreshold },
                        set: { preferences.warningThreshold = min($0, preferences.criticalThreshold - 1) }
                    ),
                    in: 5...94,
                    step: 5
                )
                Stepper(
                    "Critical at \(preferences.criticalThreshold)%",
                    value: Binding(
                        get: { preferences.criticalThreshold },
                        set: { preferences.criticalThreshold = max($0, preferences.warningThreshold + 1) }
                    ),
                    in: 10...99,
                    step: 5
                )
            }

            Section("System") {
                Toggle("Use a 24 hour clock for reset times", isOn: Binding(
                    get: { preferences.use24HourClock },
                    set: { preferences.use24HourClock = $0 }
                ))

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                    .onChange(of: launchAtLogin) { _, newValue in
                        launchAtLogin = LaunchAtLogin.setEnabled(newValue)
                    }

                if !LaunchAtLogin.isAvailable {
                    Text("Available once ClaudeUsage runs from an installed app bundle.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountSettingsTab: View {
    let viewModel: UsageViewModel
    @State private var historyPath = ""

    var body: some View {
        Form {
            Section("Credentials") {
                LabeledContent("Source") {
                    Text("macOS login keychain")
                }
                LabeledContent("Keychain item") {
                    Text(KeychainTokenStore.service)
                        .font(.system(size: 11, design: .monospaced))
                }
                LabeledContent("Status") {
                    statusLabel
                }
                Text("ClaudeUsage reads the token that the claude CLI already stores, at the moment of each request. The token is never written to disk, never logged, and never shown.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section("Polling") {
                LabeledContent("Last success") {
                    Text(viewModel.lastSuccessAt.map { RelativeTime.agoDescription($0) } ?? "never")
                }
                LabeledContent("Next poll") {
                    Text(viewModel.nextPollAt.flatMap { RelativeTime.compactCountdown(to: $0) } ?? "soon")
                }
                Button("Refresh now") { viewModel.refreshNow() }
            }

            Section("History") {
                LabeledContent("Snapshots recorded") {
                    Text("\(viewModel.historyRowCount)")
                        .monospacedDigit()
                }
                HStack {
                    Text(historyPath.isEmpty ? "Locating..." : historyPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal") {
                        Task {
                            let url = await viewModel.historyFileURL
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            historyPath = await viewModel.historyFileURL.path
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch viewModel.state {
        case .loaded:
            Label("Working", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .loading, .idle:
            Label("Checking", systemImage: "hourglass").foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AboutTab: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("ClaudeUsage")
                .font(.system(size: 17, weight: .semibold))
            Text(version)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Menu bar tracker for Claude usage limits. Reads the authoritative OAuth usage endpoint, keeps local history, sends no telemetry, and needs no account of its own.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Text("MIT licensed")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}
