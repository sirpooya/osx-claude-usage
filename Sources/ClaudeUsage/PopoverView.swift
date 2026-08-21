import SwiftUI
import ClaudeUsageCore

struct PopoverView: View {
    let viewModel: UsageViewModel
    let preferences: Preferences
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    /// Redraws the countdowns without re-polling the endpoint.
    @State private var tick = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 300)
        .onReceive(every: 30) { tick = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .foregroundStyle(.secondary)
            Text("Claude Usage")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                viewModel.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            placeholder(icon: "hourglass", message: "Reading usage...")
        case .failed(let message) where viewModel.snapshot == nil:
            placeholder(icon: "exclamationmark.triangle", message: message)
        case .loaded, .failed:
            limitRows
        }
    }

    private var limitRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = viewModel.snapshot {
                if snapshot.limits.isEmpty {
                    Text("No limits reported for this account.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.sortedLimits) { limit in
                        LimitRow(limit: limit, preferences: preferences, now: tick)
                    }
                }

                if let spend = snapshot.spend, spend.enabled, let used = spend.used {
                    Divider()
                    HStack {
                        Text("Extra usage")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatted(used))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                    }
                }
            }

            // A stale read is worth showing without throwing away good data.
            if case .failed(let message) = viewModel.state, viewModel.snapshot != nil {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func formatted(_ money: MoneyAmount) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = money.currency
        formatter.maximumFractionDigits = money.exponent
        return formatter.string(from: money.decimalValue as NSDecimalNumber) ?? "\(money.decimalValue)"
    }

    private func placeholder(icon: String, message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(message)
                .font(.system(size: 11))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(updatedLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Settings", action: onOpenSettings)
                .buttonStyle(.plain)
                .font(.system(size: 11))
            Button("Quit", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var updatedLabel: String {
        guard let last = viewModel.lastSuccessAt else { return "Not updated yet" }
        return "Updated \(RelativeTime.agoDescription(last, from: tick))"
    }
}

private struct LimitRow: View {
    let limit: UsageLimit
    let preferences: Preferences
    let now: Date

    var body: some View {
        let tier = UsageTier.forPercent(limit.percent, preferences: preferences)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.displayName)
                    .font(.system(size: 11, weight: limit.isActive ? .semibold : .regular))
                if limit.isActive {
                    Text("binding")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(tier.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(tier.color)
                }
                Spacer()
                Text("\(limit.percent)%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(tier == .normal ? .primary : tier.color)
            }

            ProgressView(value: limit.fraction)
                .progressViewStyle(.linear)
                .tint(tier.color)

            if let resets = limit.resetsAt {
                HStack(spacing: 4) {
                    if let countdown = RelativeTime.compactCountdown(to: resets, from: now) {
                        Text("Resets in \(countdown)")
                    } else {
                        Text("Reset due")
                    }
                    Text("at")
                    Text(RelativeTime.clockTime(resets, use24Hour: preferences.use24HourClock))
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
        }
        .help("Server severity: \(limit.severity.rawValue)")
    }
}

extension View {
    /// Keeps countdown labels live while the popover is open. Uses a task
    /// rather than a repeating Timer so it is torn down on disappear instead
    /// of stacking a new timer every time the popover reopens.
    func onReceive(every seconds: TimeInterval, perform action: @escaping (Date) -> Void) -> some View {
        task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if Task.isCancelled { return }
                action(Date())
            }
        }
    }
}
