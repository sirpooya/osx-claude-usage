//
//  UsagePaceStatus.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2026-08-22.
//

import AppKit
import SwiftUI

/// Three step pace ramp, used to colour the period tick on a limit bar.
///
/// The reading is always "how far ahead of the clock am I". Projected under 70% of the cap means
/// the pace is sustainable for the rest of the window, so the tick stays blue. Past that it goes
/// orange, then red once the projection is close enough to the cap that the window ends at it.
/// More usage per unit of elapsed time is always worse, so the ramp only ever escalates.
///
/// Blue rather than green for the healthy step: the five hour limit's own bar is already green, so
/// a green tick would blur into the fill on that row.
enum UsagePaceStatus: Int, Comparable, CaseIterable {
    case onPace  = 0   // projected under 70%, sustainable
    case ahead   = 1   // projected 70-90%, pulling ahead of the clock
    case overrun = 2   // projected 90% or more, on course to hit the cap

    static func < (lhs: UsagePaceStatus, rhs: UsagePaceStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Below this much of the window elapsed there is nothing worth projecting from.
    ///
    /// Much lower than `UsagePaceCalculator.minimumElapsedFraction` (15%) on purpose. That gate
    /// protects the bar's own colour, which turning red seconds into a window would misreport;
    /// this one only tints a 2pt tick, so an early reading is cheap and useful.
    static let minimumElapsedFraction: Double = 0.03

    /// Pace step from the usage so far and how much of the window has gone.
    /// nil when the window has barely started or has already lapsed, in which case callers leave
    /// the tick its neutral colour.
    static func calculate(usedPercentage: Double, elapsedFraction: Double) -> UsagePaceStatus? {
        guard elapsedFraction >= minimumElapsedFraction, elapsedFraction < 1.0 else { return nil }
        guard usedPercentage > 0 else { return .onPace }
        let projected = (usedPercentage / 100.0) / elapsedFraction
        switch projected {
        case ..<0.70:     return .onPace
        case 0.70..<0.90: return .ahead
        default:          return .overrun
        }
    }

    /// The bar / icon colour. System colours, so each one adapts to light and dark itself.
    var nsColor: NSColor {
        switch self {
        case .onPace:  return .systemBlue
        case .ahead:   return .systemOrange
        case .overrun: return .systemRed
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// The ramp colour for one limit, straight from its percentage and reset time, or nil when
    /// there is nothing to project from and the caller should keep its own palette.
    ///
    /// The single entry point for both the popover bars and the menu bar icons, so the two cannot
    /// disagree about what colour a given pace is.
    static func color(
        usedPercentage: Double,
        resetsAt: Date?,
        type: LimitType,
        now: Date = Date()
    ) -> UsagePaceStatus? {
        guard let duration = UsagePaceCalculator.windowDuration(for: type),
              let elapsed = UsagePaceCalculator.elapsedFraction(
                  resetsAt: resetsAt,
                  duration: duration,
                  now: now
              )
        else { return nil }
        return calculate(usedPercentage: usedPercentage, elapsedFraction: elapsed)
    }
}
