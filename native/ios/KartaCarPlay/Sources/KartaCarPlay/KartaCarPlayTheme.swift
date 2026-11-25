#if canImport(UIKit)
import CarPlay
import CoreGraphics
import UIKit

/// Vehicle head-unit aspect-ratio classification for panoramic & ultra-wide dashboards.
public enum KartaCarPlayViewportClass: String, Sendable {
    case standard  // < 1.65 (800x480, 1024x600)
    case wide      // 1.65 ..< 2.05 (1280x720, 1920x1080)
    case ultraWide // >= 2.05 (1920x720, 2400x720 panoramic dashes)
}

/// Computed layout metrics maximizing map canvas lookahead and legibility across
/// standard, wide, and ultra-wide CarPlay displays.
public struct KartaCarPlayViewportMetrics: Equatable, Sendable {
    public let size: CGSize
    public let scale: CGFloat
    public let viewportClass: KartaCarPlayViewportClass

    public init(boundsSize: CGSize, scale: CGFloat) {
        self.size = boundsSize
        self.scale = max(1.0, scale)
        let ratio = boundsSize.height > 0 ? (boundsSize.width / boundsSize.height) : 1.66
        if ratio >= 2.05 {
            self.viewportClass = .ultraWide
        } else if ratio >= 1.65 {
            self.viewportClass = .wide
        } else {
            self.viewportClass = .standard
        }
    }

    /// Lower-third camera padding shifts the vehicle puck toward the bottom ~34% of the
    /// unobstructed safe area so drivers gain maximum forward expressway lookahead.
    public func navigationEdgePadding(
        safeArea: UIEdgeInsets,
        isLeftHandTraffic: Bool
    ) -> UIEdgeInsets {
        let usableHeight = max(120.0, size.height - safeArea.top - safeArea.bottom)
        let forwardBiasTop = usableHeight * (viewportClass == .ultraWide ? 0.24 : 0.28)
        let extraLateral: CGFloat = viewportClass == .ultraWide ? 28.0 : 12.0

        return UIEdgeInsets(
            top: safeArea.top + forwardBiasTop,
            left: safeArea.left + (isLeftHandTraffic ? 12.0 : extraLateral),
            bottom: safeArea.bottom + 14.0,
            right: safeArea.right + (isLeftHandTraffic ? extraLateral : 12.0)
        )
    }

    public var routeLineWidth: CGFloat {
        switch viewportClass {
        case .ultraWide: return 9.5
        case .wide: return 8.2
        case .standard: return 7.2
        }
    }

    public var routeCasingWidth: CGFloat {
        routeLineWidth + 5.0
    }

    public var speedBadgeScale: CGFloat {
        switch viewportClass {
        case .ultraWide: return 1.12
        case .wide: return 1.04
        case .standard: return 0.96
        }
    }
}

/// Dual-lighting automotive design token palette mirroring Karta's `KartaPalette`
/// (`Obsidian Night` for headlights-on / tunnel driving; `Tropical Daylight` for
/// high-glare midday equatorial sun across MY / SG / BN).
public struct KartaCarPlayTheme {
    public let isDarkMode: Bool
    public let backgroundPrimary: UIColor
    public let surfaceCard: UIColor
    public let surfaceElevated: UIColor
    public let borderSubtle: UIColor
    public let accentPrimary: UIColor
    public let accentBright: UIColor
    public let textPrimary: UIColor
    public let textSecondary: UIColor
    public let arrowInk: UIColor
    public let statusClear: UIColor
    public let statusCaution: UIColor
    public let statusAlert: UIColor
    public let statusInfo: UIColor
    public let routeCore: UIColor
    public let routeCasing: UIColor
    public let rotaryFocusRing: UIColor
    public let tripEstimateStyle: CPTripEstimateStyle

    /// Obsidian Night Mode — low-glare cockpit palette (#0D0F12 / #181C22 / #5B9A94).
    public static let obsidianNight = KartaCarPlayTheme(
        isDarkMode: true,
        backgroundPrimary: UIColor(red: 0x0D / 255.0, green: 0x0F / 255.0, blue: 0x12 / 255.0, alpha: 1.0),
        surfaceCard: UIColor(red: 0x18 / 255.0, green: 0x1C / 255.0, blue: 0x22 / 255.0, alpha: 1.0),
        surfaceElevated: UIColor(red: 0x20 / 255.0, green: 0x26 / 255.0, blue: 0x2F / 255.0, alpha: 1.0),
        borderSubtle: UIColor(red: 0x2B / 255.0, green: 0x33 / 255.0, blue: 0x40 / 255.0, alpha: 1.0),
        accentPrimary: UIColor(red: 0x5B / 255.0, green: 0x9A / 255.0, blue: 0x94 / 255.0, alpha: 1.0),
        accentBright: UIColor(red: 0x74 / 255.0, green: 0xC4 / 255.0, blue: 0xBC / 255.0, alpha: 1.0),
        textPrimary: UIColor(red: 0xF4 / 255.0, green: 0xF6 / 255.0, blue: 0xF8 / 255.0, alpha: 1.0),
        textSecondary: UIColor(red: 0x8E / 255.0, green: 0x96 / 255.0, blue: 0xA0 / 255.0, alpha: 1.0),
        arrowInk: UIColor.white,
        statusClear: UIColor(red: 0x42 / 255.0, green: 0xB8 / 255.0, blue: 0x83 / 255.0, alpha: 1.0),
        statusCaution: UIColor(red: 0xF5 / 255.0, green: 0xA6 / 255.0, blue: 0x23 / 255.0, alpha: 1.0),
        statusAlert: UIColor(red: 0xFF / 255.0, green: 0x5A / 255.0, blue: 0x52 / 255.0, alpha: 1.0),
        statusInfo: UIColor(red: 0x5A / 255.0, green: 0x9D / 255.0, blue: 0xF0 / 255.0, alpha: 1.0),
        routeCore: UIColor(red: 0x62 / 255.0, green: 0xB3 / 255.0, blue: 0xAB / 255.0, alpha: 1.0),
        routeCasing: UIColor(red: 0x09 / 255.0, green: 0x0B / 255.0, blue: 0x0E / 255.0, alpha: 1.0),
        rotaryFocusRing: UIColor(red: 0x74 / 255.0, green: 0xC4 / 255.0, blue: 0xBC / 255.0, alpha: 1.0),
        tripEstimateStyle: .dark
    )

    /// High-Glare Tropical Daylight Mode — warm limestone canvas (#F5F2EB) & WCAG AAA ink (#11161C).
    public static let tropicalDaylight = KartaCarPlayTheme(
        isDarkMode: false,
        backgroundPrimary: UIColor(red: 0xF5 / 255.0, green: 0xF2 / 255.0, blue: 0xEB / 255.0, alpha: 1.0),
        surfaceCard: UIColor(red: 0xFC / 255.0, green: 0xFB / 255.0, blue: 0xF8 / 255.0, alpha: 1.0),
        surfaceElevated: UIColor(red: 0xEF / 255.0, green: 0xEC / 255.0, blue: 0xE4 / 255.0, alpha: 1.0),
        borderSubtle: UIColor(red: 0xD5 / 255.0, green: 0xD0 / 255.0, blue: 0xC5 / 255.0, alpha: 1.0),
        accentPrimary: UIColor(red: 0x2F / 255.0, green: 0x75 / 255.0, blue: 0x6F / 255.0, alpha: 1.0),
        accentBright: UIColor(red: 0x1E / 255.0, green: 0x5C / 255.0, blue: 0x57 / 255.0, alpha: 1.0),
        textPrimary: UIColor(red: 0x11 / 255.0, green: 0x16 / 255.0, blue: 0x1C / 255.0, alpha: 1.0),
        textSecondary: UIColor(red: 0x4A / 255.0, green: 0x55 / 255.0, blue: 0x63 / 255.0, alpha: 1.0),
        arrowInk: UIColor(red: 0x11 / 255.0, green: 0x16 / 255.0, blue: 0x1C / 255.0, alpha: 1.0),
        statusClear: UIColor(red: 0x13 / 255.0, green: 0x7D / 255.0, blue: 0x4E / 255.0, alpha: 1.0),
        statusCaution: UIColor(red: 0xB8 / 255.0, green: 0x6B / 255.0, blue: 0x00 / 255.0, alpha: 1.0),
        statusAlert: UIColor(red: 0xC8 / 255.0, green: 0x28 / 255.0, blue: 0x22 / 255.0, alpha: 1.0),
        statusInfo: UIColor(red: 0x1C / 255.0, green: 0x5D / 255.0, blue: 0xB0 / 255.0, alpha: 1.0),
        routeCore: UIColor(red: 0x24 / 255.0, green: 0x6E / 255.0, blue: 0x68 / 255.0, alpha: 1.0),
        routeCasing: UIColor(red: 0x10 / 255.0, green: 0x2F / 255.0, blue: 0x2C / 255.0, alpha: 1.0),
        rotaryFocusRing: UIColor(red: 0x1E / 255.0, green: 0x5C / 255.0, blue: 0x57 / 255.0, alpha: 1.0),
        tripEstimateStyle: .light
    )

    public static func resolve(isDarkMode: Bool) -> KartaCarPlayTheme {
        isDarkMode ? .obsidianNight : .tropicalDaylight
    }

    public static func resolve(for traitCollection: UITraitCollection) -> KartaCarPlayTheme {
        traitCollection.userInterfaceStyle == .light ? .tropicalDaylight : .obsidianNight
    }
}
#endif
