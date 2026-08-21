//
//  CredentialsChrome.swift
//  ClaudeUsage
//
//  Shared furniture for the three credential panes: the page header, the connected
//  status card, the numbered step indicator and the card container they all sit in.
//  Keeping it in one place is what makes Claude.ai, API Console and CLI Account look
//  like three views of one idea rather than three separate screens.
//

import SwiftUI

// MARK: - Page header

struct CredentialPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Status card

/// The connected / not connected card at the top of every pane. When connected it can
/// show the masked credential and offer a trailing action such as Remove.
struct CredentialStatusCard<Trailing: View>: View {
    let isConnected: Bool
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            trailing
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

extension CredentialStatusCard where Trailing == EmptyView {
    init(isConnected: Bool, title: String, detail: String? = nil) {
        self.init(isConnected: isConnected, title: title, detail: detail) { EmptyView() }
    }
}

// MARK: - Step indicator

/// Three step wizard state, shared by the Claude.ai and API Console panes
enum CredentialStep: Int, Comparable, CaseIterable {
    case enterKey = 1
    case selectOrganization = 2
    case confirm = 3

    static func < (lhs: CredentialStep, rhs: CredentialStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The numbered 1 - 2 - 3 header. The current step is the only one that shows its title,
/// which keeps the row narrow enough for the settings window.
struct CredentialStepIndicator: View {
    let current: CredentialStep
    let titles: [CredentialStep: String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(CredentialStep.allCases.enumerated()), id: \.element) { index, step in
                let isCurrent = current == step
                let isCompleted = current > step

                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(isCompleted ? Color.green : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.2)))
                            .frame(width: 20, height: 20)

                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(isCurrent ? .white : .secondary)
                        }
                    }

                    if isCurrent, let title = titles[step] {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }

                if index < CredentialStep.allCases.count - 1 {
                    Rectangle()
                        .fill(isCompleted ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2))
                        .frame(height: 1)
                }
            }
        }
    }
}

// MARK: - Card container

/// The bordered container the configuration steps live in, with an optional titled header
/// separated by a divider (the "Configuration" card in the reference design).
struct CredentialCard<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
            }
            .padding(14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Detail row

/// Label above value, used by the account detail blocks
struct CredentialDetailRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(iconColor)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Info box

/// The "About" explainer at the bottom of a pane
struct CredentialInfoBox: View {
    let title: String
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            ForEach(points, id: \.self) { point in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(point)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.06))
        )
    }
}
