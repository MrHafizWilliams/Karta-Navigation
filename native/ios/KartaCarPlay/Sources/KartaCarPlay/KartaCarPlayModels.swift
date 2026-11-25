import CoreLocation
import Foundation

#if canImport(UIKit)
import UIKit

/// Canonical Karta Dark-First Automotive Color Tokens (derived from GEMINI.md).
public enum KartaCarPlayPalette {
    public static let backgroundPrimary = UIColor(red: 0x0D / 255.0, green: 0x0F / 255.0, blue: 0x12 / 255.0, alpha: 1.0) // #0D0F12
    public static let surfaceCard = UIColor(red: 0x18 / 255.0, green: 0x1C / 255.0, blue: 0x22 / 255.0, alpha: 1.0) // #181C22
    public static let accentPrimary = UIColor(red: 0x5B / 255.0, green: 0x9A / 255.0, blue: 0x94 / 255.0, alpha: 1.0) // #5B9A94
    public static let accentBright = UIColor(red: 0x72 / 255.0, green: 0xB8 / 255.0, blue: 0xB1 / 255.0, alpha: 1.0)
    public static let textPrimary = UIColor(red: 0xF4 / 255.0, green: 0xF6 / 255.0, blue: 0xF8 / 255.0, alpha: 1.0) // #F4F6F8
    public static let textSecondary = UIColor(red: 0x8E / 255.0, green: 0x96 / 255.0, blue: 0xA0 / 255.0, alpha: 1.0) // #8E96A0
    public static let statusClear = UIColor(red: 0x42 / 255.0, green: 0xB8 / 255.0, blue: 0x83 / 255.0, alpha: 1.0)
    public static let statusCaution = UIColor(red: 0xE6 / 255.0, green: 0xA2 / 255.0, blue: 0x3C / 255.0, alpha: 1.0)
    public static let statusAlert = UIColor(red: 0xE5 / 255.0, green: 0x53 / 255.0, blue: 0x4B / 255.0, alpha: 1.0)
    public static let statusInfo = UIColor(red: 0x52 / 255.0, green: 0x94 / 255.0, blue: 0xE2 / 255.0, alpha: 1.0)
}
#endif

public struct KartaCarPlayLaneItem: Equatable, Sendable {
    public let laneSpec: String
    public let isRecommended: Bool

    public init(laneSpec: String, isRecommended: Bool) {
        self.laneSpec = laneSpec
        self.isRecommended = isRecommended
    }

    public static func from(_ dict: [String: Any]) -> KartaCarPlayLaneItem {
        KartaCarPlayLaneItem(
            laneSpec: (dict["laneSpec"] as? String) ?? "through",
            isRecommended: (dict["isRecommended"] as? Bool) ?? false
        )
    }
}

public struct KartaCarPlayNavigationFrame: Equatable, Sendable {
    public let sequenceId: Int
    public let tripId: String
    public let isNavigating: Bool
    public let phase: String
    public let currentLat: Double?
    public let currentLon: Double?
    public let bearingDeg: Double?
    public let accuracyMeters: Double?
    public let maneuverType: Int
    public let primaryInstruction: String
    public let secondaryInstruction: String?
    public let nextManeuverType: Int?
    public let roadRef: String?
    public let roadName: String?
    public let drivingSide: String
    public let distanceToManeuverMeters: Double
    public let remainingDistanceMeters: Double
    public let remainingDurationSeconds: Double
    public let etaEpochMs: Int64
    public let currentSpeedKmh: Double
    public let speedLimitKmh: Int?
    public let speedAlertLevel: String
    public let countryCode: String
    public let currencyCode: String
    public let currencySymbol: String
    public let tripTollSummaryText: String
    public let laneItems: [KartaCarPlayLaneItem]
    public let approachingTollName: String?
    public let approachingTollDistanceMeters: Double?
    public let approachingTollPayments: [String]
    public let approachingHazardId: String?
    public let approachingHazardCategory: String?
    public let approachingHazardLabel: String?
    public let approachingHazardDistanceMeters: Double?
    public let liveTrafficDelaySeconds: Double
    public let rerouteProposalId: String?
    public let rerouteBannerText: String?
    public let rerouteTimeSavedSeconds: Double?
    public let rerouteTollDeltaText: String?
    public let isOffRoute: Bool
    public let voiceMuted: Bool
    public let isDarkMode: Bool
    public let isRouteOverviewActive: Bool

    public var isLeftHandTraffic: Bool {
        drivingSide.lowercased() == "left"
    }

    public static let idle = KartaCarPlayNavigationFrame(
        sequenceId: 0,
        tripId: "",
        isNavigating: false,
        phase: "idle",
        currentLat: nil,
        currentLon: nil,
        bearingDeg: nil,
        accuracyMeters: nil,
        maneuverType: 8,
        primaryInstruction: "Ready to navigate",
        secondaryInstruction: nil,
        nextManeuverType: nil,
        roadRef: nil,
        roadName: nil,
        drivingSide: "left",
        distanceToManeuverMeters: 0,
        remainingDistanceMeters: 0,
        remainingDurationSeconds: 0,
        etaEpochMs: 0,
        currentSpeedKmh: 0,
        speedLimitKmh: nil,
        speedAlertLevel: "normal",
        countryCode: "MY",
        currencyCode: "MYR",
        currencySymbol: "RM",
        tripTollSummaryText: "Free",
        laneItems: [],
        approachingTollName: nil,
        approachingTollDistanceMeters: nil,
        approachingTollPayments: [],
        approachingHazardId: nil,
        approachingHazardCategory: nil,
        approachingHazardLabel: nil,
        approachingHazardDistanceMeters: nil,
        liveTrafficDelaySeconds: 0,
        rerouteProposalId: nil,
        rerouteBannerText: nil,
        rerouteTimeSavedSeconds: nil,
        rerouteTollDeltaText: nil,
        isOffRoute: false,
        voiceMuted: false,
        isDarkMode: true,
        isRouteOverviewActive: false
    )

    public static func from(_ payload: [String: Any]) -> KartaCarPlayNavigationFrame {
        let structuredLanes: [KartaCarPlayLaneItem]
        if let rawItems = payload["laneItems"] as? [[String: Any]], !rawItems.isEmpty {
            structuredLanes = rawItems.map(KartaCarPlayLaneItem.from)
        } else if let legacyLanes = payload["turnLanes"] as? [String] {
            structuredLanes = legacyLanes.map { KartaCarPlayLaneItem(laneSpec: $0, isRecommended: true) }
        } else {
            structuredLanes = []
        }

        return KartaCarPlayNavigationFrame(
            sequenceId: (payload["sequenceId"] as? NSNumber)?.intValue ?? 0,
            tripId: (payload["tripId"] as? String) ?? "",
            isNavigating: (payload["isNavigating"] as? Bool) ?? false,
            phase: (payload["phase"] as? String) ?? "idle",
            currentLat: (payload["currentLat"] as? NSNumber)?.doubleValue,
            currentLon: (payload["currentLon"] as? NSNumber)?.doubleValue,
            bearingDeg: (payload["bearingDeg"] as? NSNumber)?.doubleValue,
            accuracyMeters: (payload["accuracyMeters"] as? NSNumber)?.doubleValue,
            maneuverType: (payload["maneuverType"] as? NSNumber)?.intValue ?? 8,
            primaryInstruction: (payload["primaryInstruction"] as? String) ?? "Continue",
            secondaryInstruction: payload["secondaryInstruction"] as? String,
            nextManeuverType: (payload["nextManeuverType"] as? NSNumber)?.intValue,
            roadRef: payload["roadRef"] as? String,
            roadName: payload["roadName"] as? String,
            drivingSide: (payload["drivingSide"] as? String) ?? "left",
            distanceToManeuverMeters: (payload["distanceToManeuverMeters"] as? NSNumber)?.doubleValue ?? 0,
            remainingDistanceMeters: (payload["remainingDistanceMeters"] as? NSNumber)?.doubleValue ?? 0,
            remainingDurationSeconds: (payload["remainingDurationSeconds"] as? NSNumber)?.doubleValue ?? 0,
            etaEpochMs: (payload["etaEpochMs"] as? NSNumber)?.int64Value ?? 0,
            currentSpeedKmh: (payload["currentSpeedKmh"] as? NSNumber)?.doubleValue ?? 0,
            speedLimitKmh: (payload["speedLimitKmh"] as? NSNumber)?.intValue,
            speedAlertLevel: (payload["speedAlertLevel"] as? String) ?? "normal",
            countryCode: (payload["countryCode"] as? String) ?? "MY",
            currencyCode: (payload["currencyCode"] as? String) ?? "MYR",
            currencySymbol: (payload["currencySymbol"] as? String) ?? "RM",
            tripTollSummaryText: (payload["tripTollSummaryText"] as? String) ?? "Free",
            laneItems: structuredLanes,
            approachingTollName: payload["approachingTollName"] as? String,
            approachingTollDistanceMeters: (payload["approachingTollDistanceMeters"] as? NSNumber)?.doubleValue,
            approachingTollPayments: (payload["approachingTollPayments"] as? [String]) ?? [],
            approachingHazardId: payload["approachingHazardId"] as? String,
            approachingHazardCategory: payload["approachingHazardCategory"] as? String,
            approachingHazardLabel: payload["approachingHazardLabel"] as? String,
            approachingHazardDistanceMeters: (payload["approachingHazardDistanceMeters"] as? NSNumber)?.doubleValue,
            liveTrafficDelaySeconds: (payload["liveTrafficDelaySeconds"] as? NSNumber)?.doubleValue ?? 0,
            rerouteProposalId: payload["rerouteProposalId"] as? String,
            rerouteBannerText: payload["rerouteBannerText"] as? String,
            rerouteTimeSavedSeconds: (payload["rerouteTimeSavedSeconds"] as? NSNumber)?.doubleValue,
            rerouteTollDeltaText: payload["rerouteTollDeltaText"] as? String,
            isOffRoute: (payload["isOffRoute"] as? Bool) ?? false,
            voiceMuted: (payload["voiceMuted"] as? Bool) ?? false,
            isDarkMode: (payload["isDarkMode"] as? Bool) ?? true,
            isRouteOverviewActive: (payload["isRouteOverviewActive"] as? Bool) ?? false
        )
    }
}

public struct KartaCarPlayCongestionSegment: Equatable, Sendable {
    public let startFraction: Double
    public let endFraction: Double
    public let severity: String
    public let speedKmh: Int

    public static func from(_ dict: [String: Any]) -> KartaCarPlayCongestionSegment {
        KartaCarPlayCongestionSegment(
            startFraction: (dict["startFraction"] as? NSNumber)?.doubleValue ?? 0.0,
            endFraction: (dict["endFraction"] as? NSNumber)?.doubleValue ?? 0.0,
            severity: (dict["severity"] as? String) ?? "moderate",
            speedKmh: (dict["speedKmh"] as? NSNumber)?.intValue ?? 35
        )
    }
}

public struct KartaCarPlayRouteGeometry: Equatable, Sendable {
    public let tripId: String
    public let routePolyline6: String
    public let alternatePolylines6: [String]
    public let congestionSegments: [KartaCarPlayCongestionSegment]
    public let originName: String
    public let destinationName: String
    public let destinationLat: Double
    public let destinationLon: Double
    public let tollDisplayTotal: String
    public let hasTolls: Bool

    public static func from(_ payload: [String: Any]) -> KartaCarPlayRouteGeometry {
        let segs = (payload["congestionSegments"] as? [[String: Any]] ?? [])
            .map(KartaCarPlayCongestionSegment.from)
        return KartaCarPlayRouteGeometry(
            tripId: (payload["tripId"] as? String) ?? "",
            routePolyline6: (payload["routePolyline6"] as? String) ?? "",
            alternatePolylines6: (payload["alternatePolylines6"] as? [String]) ?? [],
            congestionSegments: segs,
            originName: (payload["originName"] as? String) ?? "Origin",
            destinationName: (payload["destinationName"] as? String) ?? "Destination",
            destinationLat: (payload["destinationLat"] as? NSNumber)?.doubleValue ?? 3.1579,
            destinationLon: (payload["destinationLon"] as? NSNumber)?.doubleValue ?? 101.7116,
            tollDisplayTotal: (payload["tollDisplayTotal"] as? String) ?? "Free",
            hasTolls: (payload["hasTolls"] as? Bool) ?? false
        )
    }
}

public struct KartaCarPlayHazardPin: Equatable, Sendable {
    public let id: String
    public let category: String
    public let label: String
    public let severity: String
    public let lat: Double
    public let lon: Double
    public let distanceMeters: Double?
    public let roadRef: String?
    public let onActiveRoute: Bool

    public static func from(_ dict: [String: Any]) -> KartaCarPlayHazardPin {
        KartaCarPlayHazardPin(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            category: (dict["category"] as? String) ?? "accident",
            label: (dict["label"] as? String) ?? "Hazard",
            severity: (dict["severity"] as? String) ?? "medium",
            lat: (dict["lat"] as? NSNumber)?.doubleValue ?? 0,
            lon: (dict["lon"] as? NSNumber)?.doubleValue ?? 0,
            distanceMeters: (dict["distanceMeters"] as? NSNumber)?.doubleValue,
            roadRef: dict["roadRef"] as? String,
            onActiveRoute: (dict["onActiveRoute"] as? Bool) ?? false
        )
    }
}

public struct KartaCarPlayThermalProfile: Equatable, Sendable {
    public let thermalTier: String
    public let headUnitTargetFps: Int
    public let enableHeadUnit3DBuildings: Bool
    public let enableVehicleHaloShader: Bool
    public let headUnitCameraPitchDeg: Double
    public let maxOfflineTileCacheMb: Int

    public static let nominal = KartaCarPlayThermalProfile(
        thermalTier: "nominal",
        headUnitTargetFps: 60,
        enableHeadUnit3DBuildings: true,
        enableVehicleHaloShader: true,
        headUnitCameraPitchDeg: 58.0,
        maxOfflineTileCacheMb: 128
    )

    public static let criticalFailsafe = KartaCarPlayThermalProfile(
        thermalTier: "critical",
        headUnitTargetFps: 20,
        enableHeadUnit3DBuildings: false,
        enableVehicleHaloShader: false,
        headUnitCameraPitchDeg: 0.0,
        maxOfflineTileCacheMb: 32
    )

    public static func from(_ payload: [String: Any]) -> KartaCarPlayThermalProfile {
        KartaCarPlayThermalProfile(
            thermalTier: (payload["thermalTier"] as? String) ?? "nominal",
            headUnitTargetFps: (payload["headUnitTargetFps"] as? NSNumber)?.intValue ?? 60,
            enableHeadUnit3DBuildings: (payload["enableHeadUnit3DBuildings"] as? Bool) ?? true,
            enableVehicleHaloShader: (payload["enableVehicleHaloShader"] as? Bool) ?? true,
            headUnitCameraPitchDeg: (payload["headUnitCameraPitchDeg"] as? NSNumber)?.doubleValue ?? 58.0,
            maxOfflineTileCacheMb: (payload["maxOfflineTileCacheMb"] as? NSNumber)?.intValue ?? 128
        )
    }
}

public struct KartaCarPlayOfflineMapConfig: Equatable, Sendable {
    public let offlineModeEnabled: Bool
    public let activePmtilesUrl: String
    public let darkStyleSchema: String
    public let localPmtilesPaths: [String]

    public static let defaultConfig = KartaCarPlayOfflineMapConfig(
        offlineModeEnabled: false,
        activePmtilesUrl: "http://localhost:8081/my-sg-bn-full.json",
        darkStyleSchema: "openmaptiles",
        localPmtilesPaths: []
    )

    public static func from(_ payload: [String: Any]) -> KartaCarPlayOfflineMapConfig {
        let regions = (payload["downloadedRegions"] as? [[String: Any]] ?? [])
            .compactMap { $0["localPmtilesPath"] as? String }
            .filter { !$0.isEmpty }
        return KartaCarPlayOfflineMapConfig(
            offlineModeEnabled: (payload["offlineModeEnabled"] as? Bool) ?? false,
            activePmtilesUrl: (payload["activePmtilesUrl"] as? String) ?? "http://localhost:8081/my-sg-bn-full.json",
            darkStyleSchema: (payload["darkStyleSchema"] as? String) ?? "openmaptiles",
            localPmtilesPaths: regions
        )
    }
}

/// Decodes Valhalla precision-6 encoded polylines into WGS 84 `CLLocationCoordinate2D` arrays.
public enum KartaPolyline6Decoder {
    public static func decode(_ encoded: String, precision: Int = 6) -> [CLLocationCoordinate2D] {
        guard !encoded.isEmpty else { return [] }
        let bytes = Array(encoded.utf8)
        let factor = pow(10.0, Double(precision))
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(bytes.count / 4)

        var index = 0
        var lat = 0
        var lon = 0

        while index < bytes.count {
            var shift = 0
            var result = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { break }
            }
            lat += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1)

            shift = 0
            result = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { break }
            }
            lon += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1)

            coords.append(
                CLLocationCoordinate2D(
                    latitude: Double(lat) / factor,
                    longitude: Double(lon) / factor
                )
            )
        }
        return coords
    }
}
