package com.karta.navigation.auto

import kotlin.math.pow

/** Canonical Karta Dark-First Automotive Palette derived from GEMINI.md. */
object KartaAutoPalette {
    const val BACKGROUND_PRIMARY = 0xFF0D0F12.toInt() // Deep Obsidian
    const val SURFACE_CARD = 0xFF181C22.toInt()       // Charcoal Slate
    const val ACCENT_PRIMARY = 0xFF5B9A94.toInt()     // Muted Teal
    const val ACCENT_BRIGHT = 0xFF72B8B1.toInt()
    const val TEXT_PRIMARY = 0xFFF4F6F8.toInt()       // Crisp Off-White
    const val TEXT_SECONDARY = 0xFF8E96A0.toInt()     // Steel Gray
    const val STATUS_CLEAR = 0xFF42B883.toInt()
    const val STATUS_CAUTION = 0xFFE6A23C.toInt()
    const val STATUS_ALERT = 0xFFE5534B.toInt()
    const val STATUS_INFO = 0xFF5294E2.toInt()
}

data class KartaLatLng(val lat: Double, val lon: Double)

data class KartaAutoLane(
    val laneSpec: String,
    val isRecommended: Boolean,
) {
    companion object {
        fun fromMap(map: Map<*, *>): KartaAutoLane = KartaAutoLane(
            laneSpec = (map["laneSpec"] as? String) ?: "through",
            isRecommended = (map["isRecommended"] as? Boolean) ?: false,
        )
    }
}

data class KartaAutoFrame(
    val sequenceId: Int = 0,
    val tripId: String = "",
    val isNavigating: Boolean = false,
    val phase: String = "idle",
    val currentLat: Double? = null,
    val currentLon: Double? = null,
    val bearingDeg: Double? = null,
    val accuracyMeters: Double? = null,
    val maneuverType: Int = 8,
    val primaryInstruction: String = "Ready to navigate",
    val secondaryInstruction: String? = null,
    val nextManeuverType: Int? = null,
    val roadRef: String? = null,
    val roadName: String? = null,
    val drivingSide: String = "left",
    val distanceToManeuverMeters: Double = 0.0,
    val remainingDistanceMeters: Double = 0.0,
    val remainingDurationSeconds: Double = 0.0,
    val etaEpochMs: Long = 0L,
    val currentSpeedKmh: Double = 0.0,
    val speedLimitKmh: Int? = null,
    val speedAlertLevel: String = "normal",
    val countryCode: String = "MY",
    val currencyCode: String = "MYR",
    val currencySymbol: String = "RM",
    val tripTollSummaryText: String = "Free",
    val laneItems: List<KartaAutoLane> = emptyList(),
    val approachingTollName: String? = null,
    val approachingTollDistanceMeters: Double? = null,
    val approachingTollPayments: List<String> = emptyList(),
    val approachingHazardId: String? = null,
    val approachingHazardCategory: String? = null,
    val approachingHazardLabel: String? = null,
    val approachingHazardDistanceMeters: Double? = null,
    val liveTrafficDelaySeconds: Double = 0.0,
    val rerouteProposalId: String? = null,
    val rerouteBannerText: String? = null,
    val rerouteTimeSavedSeconds: Double? = null,
    val rerouteTollDeltaText: String? = null,
    val isOffRoute: Boolean = false,
    val voiceMuted: Boolean = false,
    val isDarkMode: Boolean = true,
    val isRouteOverviewActive: Boolean = false,
) {
    val isLeftHandTraffic: Boolean
        get() = drivingSide.equals("left", ignoreCase = true)

    companion object {
        fun fromMap(map: Map<*, *>): KartaAutoFrame {
            val parsedLanes = (map["laneItems"] as? List<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.let(KartaAutoLane::fromMap) }
                ?.takeIf { it.isNotEmpty() }
                ?: (map["turnLanes"] as? List<*>)
                    ?.mapNotNull { it as? String }
                    ?.map { KartaAutoLane(laneSpec = it, isRecommended = true) }
                ?: emptyList()

            return KartaAutoFrame(
                sequenceId = (map["sequenceId"] as? Number)?.toInt() ?: 0,
                tripId = (map["tripId"] as? String) ?: "",
                isNavigating = (map["isNavigating"] as? Boolean) ?: false,
                phase = (map["phase"] as? String) ?: "idle",
                currentLat = (map["currentLat"] as? Number)?.toDouble(),
                currentLon = (map["currentLon"] as? Number)?.toDouble(),
                bearingDeg = (map["bearingDeg"] as? Number)?.toDouble(),
                accuracyMeters = (map["accuracyMeters"] as? Number)?.toDouble(),
                maneuverType = (map["maneuverType"] as? Number)?.toInt() ?: 8,
                primaryInstruction = (map["primaryInstruction"] as? String) ?: "Continue",
                secondaryInstruction = map["secondaryInstruction"] as? String,
                nextManeuverType = (map["nextManeuverType"] as? Number)?.toInt(),
                roadRef = map["roadRef"] as? String,
                roadName = map["roadName"] as? String,
                drivingSide = (map["drivingSide"] as? String) ?: "left",
                distanceToManeuverMeters = (map["distanceToManeuverMeters"] as? Number)?.toDouble() ?: 0.0,
                remainingDistanceMeters = (map["remainingDistanceMeters"] as? Number)?.toDouble() ?: 0.0,
                remainingDurationSeconds = (map["remainingDurationSeconds"] as? Number)?.toDouble() ?: 0.0,
                etaEpochMs = (map["etaEpochMs"] as? Number)?.toLong() ?: 0L,
                currentSpeedKmh = (map["currentSpeedKmh"] as? Number)?.toDouble() ?: 0.0,
                speedLimitKmh = (map["speedLimitKmh"] as? Number)?.toInt(),
                speedAlertLevel = (map["speedAlertLevel"] as? String) ?: "normal",
                countryCode = (map["countryCode"] as? String) ?: "MY",
                currencyCode = (map["currencyCode"] as? String) ?: "MYR",
                currencySymbol = (map["currencySymbol"] as? String) ?: "RM",
                tripTollSummaryText = (map["tripTollSummaryText"] as? String) ?: "Free",
                laneItems = parsedLanes,
                approachingTollName = map["approachingTollName"] as? String,
                approachingTollDistanceMeters = (map["approachingTollDistanceMeters"] as? Number)?.toDouble(),
                approachingTollPayments = (map["approachingTollPayments"] as? List<*>)
                    ?.mapNotNull { it as? String } ?: emptyList(),
                approachingHazardId = map["approachingHazardId"] as? String,
                approachingHazardCategory = map["approachingHazardCategory"] as? String,
                approachingHazardLabel = map["approachingHazardLabel"] as? String,
                approachingHazardDistanceMeters = (map["approachingHazardDistanceMeters"] as? Number)?.toDouble(),
                liveTrafficDelaySeconds = (map["liveTrafficDelaySeconds"] as? Number)?.toDouble() ?: 0.0,
                rerouteProposalId = map["rerouteProposalId"] as? String,
                rerouteBannerText = map["rerouteBannerText"] as? String,
                rerouteTimeSavedSeconds = (map["rerouteTimeSavedSeconds"] as? Number)?.toDouble(),
                rerouteTollDeltaText = map["rerouteTollDeltaText"] as? String,
                isOffRoute = (map["isOffRoute"] as? Boolean) ?: false,
                voiceMuted = (map["voiceMuted"] as? Boolean) ?: false,
                isDarkMode = (map["isDarkMode"] as? Boolean) ?: true,
                isRouteOverviewActive = (map["isRouteOverviewActive"] as? Boolean) ?: false,
            )
        }
    }
}

data class KartaAutoCongestionSegment(
    val startFraction: Double,
    val endFraction: Double,
    val severity: String,
    val speedKmh: Int,
) {
    companion object {
        fun fromMap(map: Map<*, *>): KartaAutoCongestionSegment = KartaAutoCongestionSegment(
            startFraction = (map["startFraction"] as? Number)?.toDouble() ?: 0.0,
            endFraction = (map["endFraction"] as? Number)?.toDouble() ?: 0.0,
            severity = (map["severity"] as? String) ?: "moderate",
            speedKmh = (map["speedKmh"] as? Number)?.toInt() ?: 35,
        )
    }
}

data class KartaAutoRouteGeometry(
    val tripId: String,
    val routePolyline6: String,
    val alternatePolylines6: List<String> = emptyList(),
    val congestionSegments: List<KartaAutoCongestionSegment> = emptyList(),
    val originName: String = "Origin",
    val destinationName: String = "Destination",
    val destinationLat: Double = 3.1579,
    val destinationLon: Double = 101.7116,
    val tollDisplayTotal: String = "Free",
    val hasTolls: Boolean = false,
) {
    companion object {
        fun fromMap(map: Map<*, *>): KartaAutoRouteGeometry = KartaAutoRouteGeometry(
            tripId = (map["tripId"] as? String) ?: "",
            routePolyline6 = (map["routePolyline6"] as? String) ?: "",
            alternatePolylines6 = (map["alternatePolylines6"] as? List<*>)
                ?.mapNotNull { it as? String } ?: emptyList(),
            congestionSegments = (map["congestionSegments"] as? List<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.let(KartaAutoCongestionSegment::fromMap) }
                ?: emptyList(),
            originName = (map["originName"] as? String) ?: "Origin",
            destinationName = (map["destinationName"] as? String) ?: "Destination",
            destinationLat = (map["destinationLat"] as? Number)?.toDouble() ?: 3.1579,
            destinationLon = (map["destinationLon"] as? Number)?.toDouble() ?: 101.7116,
            tollDisplayTotal = (map["tollDisplayTotal"] as? String) ?: "Free",
            hasTolls = (map["hasTolls"] as? Boolean) ?: false,
        )
    }
}

data class KartaAutoHazardPin(
    val id: String,
    val category: String,
    val label: String,
    val severity: String,
    val lat: Double,
    val lon: Double,
    val distanceMeters: Double? = null,
    val roadRef: String? = null,
    val onActiveRoute: Boolean = false,
) {
    companion object {
        fun fromMap(map: Map<*, *>): KartaAutoHazardPin = KartaAutoHazardPin(
            id = (map["id"] as? String) ?: "",
            category = (map["category"] as? String) ?: "accident",
            label = (map["label"] as? String) ?: "Hazard",
            severity = (map["severity"] as? String) ?: "medium",
            lat = (map["lat"] as? Number)?.toDouble() ?: 0.0,
            lon = (map["lon"] as? Number)?.toDouble() ?: 0.0,
            distanceMeters = (map["distanceMeters"] as? Number)?.toDouble(),
            roadRef = map["roadRef"] as? String,
            onActiveRoute = (map["onActiveRoute"] as? Boolean) ?: false,
        )
    }
}

data class KartaAutoThermalProfile(
    val thermalTier: String = "nominal",
    val headUnitTargetFps: Int = 60,
    val enableHeadUnit3DBuildings: Boolean = true,
    val enableVehicleHaloShader: Boolean = true,
    val headUnitCameraPitchDeg: Double = 58.0,
    val maxOfflineTileCacheMb: Int = 128,
) {
    companion object {
        val NOMINAL = KartaAutoThermalProfile()
        val CRITICAL_FAILSAFE = KartaAutoThermalProfile(
            thermalTier = "critical",
            headUnitTargetFps = 20,
            enableHeadUnit3DBuildings = false,
            enableVehicleHaloShader = false,
            headUnitCameraPitchDeg = 0.0,
            maxOfflineTileCacheMb = 32,
        )

        fun fromMap(map: Map<*, *>): KartaAutoThermalProfile = KartaAutoThermalProfile(
            thermalTier = (map["thermalTier"] as? String) ?: "nominal",
            headUnitTargetFps = (map["headUnitTargetFps"] as? Number)?.toInt() ?: 60,
            enableHeadUnit3DBuildings = (map["enableHeadUnit3DBuildings"] as? Boolean) ?: true,
            enableVehicleHaloShader = (map["enableVehicleHaloShader"] as? Boolean) ?: true,
            headUnitCameraPitchDeg = (map["headUnitCameraPitchDeg"] as? Number)?.toDouble() ?: 58.0,
            maxOfflineTileCacheMb = (map["maxOfflineTileCacheMb"] as? Number)?.toInt() ?: 128,
        )
    }
}

data class KartaAutoOfflineRegion(
    val regionId: String,
    val displayName: String,
    val pmtilesUrl: String,
    val localPmtilesPath: String,
    val verifiedSha256: Boolean,
) {
    companion object {
        fun fromMap(map: Map<*, *>): KartaAutoOfflineRegion = KartaAutoOfflineRegion(
            regionId = (map["regionId"] as? String) ?: "",
            displayName = (map["displayName"] as? String) ?: "",
            pmtilesUrl = (map["pmtilesUrl"] as? String) ?: "",
            localPmtilesPath = (map["localPmtilesPath"] as? String) ?: "",
            verifiedSha256 = (map["verifiedSha256"] as? Boolean) ?: false,
        )
    }
}

data class KartaAutoOfflineConfig(
    val offlineModeEnabled: Boolean = false,
    val activePmtilesUrl: String = "http://localhost:8081/my-sg-bn-full.json",
    val darkStyleSchema: String = "openmaptiles",
    val downloadedRegions: List<KartaAutoOfflineRegion> = emptyList(),
) {
    companion object {
        fun fromMap(map: Map<*, *>): KartaAutoOfflineConfig = KartaAutoOfflineConfig(
            offlineModeEnabled = (map["offlineModeEnabled"] as? Boolean) ?: false,
            activePmtilesUrl = (map["activePmtilesUrl"] as? String)
                ?: "http://localhost:8081/my-sg-bn-full.json",
            darkStyleSchema = (map["darkStyleSchema"] as? String) ?: "openmaptiles",
            downloadedRegions = (map["downloadedRegions"] as? List<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.let(KartaAutoOfflineRegion::fromMap) }
                ?: emptyList(),
        )
    }
}

/** Decodes Valhalla precision-6 encoded polyline into WGS 84 [KartaLatLng] vertices. */
object KartaPolyline6Decoder {
    fun decode(encoded: String, precision: Int = 6): List<KartaLatLng> {
        if (encoded.isEmpty()) return emptyList()
        val factor = 10.0.pow(precision)
        val out = ArrayList<KartaLatLng>(encoded.length / 4)
        var index = 0
        var lat = 0
        var lon = 0
        val len = encoded.length

        while (index < len) {
            var shift = 0
            var result = 0
            while (index < len) {
                val b = encoded[index++].code - 63
                result = result or ((b and 0x1F) shl shift)
                shift += 5
                if (b < 0x20) break
            }
            lat += if ((result and 1) != 0) (result shr 1).inv() else (result shr 1)

            shift = 0
            result = 0
            while (index < len) {
                val b = encoded[index++].code - 63
                result = result or ((b and 0x1F) shl shift)
                shift += 5
                if (b < 0x20) break
            }
            lon += if ((result and 1) != 0) (result shr 1).inv() else (result shr 1)

            out.add(KartaLatLng(lat / factor, lon / factor))
        }
        return out
    }
}
