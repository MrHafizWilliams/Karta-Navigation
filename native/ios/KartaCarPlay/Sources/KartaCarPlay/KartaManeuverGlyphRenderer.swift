#if canImport(CarPlay) && canImport(UIKit)
import CarPlay
import UIKit

/// Flagship high-contrast automotive renderer generating:
/// 1. Heavy-stroke (14%) WCAG AAA vector maneuver arrows distinguishing slight (45°),
///    normal (90°), sharp (135°), U-turns, ramps/merges, and MY/SG/BN clockwise roundabouts.
/// 2. Dual-theme (`Obsidian Night` & `Tropical Daylight`) `320x68` compound lane-guidance
///    strips rendering all semicolon OSM tokens (`through;right`) with filled arrowheads,
///    lane dividers, and MY/SG/BN toll payment chips (`RFID`, `SmartTAG`, `TnG`, `ERP`).
/// 3. Native iOS 17.4+ `CPLaneGuidance` objects.
/// 4. Rotary-controller focus-ring action icons for the 3-action zero-distraction strip.
public enum KartaManeuverGlyphRenderer {

    /// High-contrast geometric vector turn arrow matching WCAG AAA contrast across
    /// Obsidian Night (`#FFFFFF`) and Tropical Daylight (`#11161C`).
    public static func maneuverSymbolImage(
        valhallaType: Int,
        isLeftHandTraffic: Bool = true,
        theme: KartaCarPlayTheme = .obsidianNight,
        size: CGSize = CGSize(width: 56, height: 56),
        isSecondary: Bool = false
    ) -> UIImage {
        let primaryInk = isSecondary ? theme.textSecondary : theme.arrowInk
        let accentInk = theme.accentBright
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            let w = size.width
            let h = size.height
            let strokeW = w * (isSecondary ? 0.11 : 0.145)

            cg.setStrokeColor(primaryInk.cgColor)
            cg.setFillColor(primaryInk.cgColor)
            cg.setLineWidth(strokeW)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            func drawHead(tip: CGPoint, angleRad: CGFloat, color: UIColor = primaryInk) {
                let len = w * 0.27
                let spread: CGFloat = 0.54
                let p1 = CGPoint(x: tip.x - len * cos(angleRad - spread), y: tip.y - len * sin(angleRad - spread))
                let p2 = CGPoint(x: tip.x - len * cos(angleRad + spread), y: tip.y - len * sin(angleRad + spread))
                cg.saveGState()
                cg.setFillColor(color.cgColor)
                cg.beginPath()
                cg.move(to: tip)
                cg.addLine(to: p1)
                cg.addLine(to: p2)
                cg.closePath()
                cg.fillPath()
                cg.restoreGState()
            }

            switch valhallaType {
            // Destination (4, 5, 6)
            case 4, 5, 6:
                cg.setStrokeColor(accentInk.cgColor)
                cg.setFillColor(accentInk.cgColor)
                let ring = CGRect(x: w * 0.28, y: h * 0.16, width: w * 0.44, height: h * 0.44)
                cg.strokeEllipse(in: ring)
                cg.fillEllipse(in: ring.insetBy(dx: w * 0.13, dy: h * 0.13))
                cg.move(to: CGPoint(x: w * 0.5, y: h * 0.62))
                cg.addLine(to: CGPoint(x: w * 0.5, y: h * 0.88))
                cg.strokePath()

            // Slight right (9), Ramp/Exit/Keep/Merge right (18, 20, 23, 25) -> crisp 45° right
            case 9, 18, 20, 23, 25:
                if valhallaType == 23 || valhallaType == 25 {
                    // Subtle ghosted through stem for lane split/merge clarity
                    cg.saveGState()
                    cg.setStrokeColor(theme.textSecondary.withAlphaComponent(0.38).cgColor)
                    cg.setLineWidth(strokeW * 0.72)
                    cg.move(to: CGPoint(x: w * 0.34, y: h * 0.86))
                    cg.addLine(to: CGPoint(x: w * 0.34, y: h * 0.20))
                    cg.strokePath()
                    cg.restoreGState()
                }
                cg.move(to: CGPoint(x: w * 0.34, y: h * 0.86))
                cg.addLine(to: CGPoint(x: w * 0.34, y: h * 0.52))
                cg.addLine(to: CGPoint(x: w * 0.68, y: h * 0.22))
                cg.strokePath()
                drawHead(tip: CGPoint(x: w * 0.76, y: h * 0.15), angleRad: -.pi / 4)

            // Normal right turn (10) -> crisp 90° right
            case 10:
                cg.move(to: CGPoint(x: w * 0.28, y: h * 0.86))
                cg.addLine(to: CGPoint(x: w * 0.28, y: h * 0.42))
                cg.addQuadCurve(to: CGPoint(x: w * 0.44, y: h * 0.30), control: CGPoint(x: w * 0.28, y: h * 0.30))
                cg.addLine(to: CGPoint(x: w * 0.70, y: h * 0.30))
                cg.strokePath()
                drawHead(tip: CGPoint(x: w * 0.84, y: h * 0.30), angleRad: 0)

            // Sharp right turn (11) -> crisp 135° hairpin right
            case 11:
                cg.move(to: CGPoint(x: w * 0.26, y: h * 0.86))
                cg.addLine(to: CGPoint(x: w * 0.26, y: h * 0.28))
                cg.addLine(to: CGPoint(x: w * 0.68, y: h * 0.62))
                cg.strokePath()
                drawHead(tip: CGPoint(x: w * 0.78, y: h * 0.70), angleRad: .pi / 4)

            // U-turn right (12) / U-turn left (13)
            case 12, 13:
                let isLeft = (valhallaType == 13)
                let xStart = isLeft ? w * 0.70 : w * 0.30
                let xEnd = isLeft ? w * 0.28 : w * 0.72
                let radius = abs(xEnd - xStart) * 0.5
                cg.move(to: CGPoint(x: xStart, y: h * 0.86))
                cg.addLine(to: CGPoint(x: xStart, y: h * 0.36))
                cg.addArc(
                    center: CGPoint(x: (xStart + xEnd) * 0.5, y: h * 0.36),
                    radius: radius,
                    startAngle: isLeft ? 0 : .pi,
                    endAngle: isLeft ? .pi : 0,
                    clockwise: isLeft
                )
                cg.addLine(to: CGPoint(x: xEnd, y: h * 0.62))
                cg.strokePath()
                drawHead(tip: CGPoint(x: xEnd, y: h * 0.76), angleRad: .pi / 2)

            // Sharp left turn (14) -> crisp 135° hairpin left
            case 14:
                cg.move(to: CGPoint(x: w * 0.74, y: h * 0.86))
                cg.addLine(to: CGPoint(x: w * 0.74, y: h * 0.28))
                cg.addLine(to: CGPoint(x: w * 0.32, y: h * 0.62))
                cg.strokePath()
                drawHead(tip: CGPoint(x: w * 0.22, y: h * 0.70), angleRad: 3 * .pi / 4)

            // Normal left turn (15) -> crisp 90° left
            case 15:
                cg.move(to: CGPoint(x: w * 0.72, y: h * 0.86))
                cg.addLine(to: CGPoint(x: w * 0.72, y: h * 0.42))
                cg.addQuadCurve(to: CGPoint(x: w * 0.56, y: h * 0.30), control: CGPoint(x: w * 0.72, y: h * 0.30))
                cg.addLine(to: CGPoint(x: w * 0.30, y: h * 0.30))
                cg.strokePath()
                drawHead(tip: CGPoint(x: w * 0.16, y: h * 0.30), angleRad: .pi)

            // Slight left (16), Ramp/Exit/Keep/Merge left (19, 21, 24, 26) -> crisp 45° left
            case 16, 19, 21, 24, 26:
                if valhallaType == 24 || valhallaType == 26 {
                    cg.saveGState()
                    cg.setStrokeColor(theme.textSecondary.withAlphaComponent(0.38).cgColor)
                    cg.setLineWidth(strokeW * 0.72)
                    cg.move(to: CGPoint(x: w * 0.66, y: h * 0.86))
                    cg.addLine(to: CGPoint(x: w * 0.66, y: h * 0.20))
                    cg.strokePath()
                    cg.restoreGState()
                }
                cg.move(to: CGPoint(x: w * 0.66, y: h * 0.86))
                cg.addLine(to: CGPoint(x: w * 0.66, y: h * 0.52))
                cg.addLine(to: CGPoint(x: w * 0.32, y: h * 0.22))
                cg.strokePath()
                drawHead(tip: CGPoint(x: w * 0.24, y: h * 0.15), angleRad: -3 * .pi / 4)

            // Roundabout (27, 28) — clockwise for MY / SG / BN left-hand traffic
            case 27, 28:
                let ringCenter = CGPoint(x: w * 0.5, y: h * 0.48)
                let ringRadius = w * 0.20
                cg.saveGState()
                cg.setStrokeColor(theme.textSecondary.withAlphaComponent(0.42).cgColor)
                cg.setLineWidth(strokeW * 0.78)
                cg.strokeEllipse(in: CGRect(
                    x: ringCenter.x - ringRadius,
                    y: ringCenter.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                ))
                cg.restoreGState()

                // Highlighted entry -> arc -> exit
                cg.move(to: CGPoint(x: w * 0.5, y: h * 0.88))
                cg.addLine(to: CGPoint(x: w * 0.5, y: ringCenter.y + ringRadius))
                cg.addArc(
                    center: ringCenter,
                    radius: ringRadius,
                    startAngle: .pi / 2,
                    endAngle: -.pi / 2,
                    clockwise: isLeftHandTraffic
                )
                cg.addLine(to: CGPoint(x: w * 0.5, y: h * 0.16))
                cg.strokePath()
                drawHead(tip: CGPoint(x: w * 0.5, y: h * 0.08), angleRad: -.pi / 2)

            // Straight / Continue / Start
            default:
                cg.move(to: CGPoint(x: w * 0.5, y: h * 0.86))
                cg.addLine(to: CGPoint(x: w * 0.5, y: h * 0.24))
                cg.strokePath()
                drawHead(tip: CGPoint(x: w * 0.5, y: h * 0.12), angleRad: -.pi / 2)
            }
        }
    }

    /// Builds native iOS 17.4+ `CPLaneGuidance` from Karta's structured `KartaCarPlayLaneItem`s.
    @available(iOS 17.4, *)
    public static func buildNativeLaneGuidance(
        lanes: [KartaCarPlayLaneItem],
        instructionVariants: [String]
    ) -> CPLaneGuidance? {
        guard !lanes.isEmpty else { return nil }
        let cpLanes: [CPLane] = lanes.prefix(6).map { item in
            let parsedAngles = laneAngles(from: item.laneSpec)
            let primaryAngle = parsedAngles.first ?? Measurement(value: 0, unit: UnitAngle.degrees)
            if item.isRecommended {
                return CPLane(
                    angles: parsedAngles,
                    highlightedAngle: primaryAngle,
                    isPreferred: true
                )
            } else {
                return CPLane(angles: parsedAngles)
            }
        }
        let guidance = CPLaneGuidance()
        guidance.lanes = cpLanes
        guidance.instructionVariants = instructionVariants
        return guidance
    }

    /// Renders a wide-format, theme-adaptive `320x68` lane-guidance & MY/SG/BN toll-payment strip
    /// (`junctionImage`) displaying ALL compound semicolon lane tokens, crisp filled arrowheads,
    /// vertical lane dividers, and payment chips (`RFID` / `SmartTAG` / `TnG` / `ERP`).
    public static func renderLaneAndTollStripImage(
        lanes: [KartaCarPlayLaneItem],
        approachingTollPayments: [String],
        approachingTollName: String?,
        theme: KartaCarPlayTheme = .obsidianNight,
        size: CGSize = CGSize(width: 320, height: 68)
    ) -> UIImage? {
        guard !lanes.isEmpty || !approachingTollPayments.isEmpty else { return nil }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let bounds = CGRect(origin: .zero, size: size)

            let bgPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 12)
            theme.surfaceCard.setFill()
            bgPath.fill()

            let borderColor = approachingTollName != nil
                ? theme.statusCaution
                : theme.accentPrimary.withAlphaComponent(0.75)
            borderColor.setStroke()
            bgPath.lineWidth = 1.8
            bgPath.stroke()

            let displayLanes = Array(lanes.prefix(5))
            let badges = Array(approachingTollPayments.prefix(3))
            let badgeAreaWidth: CGFloat = badges.isEmpty ? 0 : CGFloat(badges.count) * 52 + 12
            let laneAreaWidth = max(120, size.width - 20 - badgeAreaWidth)
            let slotW = displayLanes.isEmpty ? 0 : min(46.0, laneAreaWidth / CGFloat(displayLanes.count))
            var xCursor: CGFloat = 10

            for (idx, lane) in displayLanes.enumerated() {
                let boxRect = CGRect(x: xCursor, y: 8, width: slotW - 4, height: size.height - 16)
                let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
                if lane.isRecommended {
                    theme.accentPrimary.withAlphaComponent(theme.isDarkMode ? 0.34 : 0.18).setFill()
                    boxPath.fill()
                    theme.accentBright.setStroke()
                    boxPath.lineWidth = 1.8
                    boxPath.stroke()
                }
                drawCompoundLaneTokens(
                    lane.laneSpec,
                    in: boxRect.insetBy(dx: 5, dy: 6),
                    color: lane.isRecommended
                        ? theme.arrowInk
                        : theme.textSecondary.withAlphaComponent(0.34),
                    lineWidth: lane.isRecommended ? 3.2 : 2.2,
                    context: cg
                )

                // Dashed road lane divider between adjacent slots
                if idx < displayLanes.count - 1 {
                    cg.saveGState()
                    cg.setStrokeColor(theme.borderSubtle.cgColor)
                    cg.setLineWidth(1.2)
                    cg.setLineDash(phase: 0, lengths: [4, 4])
                    let divX = xCursor + slotW - 2
                    cg.move(to: CGPoint(x: divX, y: 12))
                    cg.addLine(to: CGPoint(x: divX, y: size.height - 12))
                    cg.strokePath()
                    cg.restoreGState()
                }
                xCursor += slotW
            }

            if !badges.isEmpty {
                xCursor = max(xCursor + 6, 12)
                for wire in badges {
                    let label = shortPaymentBadge(wire)
                    let chipRect = CGRect(x: xCursor, y: 19, width: 48, height: 30)
                    if chipRect.maxX > size.width - 8 { break }
                    let chipColor = paymentAccentColor(wire, theme: theme)
                    let chipPath = UIBezierPath(roundedRect: chipRect, cornerRadius: 7)
                    chipColor.withAlphaComponent(theme.isDarkMode ? 0.28 : 0.18).setFill()
                    chipPath.fill()
                    chipColor.setStroke()
                    chipPath.lineWidth = 1.5
                    chipPath.stroke()

                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.monospacedSystemFont(ofSize: 10.5, weight: .heavy),
                        .foregroundColor: theme.textPrimary
                    ]
                    let textSize = (label as NSString).size(withAttributes: attrs)
                    let textOrigin = CGPoint(
                        x: chipRect.midX - textSize.width / 2,
                        y: chipRect.midY - textSize.height / 2
                    )
                    (label as NSString).draw(at: textOrigin, withAttributes: attrs)
                    xCursor += 52
                }
            }
        }
    }

    /// Renders a rotary-focus-ring icon for CarPlay's 3 primary one-tap actions
    /// (`Voice Report`, `Guidance Audio`, `Route Overview / Cancel`) and minimal map controls.
    public static func rotaryActionIcon(
        sfSymbol: String,
        theme: KartaCarPlayTheme,
        highlighted: Bool = false,
        destructive: Bool = false,
        size: CGSize = CGSize(width: 30, height: 30)
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let ringColor = destructive
                ? theme.statusAlert
                : (highlighted ? theme.rotaryFocusRing : theme.borderSubtle)

            let circle = UIBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            if highlighted || destructive {
                ringColor.withAlphaComponent(theme.isDarkMode ? 0.28 : 0.16).setFill()
                circle.fill()
            }
            ringColor.setStroke()
            circle.lineWidth = highlighted ? 2.0 : 1.4
            circle.stroke()

            let cfg = UIImage.SymbolConfiguration(pointSize: size.width * 0.46, weight: .bold)
            let symTint = destructive
                ? theme.statusAlert
                : (highlighted ? theme.rotaryFocusRing : theme.textPrimary)
            if let sym = UIImage(systemName: sfSymbol, withConfiguration: cfg)?
                .withTintColor(symTint, renderingMode: .alwaysOriginal) {
                let s = sym.size
                sym.draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2))
            }
        }
    }

    /// Renders a high-contrast SF Symbol badge for the 6-sector Quick-Hazard Grid.
    public static func hazardGridIcon(
        sfSymbol: String,
        accent: UIColor,
        theme: KartaCarPlayTheme = .obsidianNight,
        size: CGSize = CGSize(width: 60, height: 60)
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let circle = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            accent.withAlphaComponent(theme.isDarkMode ? 0.26 : 0.16).setFill()
            circle.fill()
            accent.setStroke()
            circle.lineWidth = 2.4
            circle.stroke()

            let cfg = UIImage.SymbolConfiguration(pointSize: size.width * 0.46, weight: .bold)
            if let sym = UIImage(systemName: sfSymbol, withConfiguration: cfg)?
                .withTintColor(accent, renderingMode: .alwaysOriginal) {
                let symSize = sym.size
                let pt = CGPoint(
                    x: (size.width - symSize.width) / 2,
                    y: (size.height - symSize.height) / 2
                )
                sym.draw(at: pt)
            }
        }
    }

    private static func laneAngles(from laneSpec: String) -> [Measurement<UnitAngle>] {
        let tokens = laneSpec
            .lowercased()
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return [Measurement(value: 0, unit: UnitAngle.degrees)]
        }
        return tokens.map { token in
            let deg: Double
            if token.contains("sharp_left") {
                deg = -135
            } else if token.contains("slight_left") {
                deg = -45
            } else if token.contains("left") {
                deg = -90
            } else if token.contains("sharp_right") {
                deg = 135
            } else if token.contains("slight_right") {
                deg = 45
            } else if token.contains("right") {
                deg = 90
            } else if token.contains("reverse") {
                deg = 180
            } else {
                deg = 0
            }
            return Measurement(value: deg, unit: UnitAngle.degrees)
        }
    }

    private static func drawCompoundLaneTokens(
        _ laneSpec: String,
        in rect: CGRect,
        color: UIColor,
        lineWidth: CGFloat,
        context: CGContext
    ) {
        let tokens = laneSpec
            .lowercased()
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let active = tokens.isEmpty ? ["through"] : tokens

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let midX = rect.midX
        let bottomY = rect.maxY
        let stemY = rect.midY + 2

        func drawMiniHead(tip: CGPoint, angle: CGFloat) {
            let len: CGFloat = 6.5
            let p1 = CGPoint(x: tip.x - len * cos(angle - 0.58), y: tip.y - len * sin(angle - 0.58))
            let p2 = CGPoint(x: tip.x - len * cos(angle + 0.58), y: tip.y - len * sin(angle + 0.58))
            context.beginPath()
            context.move(to: tip)
            context.addLine(to: p1)
            context.addLine(to: p2)
            context.closePath()
            context.fillPath()
        }

        for raw in active {
            context.beginPath()
            if raw.contains("left") {
                let slight = raw.contains("slight")
                let tip = CGPoint(
                    x: slight ? rect.minX + 3 : rect.minX + 1,
                    y: slight ? rect.minY + 3 : stemY - 5
                )
                context.move(to: CGPoint(x: midX, y: bottomY))
                context.addLine(to: CGPoint(x: midX, y: stemY))
                context.addLine(to: tip)
                context.strokePath()
                drawMiniHead(tip: tip, angle: slight ? -3 * .pi / 4 : .pi)
            } else if raw.contains("right") {
                let slight = raw.contains("slight")
                let tip = CGPoint(
                    x: slight ? rect.maxX - 3 : rect.maxX - 1,
                    y: slight ? rect.minY + 3 : stemY - 5
                )
                context.move(to: CGPoint(x: midX, y: bottomY))
                context.addLine(to: CGPoint(x: midX, y: stemY))
                context.addLine(to: tip)
                context.strokePath()
                drawMiniHead(tip: tip, angle: slight ? -.pi / 4 : 0)
            } else {
                let tip = CGPoint(x: midX, y: rect.minY + 2)
                context.move(to: CGPoint(x: midX, y: bottomY))
                context.addLine(to: tip)
                context.strokePath()
                drawMiniHead(tip: tip, angle: -.pi / 2)
            }
        }
        context.restoreGState()
    }

    private static func shortPaymentBadge(_ wire: String) -> String {
        switch wire.uppercased() {
        case "RFID": return "RFID"
        case "SMARTTAG": return "SmTAG"
        case "TNG_CARD": return "TnG"
        case "OPEN_PAYMENT_CARD": return "CARD"
        case "ERP2_OBU", "ERP_IU": return "ERP"
        case "BRUNEI_TOLL_CARD": return "BN"
        default: return String(wire.prefix(5))
        }
    }

    private static func paymentAccentColor(_ wire: String, theme: KartaCarPlayTheme) -> UIColor {
        switch wire.uppercased() {
        case "RFID": return theme.accentPrimary
        case "SMARTTAG": return theme.statusInfo
        case "TNG_CARD": return theme.statusInfo
        case "ERP2_OBU", "ERP_IU": return theme.statusCaution
        case "BRUNEI_TOLL_CARD": return UIColor(red: 0xD4 / 255.0, green: 0xAF / 255.0, blue: 0x37 / 255.0, alpha: 1.0)
        default: return theme.accentBright
        }
    }
}
#endif
