//
//  ShapeIconRenderer.swift
//  ClaudeUsage
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import SwiftUI

/// Shape icon renderer
/// Draws the progress ring for the non circular icons (square, diamond, hexagon)
class ShapeIconRenderer {

    // MARK: - Helper Methods

    /// Compute the opacity for the monochrome theme (from the percentage)
    /// - Parameter percentage: usage percentage (0-100)
    /// - Returns: opacity (0.8-1.0)
    static func monochromeOpacity(for percentage: Double) -> CGFloat {
        if percentage <= 50 {
            return 0.8
        } else if percentage <= 75 {
            return 0.9
        } else {
            return 1.0
        }
    }

    // MARK: - Shape Drawing Methods

    /// Draw the rounded square progress ring and percentage (used by Opus)
    /// - Parameters:
    ///   - rect: drawing area
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button (used to read colors)
    ///   - removeBackground: whether to remove the background fill
    static func drawRoundedSquareWithPercentage(in rect: NSRect, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) {
        // Battery style display: the progress border and the glyph show remaining; colors stay keyed off used
        let displayPercentage = UsagePercentDisplay.displayPercentage(percentage)
        let cornerRadius: CGFloat = 3.0
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress stroke
        let center = NSPoint(x: rect.midX, y: rect.midY)

        // 1. Draw the background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            let backgroundFillPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.withAlphaComponent(0.5).setFill()
            backgroundFillPath.fill()
        }

        // 2. Draw the background border
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            NSColor.gray.withAlphaComponent(0.5).setStroke()
        }
        backgroundPath.lineWidth = borderWidth
        backgroundPath.stroke()

        // 2. Draw the progress border (clockwise, starting at 12 o'clock)
        if displayPercentage > 0 {
            // Compute the real perimeter of the rounded square
            // Perimeter = 4 straight segments + 4 corner arcs
            // Total straight length = 4 * (side - 2*cornerRadius)
            // Total arc length = 4 * (pi*cornerRadius/2) = 2*pi*cornerRadius
            let straightLength = 4 * (rect.width - 2 * cornerRadius)
            let arcLength = 2 * CGFloat.pi * cornerRadius
            let perimeter = straightLength + arcLength

            // Compute the progress length
            // Progressive subtraction: the amount subtracted grows linearly with the percentage and is fully applied at 50%
            // Below 50%: smooth ramp, the subtracted amount goes from 0 up to progressWidth
            // At or above 50%: exact, always subtract the full progressWidth
            // At 100% nothing is subtracted because .butt caps are used (no overhang)
            let baseProgressLength = perimeter * CGFloat(displayPercentage / 100.0)
            let progressLength = displayPercentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(displayPercentage / 50.0)))

            // Build the clockwise path from 12 o'clock by hand
            let progressPath = NSBezierPath()

            // Start at 12 o'clock (middle of the top edge)
            let startPoint = NSPoint(x: rect.midX, y: rect.maxY)
            progressPath.move(to: startPoint)

            // Clockwise: 12 o'clock to 3 to 6 to 9 and back to 12
            // Top right corner (the corner radius has to be accounted for)
            progressPath.line(to: NSPoint(x: rect.maxX - cornerRadius, y: rect.maxY))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 90,
                endAngle: 0,
                clockwise: true
            )

            // Right edge down to the bottom right corner
            progressPath.line(to: NSPoint(x: rect.maxX, y: rect.minY + cornerRadius))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 0,
                endAngle: 270,
                clockwise: true
            )

            // Bottom edge to the bottom left corner
            progressPath.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.minY))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 270,
                endAngle: 180,
                clockwise: true
            )

            // Left edge to the top left corner
            progressPath.line(to: NSPoint(x: rect.minX, y: rect.maxY - cornerRadius))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 180,
                endAngle: 90,
                clockwise: true
            )

            // Top edge back to the start
            progressPath.line(to: startPoint)

            // Draw with a dash pattern
            // Below 100% a negative phase pre draws half a round cap at the start, so the subtracted lineWidth is split evenly across both ends
            let phase: CGFloat = displayPercentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressPath.setLineDash(pattern, count: 2, phase: phase)
            progressPath.lineWidth = progressWidth
            // At 100% butt caps close the shape perfectly, every other value uses round caps
            progressPath.lineCapStyle = displayPercentage >= 100 ? .butt : .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else {
                UsageColorScheme.opusWeeklyColorAdaptive(percentage, for: button).setStroke()
            }
            progressPath.stroke()
        }

        // 3. Draw the percentage text
        let percentageText = "\(Int(displayPercentage))"
        let percentageFontSize: CGFloat = displayPercentage >= 100 ? 5.0 : 7.2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: percentageFontSize, weight: displayPercentage >= 100 ? .bold : .semibold),
            .foregroundColor: UsageColorScheme.menuBarForeground(for: button)
        ]
        let textSize = percentageText.size(withAttributes: attributes)
        let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
        percentageText.draw(in: textRect, withAttributes: attributes)
    }

    /// Draw the diamond progress ring and percentage (used by Sonnet, a square rotated 45 degrees)
    /// - Parameters:
    ///   - rect: drawing area
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button (used to read colors)
    ///   - removeBackground: whether to remove the background fill
    static func drawDiamondWithPercentage(in rect: NSRect, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) {
        // Battery style display: the progress border and the glyph show remaining; colors stay keyed off used
        let displayPercentage = UsagePercentDisplay.displayPercentage(percentage)
        // Exactly the same parameters as Opus
        let cornerRadius: CGFloat = 3.0
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress stroke
        let cutSize: CGFloat = 3.5  // Size of the top right chamfer (nudged slightly smaller)
        let center = NSPoint(x: rect.midX, y: rect.midY)

        // Build the rounded rect path with a chamfered top right corner (same as Opus, only that corner is cut)
        func createChamferedRectPath(_ rect: NSRect) -> NSBezierPath {
            let path = NSBezierPath()

            // Start at the bottom left corner (rounded)
            path.move(to: NSPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 180,
                endAngle: 270,
                clockwise: false
            )

            // Bottom edge to the bottom right corner (rounded)
            path.line(to: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 270,
                endAngle: 0,
                clockwise: false
            )

            // Right edge up to the chamfer
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cutSize))

            // Chamfer line
            path.line(to: NSPoint(x: rect.maxX - cutSize, y: rect.maxY))

            // Top edge to the top left corner (rounded)
            path.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 90,
                endAngle: 180,
                clockwise: false
            )

            // Back to the start
            path.close()

            return path
        }

        // 1. Draw the background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            let backgroundFillPath = createChamferedRectPath(rect)
            NSColor.white.withAlphaComponent(0.5).setFill()
            backgroundFillPath.fill()
        }

        // 2. Draw the background border (exactly as Opus does)
        let backgroundPath = createChamferedRectPath(rect)
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            NSColor.gray.withAlphaComponent(0.5).setStroke()
        }
        backgroundPath.lineWidth = borderWidth
        backgroundPath.stroke()

        // 2. Draw the progress border (clockwise, starting at 12 o'clock)
        if displayPercentage > 0 {
            // Build the clockwise path from 12 o'clock by hand (with the top right chamfer)
            let progressPath = NSBezierPath()

            // Start at 12 o'clock (middle of the top edge)
            let startPoint = NSPoint(x: rect.midX, y: rect.maxY)
            progressPath.move(to: startPoint)

            // Clockwise: 12 o'clock to the top right chamfer to 3 to 6 to 9 and back to 12
            // Top edge to the start of the top right chamfer
            progressPath.line(to: NSPoint(x: rect.maxX - cutSize, y: rect.maxY))

            // The top right chamfer line
            progressPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cutSize))

            // Right edge down to the bottom right corner
            progressPath.line(to: NSPoint(x: rect.maxX, y: rect.minY + cornerRadius))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 0,
                endAngle: 270,
                clockwise: true
            )

            // Bottom edge to the bottom left corner
            progressPath.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.minY))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 270,
                endAngle: 180,
                clockwise: true
            )

            // Left edge to the top left corner
            progressPath.line(to: NSPoint(x: rect.minX, y: rect.maxY - cornerRadius))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 180,
                endAngle: 90,
                clockwise: true
            )

            // Top edge back to the start
            progressPath.line(to: startPoint)

            // Compute the real perimeter of the chamfered square
            // Start from the Opus rounded square perimeter, then adjust for the chamfer:
            // 1. Opus perimeter = 4 straight segments + 4 corner arcs
            let opusStraightLength = 4 * (rect.width - 2 * cornerRadius)
            let opusArcLength = 2 * CGFloat.pi * cornerRadius
            let opusPerimeter = opusStraightLength + opusArcLength

            // 2. Sonnet's top right chamfer means:
            //    - one 90 degree corner arc is gone: -cornerRadius * pi/2
            //    - the top edge goes from (width-2*corner) to (width-corner-cut): +cornerRadius-cutSize
            //    - the right edge goes from (width-2*corner) to (width-corner-cut): +cornerRadius-cutSize
            //    - the chamfer line is added: +cutSize * sqrt(2)
            //    Total: 2*cornerRadius - 2*cutSize + cutSize*sqrt(2) - cornerRadius*pi/2
            let cornerArcReduction = -cornerRadius * .pi / 2
            let edgeAdjustment = 2.0 * cornerRadius
            let cutAdjustment = cutSize * (sqrt(2.0) - 2.0)
            let perimeter = opusPerimeter + cornerArcReduction + edgeAdjustment + cutAdjustment

            // Compute the progress length
            // Progressive subtraction: the amount subtracted grows linearly with the percentage and is fully applied at 50%
            // Below 50%: smooth ramp, the subtracted amount goes from 0 up to progressWidth
            // At or above 50%: exact, always subtract the full progressWidth
            // At 100% nothing is subtracted because .butt caps are used (no overhang)
            let baseProgressLength = perimeter * CGFloat(displayPercentage / 100.0)
            let progressLength = displayPercentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(displayPercentage / 50.0)))

            // Draw with a dash pattern
            // Below 100% a negative phase pre draws half a round cap at the start, so the subtracted lineWidth is split evenly across both ends
            let phase: CGFloat = displayPercentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressPath.setLineDash(pattern, count: 2, phase: phase)
            progressPath.lineWidth = progressWidth
            // At 100% butt caps close the shape perfectly, every other value uses round caps
            progressPath.lineCapStyle = displayPercentage >= 100 ? .butt : .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else {
                UsageColorScheme.sonnetWeeklyColorAdaptive(percentage, for: button).setStroke()
            }
            progressPath.stroke()
        }

        // 3. Draw the percentage text (exactly as Opus does)
        let percentageText = "\(Int(displayPercentage))"
        let percentageFontSize: CGFloat = displayPercentage >= 100 ? 5.0 : 7.2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: percentageFontSize, weight: displayPercentage >= 100 ? .bold : .semibold),
            .foregroundColor: UsageColorScheme.menuBarForeground(for: button)
        ]
        let textSize = percentageText.size(withAttributes: attributes)
        let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
        percentageText.draw(in: textRect, withAttributes: attributes)
    }

    /// Draw the flat top hexagon progress ring and percentage (used by Extra Usage)
    /// - Parameters:
    ///   - center: center point
    ///   - size: hexagon size
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button (used to read colors)
    ///   - removeBackground: whether to remove the background fill
    static func drawHexagonWithPercentage(center: NSPoint, size: CGFloat, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false, colorOverride: NSColor? = nil) {
        let radius = size / 2
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress stroke

        // Build the flat top hexagon path (flat top means the top and bottom edges are flat)
        let hexagonPath = NSBezierPath()
        for i in 0..<6 {
            let angle = CGFloat(i) * CGFloat.pi / 3.0  // Keep the flat top orientation
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            if i == 0 {
                hexagonPath.move(to: NSPoint(x: x, y: y))
            } else {
                hexagonPath.line(to: NSPoint(x: x, y: y))
            }
        }
        hexagonPath.close()

        // 1. Draw the background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            NSColor.white.withAlphaComponent(0.5).setFill()
            hexagonPath.fill()
        }

        // 2. Draw the background border
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            NSColor.gray.withAlphaComponent(0.5).setStroke()
        }
        hexagonPath.lineWidth = borderWidth
        hexagonPath.lineJoinStyle = .round
        hexagonPath.stroke()

        // 2. Draw the progress border
        if percentage > 0 {
            // Compute the hexagon perimeter
            let sideLength = radius  // Every side of a regular hexagon is as long as its radius
            let perimeter = sideLength * 6

            // Compute the progress length
            // Progressive subtraction: the amount subtracted grows linearly with the percentage and is fully applied at 50%
            // Below 50%: smooth ramp, the subtracted amount goes from 0 up to progressWidth
            // At or above 50%: exact, always subtract the full progressWidth
            // At 100% nothing is subtracted because .butt caps are used (no overhang)
            let baseProgressLength = perimeter * CGFloat(percentage / 100.0)
            let progressLength = percentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(percentage / 50.0)))

            // Build the clockwise path from the top by hand, starting at 12 o'clock
            // First compute the 6 vertex positions (keeping the flat top orientation)
            var vertices: [NSPoint] = []
            for i in 0..<6 {
                let angle = CGFloat(i) * CGFloat.pi / 3.0
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                vertices.append(NSPoint(x: x, y: y))
            }
            // vertices[0] = 3 o'clock (right)
            // vertices[1] = 1 o'clock (upper right)
            // vertices[2] = 11 o'clock (upper left)
            // vertices[3] = 9 o'clock (left)
            // vertices[4] = 7 o'clock (lower left)
            // vertices[5] = 5 o'clock (lower right)

            // Start at 12 o'clock (the top edge midpoint, between vertices[1] and vertices[2])
            let topMidpoint = NSPoint(
                x: (vertices[1].x + vertices[2].x) / 2,
                y: (vertices[1].y + vertices[2].y) / 2
            )

            let progressHexagon = NSBezierPath()
            progressHexagon.move(to: topMidpoint)

            // Clockwise: 12 to 1 to 3 to 5 to 7 to 9 to 11 and back to 12
            progressHexagon.line(to: vertices[1])  // To the 1 o'clock vertex
            progressHexagon.line(to: vertices[0])  // To the 3 o'clock vertex
            progressHexagon.line(to: vertices[5])  // To the 5 o'clock vertex
            progressHexagon.line(to: vertices[4])  // To the 7 o'clock vertex
            progressHexagon.line(to: vertices[3])  // To the 9 o'clock vertex
            progressHexagon.line(to: vertices[2])  // To the 11 o'clock vertex
            progressHexagon.line(to: topMidpoint)  // Back to 12 o'clock

            // Draw with a dash pattern
            // Below 100% a negative phase pre draws half a round cap at the start, so the subtracted lineWidth is split evenly across both ends
            let phase: CGFloat = percentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressHexagon.setLineDash(pattern, count: 2, phase: phase)
            progressHexagon.lineWidth = progressWidth
            // At 100% butt caps close the shape perfectly, every other value uses round caps
            progressHexagon.lineCapStyle = percentage >= 100 ? .butt : .round
            progressHexagon.lineJoinStyle = .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else if let colorOverride {
                colorOverride.setStroke()
            } else {
                UsageColorScheme.extraUsageColorAdaptive(percentage, for: button).setStroke()
            }
            progressHexagon.stroke()
        }

        // 3. Draw the percentage text
        let percentageText = "\(Int(percentage))"
        let percentageFontSize: CGFloat = percentage >= 100 ? 5.0 : 7.2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: percentageFontSize, weight: percentage >= 100 ? .bold : .semibold),
            .foregroundColor: UsageColorScheme.menuBarForeground(for: button)
        ]
        let textSize = percentageText.size(withAttributes: attributes)
        let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
        percentageText.draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - Icon Creation Methods

    /// Create the rounded square icon (Opus)
    /// - Parameters:
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button
    ///   - removeBackground: whether to remove the background fill
    /// - Returns: icon image (18x18)
    static func createVerticalRectangleIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: 2, dy: 2)
        drawRoundedSquareWithPercentage(in: rect, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }

    /// Create the diamond icon (Sonnet, a square rotated 45 degrees)
    /// - Parameters:
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button
    ///   - removeBackground: whether to remove the background fill
    /// - Returns: icon image (18x18)
    static func createHorizontalRectangleIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: 2, dy: 2)
        drawDiamondWithPercentage(in: rect, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }

    /// Create the flat top hexagon icon (Extra Usage)
    /// - Parameters:
    ///   - percentage: usage percentage
    ///   - isMonochrome: whether monochrome mode is active
    ///   - button: status item button
    ///   - removeBackground: whether to remove the background (false by default)
    /// - Returns: icon image (18x18)
    static func createHexagonIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false, colorOverride: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        drawHexagonWithPercentage(center: center, size: 16, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, colorOverride: colorOverride)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }
}
