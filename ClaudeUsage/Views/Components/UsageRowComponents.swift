//
//  UsageRowComponents.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Percentage Helpers

enum UsagePercentDisplay {
    static func clampedPercentage(_ percentage: Double) -> Double {
        min(100, max(0, percentage))
    }

    static func usedFraction(_ usedPercentage: Double) -> CGFloat {
        CGFloat(clampedPercentage(usedPercentage) / 100.0)
    }

    /// The percentage to show and to fill with: used, or remaining when battery style display is on.
    /// Status colors deliberately stay keyed off the used percentage, so escalation still means "close to the limit".
    static func displayPercentage(_ usedPercentage: Double) -> Double {
        let clamped = clampedPercentage(usedPercentage)
        return UserSettings.shared.showRemainingPercentage ? 100 - clamped : clamped
    }

    static func displayFraction(_ usedPercentage: Double) -> CGFloat {
        CGFloat(displayPercentage(usedPercentage) / 100.0)
    }
}

// MARK: - Provider Divider

/// The soft vertical line down the middle of the dual provider window, matching the settings page tab divider
struct ProviderDivider: View {
    let height: CGFloat

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.secondary.opacity(0.0),
                Color.secondary.opacity(0.3),
                Color.secondary.opacity(0.3),
                Color.secondary.opacity(0.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1, height: height)
    }
}

// MARK: - Usage Limit Bar

/// The horizontal bar for one limit. Full width, capsule shaped, replacing the old large ring.
struct UsageLimitBar: View {
    let fraction: CGFloat
    let color: Color
    var isRefreshing: Bool = false
    var height: CGFloat = 5

    /// While refreshing, the whole bar breathes gently in place of the old ring's spinner
    @State private var isPulsing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.10))

                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: fillWidth(in: geometry.size.width))
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.05),
                        value: fraction
                    )
            }
        }
        .frame(height: height)
        .opacity(isRefreshing && isPulsing ? 0.4 : 1)
        .onAppear { updatePulse(isRefreshing) }
        .onChange(of: isRefreshing) { newValue in updatePulse(newValue) }
    }

    /// Fill width. A very small percentage still keeps one dot of width, otherwise the user cannot tell whether there is any usage at all
    private func fillWidth(in totalWidth: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return min(totalWidth, max(height, totalWidth * fraction))
    }

    private func updatePulse(_ refreshing: Bool) {
        if refreshing {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPulsing = false
            }
        }
    }
}

// MARK: - Usage Limit Bar Row

/// One limit row: title and countdown on the upper left, percentage on the upper right, full width bar underneath
struct UsageLimitBarRow: View {
    /// One size for all three labels in the row, so title, countdown and percentage sit on one optical line.
    /// Hierarchy comes from weight and color instead, never from size.
    ///
    /// No `minimumScaleFactor` on any of them, deliberately. The title and countdown used to carry one,
    /// and since the percentage always has room it never shrank: a tight row ("5-Hour Limit  4h 51m left")
    /// scaled those two down to 10.2pt while the percentage stayed at 12, so a row declaring one size
    /// rendered two. Overflow truncates instead, and the title's `layoutPriority` makes the countdown
    /// give way first.
    private static let labelSize: CGFloat = 12

    let title: String
    let percentage: Double?
    let color: Color
    var isRefreshing: Bool = false
    /// Observed so flipping the remaining percentage setting re-renders open popover rows
    @ObservedObject private var settings = UserSettings.shared
    /// The trailing text (reset time or time left).
    /// A closure rather than a snapshot value, so TimelineView can recompute it once a minute itself
    /// instead of relying on the outer objectWillChange rebuilding the whole popover every second.
    let trailing: () -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: Self.labelSize, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)

                // The countdown sits with the title rather than out on the right edge, so the row
                // reads as one phrase ("5-Hour Limit, 26m left") and the percentage stands alone.
                // TimelineView refreshes it at minute granularity itself (minute precision is all it needs, so 60s is enough)
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(trailing())
                        .font(.system(size: Self.labelSize))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let percentageText {
                    Text(percentageText)
                        .font(.system(size: Self.labelSize))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            UsageLimitBar(
                fraction: UsagePercentDisplay.displayFraction(percentage ?? 0),
                color: color,
                isRefreshing: isRefreshing
            )
        }
    }

    /// nil when the limit carries no percentage at all, so the row does not print a bare "%"
    private var percentageText: String? {
        guard let percentage else { return nil }
        return "\(Int(UsagePercentDisplay.displayPercentage(percentage)))%"
    }
}

// MARK: - Unified Limit Row Component

/// The shared limit row (covers every Claude and Codex limit type)
struct UnifiedLimitRow: View {
    let type: LimitType
    var data: UsageData? = nil
    var codexData: CodexUsageData? = nil
    let showRemainingMode: Bool
    /// This provider is refreshing, so the bar breathes to say so
    var isRefreshing: Bool = false
    /// Overflow model row override: when it is given, the row's percentage, label and reset time come straight from this model entry
    /// and `type` only picks the color slot. Used by the popover to show the third and later models
    /// beyond the first two slots (when Fable, Opus and Sonnet all appear at once).
    var weeklyModelOverride: UsageData.WeeklyModelLimit? = nil
    /// Observed so flipping the Monochrome icon setting recolors open popover rows live
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        UsageLimitBarRow(
            title: limitName,
            percentage: percentageValue,
            color: barColor,
            isRefreshing: isRefreshing,
            trailing: { displayValue }
        )
    }

    // MARK: - Computed Properties

    private var limitName: String {
        if let override = weeklyModelOverride {
            return override.modelName ?? L.DetailRow.opusWeekly
        }
        switch type {
        case .fiveHour, .codexPrimary:
            return L.DetailRow.fiveHour
        case .sevenDay, .codexSecondary:
            return L.DetailRow.sevenDay
        case .opusWeekly:
            // The Claude 5 era: this slot may carry a per model weekly limit from the limits array (Fable, for instance).
            // A real model name wins, otherwise it falls back to the default "Opus Weekly".
            return data?.opusModelName ?? L.DetailRow.opusWeekly
        case .sonnetWeekly:
            return data?.sonnetModelName ?? L.DetailRow.sonnetWeekly
        case .extraUsage, .codexExtraUsage:
            return L.DetailRow.extraUsage
        }
    }

    /// Bar color. Each limit type keeps its own palette and escalates to the warning color with the percentage,
    /// so the color says both which limit this is and how close it is to the cap.
    /// In Monochrome icon mode the Claude bars drop the palette and all use the brand color instead;
    /// closeness to the cap stays readable from the percentage text.
    private var barColor: Color {
        let percentage = colorPercentage
        if settings.iconStyleMode == .monochrome {
            switch type {
            case .fiveHour, .sevenDay, .opusWeekly, .sonnetWeekly, .extraUsage:
                return UsageColorScheme.brand
            case .codexPrimary, .codexSecondary, .codexExtraUsage:
                break
            }
        }
        switch type {
        case .fiveHour:
            return UsageColorScheme.fiveHourColorSwiftUI(percentage, opacity: 1.0)
        case .sevenDay:
            return UsageColorScheme.sevenDayColorSwiftUI(percentage, opacity: 1.0)
        case .opusWeekly:
            return Color(nsColor: UsageColorScheme.opusWeeklyColor(percentage))
        case .sonnetWeekly:
            return Color(nsColor: UsageColorScheme.sonnetWeeklyColor(percentage))
        case .extraUsage:
            return Color(nsColor: UsageColorScheme.extraUsageColor(percentage))
        case .codexPrimary:
            return UsageColorScheme.codexPrimaryColorSwiftUI(percentage, opacity: 1.0)
        case .codexSecondary:
            return UsageColorScheme.codexSecondaryColorSwiftUI(percentage, opacity: 1.0)
        case .codexExtraUsage:
            return UsageColorScheme.codexExtraUsageColorSwiftUI(percentage, opacity: 1.0)
        }
    }

    private var iconColor: Color {
        switch type {
        case .fiveHour:
            return .green
        case .sevenDay:
            return .purple
        case .opusWeekly:
            return .orange
        case .sonnetWeekly:
            return .blue
        case .extraUsage:
            return .pink
        case .codexPrimary:
            return Color(red: 45/255.0, green: 212/255.0, blue: 191/255.0)   // #2DD4BF
        case .codexSecondary:
            return Color(red: 96/255.0, green: 165/255.0, blue: 250/255.0)   // #60A5FA
        case .codexExtraUsage:
            return Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0)    // #F59E0B
        }
    }

    private var percentageValue: Double? {
        if let override = weeklyModelOverride {
            return override.limit.percentage
        }
        switch type {
        case .fiveHour:       return data?.fiveHour?.percentage
        case .sevenDay:       return data?.sevenDay?.percentage
        case .opusWeekly:     return data?.opus?.percentage
        case .sonnetWeekly:   return data?.sonnet?.percentage
        case .extraUsage:     return data?.extraUsage?.percentage
        case .codexPrimary:   return codexData?.primary?.percentage
        case .codexSecondary: return codexData?.secondary?.percentage
        case .codexExtraUsage: return codexData?.extraUsage?.percentage
        }
    }

    private var displayValue: String {
        if let override = weeklyModelOverride {
            return showRemainingMode
                ? override.limit.formattedCompactRemaining
                : override.limit.formattedCompactResetDate
        }
        switch type {
        case .fiveHour:
            guard let fiveHour = data?.fiveHour else { return "-" }
            return showRemainingMode ? fiveHour.formattedCompactRemaining : detailCompactResetTime(fiveHour)

        case .sevenDay:
            guard let sevenDay = data?.sevenDay else { return "-" }
            return showRemainingMode ? sevenDay.formattedCompactRemaining : sevenDay.formattedCompactResetDate

        case .opusWeekly:
            guard let opus = data?.opus else { return "-" }
            return showRemainingMode ? opus.formattedCompactRemaining : opus.formattedCompactResetDate

        case .sonnetWeekly:
            guard let sonnet = data?.sonnet else { return "-" }
            return showRemainingMode ? sonnet.formattedCompactRemaining : sonnet.formattedCompactResetDate

        case .extraUsage:
            guard let extra = data?.extraUsage else { return "-" }
            return showRemainingMode ? extra.formattedRemainingAmount : extra.formattedCompactAmount

        case .codexPrimary:
            guard let limitData = codexData?.primary?.asUsageLimitData() else { return "-" }
            return showRemainingMode ? limitData.formattedCompactRemaining : detailCompactResetTime(limitData)

        case .codexSecondary:
            guard let limitData = codexData?.secondary?.asUsageLimitData() else { return "-" }
            // Two units, days plus hours, like every other row: minutes on a multi day countdown are just noise
            return showRemainingMode ? limitData.formattedCompactRemaining : limitData.formattedCompactResetDateWithMinutes

        case .codexExtraUsage:
            guard let extra = codexData?.extraUsage else { return "-" }
            return showRemainingMode ? extra.formattedDetailRemainingAmount : extra.formattedDetailCompactAmount
        }
    }

    private func detailCompactResetTime(_ limitData: UsageData.LimitData) -> String {
        guard let resetsAt = limitData.resetsAt else {
            return "-"
        }

        var calendar = Calendar.current
        calendar.locale = UserSettings.shared.appLocale
        let timeString = TimeFormatHelper.formatTimeOnly(resetsAt)

        if calendar.isDateInToday(resetsAt) {
            return "\(L.DetailRow.today) \(timeString)"
        }
        if calendar.isDateInTomorrow(resetsAt) {
            return "\(L.UsageData.tomorrow) \(timeString)"
        }
        return TimeFormatHelper.formatDateTime(resetsAt, dateTemplate: "Md")
    }
}
