package com.karta.navigation.auto

import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.Alert
import androidx.car.app.model.AlertCallback
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarText
import androidx.car.app.model.DateTimeWithZone
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.model.Destination
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.car.app.navigation.model.Trip
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * Flagship Android Auto `NavigationTemplate` screen bound reactively to [KartaAutoStateStore].
 *
 * Automotive Polish Features:
 * - Automatic Day/Night dual-lighting surfaces (`CarColor.createCustom(TropicalDaylight, ObsidianNight)`)
 *   synced with the vehicle headlight/dimmer sensor (`onCarConfigurationChanged`).
 * - High-contrast WCAG AAA geometric Valhalla maneuver arrows (including MY/SG/BN clockwise roundabouts)
 *   and `360x64` compound lane + toll-payment (`RFID` / `SmartTAG` / `TnG` / `ERP`) strip images.
 * - Zero-distraction **3-action primary `ActionStrip`** with rotary-controller focus rings:
 *   1. `Voice` (`Action.FLAG_PRIMARY` on API >= 5 — hands-free EN/BM/Manglish/Singlish reporting)
 *   2. `Mute` / `Unmute` (guidance audio toggle)
 *   3. `Overview` / `End Trip` (1st tap frames full route corridor in Overview; tapping while in
 *      Overview safely cancels navigation, preventing accidental rotary-knob termination).
 * - Minimal `MapActionStrip` (`Action.PAN` + conditional `Recenter` only when panned or in Overview)
 *   maximizing map canvas visibility on wide & ultra-wide vehicle head units.
 * - Deduplicated `AppManager.showAlert` banners (Car App API >= 5) for live hazards and Valhalla reroutes.
 */
class KartaNavigationScreen(
    carContext: CarContext,
    private val mapRenderer: KartaAutoMapSurfaceRenderer,
    private val voiceController: KartaAutoVoiceController,
) : Screen(carContext), DefaultLifecycleObserver {

    private val appManager = carContext.getCarService(AppManager::class.java)
    private val navigationManager = carContext.getCarService(NavigationManager::class.java)
    private var frame: KartaAutoFrame = KartaAutoStateStore.frame.value
    private var route: KartaAutoRouteGeometry? = KartaAutoStateStore.route.value
    private var isDarkMode: Boolean = KartaAutoStateStore.isDarkMode.value
    private var isRouteOverviewActive: Boolean = KartaAutoStateStore.isRouteOverviewActive.value
    private var isNavigationActiveOnHost = false
    private val alertCooldownsMs = HashMap<String, Long>()
    private var activeAlertId: Int? = null

    init {
        lifecycle.addObserver(this)
        mapRenderer.onCameraLockChanged = { invalidate() }

        lifecycleScope.launch {
            KartaAutoStateStore.frame.collectLatest { next ->
                frame = next
                syncNavigationManager(next)
                evaluateAlerts(next)
                invalidate()
            }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.route.collectLatest { nextRoute ->
                route = nextRoute
                if (frame.isNavigating) {
                    syncNavigationManager(frame)
                }
                invalidate()
            }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.isDarkMode.collectLatest { dark ->
                if (isDarkMode != dark) {
                    isDarkMode = dark
                    invalidate()
                }
            }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.isRouteOverviewActive.collectLatest { overview ->
                if (isRouteOverviewActive != overview) {
                    isRouteOverviewActive = overview
                    invalidate()
                }
            }
        }
    }

    override fun onDestroy(owner: LifecycleOwner) {
        mapRenderer.onCameraLockChanged = null
        if (carContext.carAppApiLevel >= 5) {
            activeAlertId?.let { appManager.dismissAlert(it) }
        }
        if (isNavigationActiveOnHost) {
            navigationManager.navigationEnded()
            isNavigationActiveOnHost = false
        }
        alertCooldownsMs.clear()
        activeAlertId = null
    }

    override fun onGetTemplate(): Template {
        val activeTheme = KartaAutoTheme.resolve(isDarkMode)
        val builder = NavigationTemplate.Builder()
            .setBackgroundColor(
                CarColor.createCustom(
                    KartaAutoTheme.TropicalDaylight.surfaceCard,
                    KartaAutoTheme.ObsidianNight.surfaceCard,
                ),
            )
            .setActionStrip(buildPrimaryActionStrip(activeTheme))
            .setMapActionStrip(buildMapActionStrip(activeTheme))

        if (frame.isNavigating) {
            val currentStep = buildCurrentStep(frame, activeTheme)
            val stepDistance = KartaValhallaManeuverMapper.toCarDistance(frame.distanceToManeuverMeters)
            val routingBuilder = RoutingInfo.Builder()
                .setCurrentStep(currentStep, stepDistance)

            val nextInstr = frame.secondaryInstruction
            if (!nextInstr.isNullOrBlank()) {
                val nextStep = Step.Builder(nextInstr)
                    .setManeuver(
                        KartaValhallaManeuverMapper.toCarManeuver(
                            valhallaType = frame.nextManeuverType ?: 8,
                            isLeftHandTraffic = frame.isLeftHandTraffic,
                            theme = activeTheme,
                            isSecondary = true,
                        ),
                    )
                    .build()
                routingBuilder.setNextStep(nextStep)
            }

            builder.setNavigationInfo(routingBuilder.build())
            builder.setDestinationTravelEstimate(buildTravelEstimate(frame))
        }

        return builder.build()
    }

    /**
     * Zero-distraction primary action strip strictly capped at **3 one-tap actions**
     * with rotary-focus rings and safe 2-stage Overview -> End Trip confirmation.
     */
    private fun buildPrimaryActionStrip(theme: KartaAutoTheme): ActionStrip {
        val voiceActionBuilder = Action.Builder()
            .setTitle("Voice")
            .setIcon(
                KartaValhallaManeuverMapper.renderRotaryActionIcon(
                    kind = KartaRotaryActionKind.VOICE_MIC,
                    theme = theme,
                    highlighted = true,
                ),
            )
            .setOnClickListener {
                voiceController.triggerHandsFreeVoiceReport(frame.countryCode)
            }
        if (carContext.carAppApiLevel >= 5) {
            voiceActionBuilder.setFlags(Action.FLAG_PRIMARY)
        }

        val audioAction = Action.Builder()
            .setTitle(if (frame.voiceMuted) "Unmute" else "Mute")
            .setIcon(
                KartaValhallaManeuverMapper.renderRotaryActionIcon(
                    kind = if (frame.voiceMuted) {
                        KartaRotaryActionKind.AUDIO_MUTED
                    } else {
                        KartaRotaryActionKind.AUDIO_ON
                    },
                    theme = theme,
                    highlighted = frame.voiceMuted,
                ),
            )
            .setOnClickListener {
                KartaAutoStateStore.emitNavigationControlAction("toggle_mute")
            }
            .build()

        val thirdAction = if (frame.isNavigating) {
            if (isRouteOverviewActive) {
                // Already in Route Overview: tapping cleanly ends trip; Recenter in MapActionStrip resumes
                Action.Builder()
                    .setTitle("End Trip")
                    .setIcon(
                        KartaValhallaManeuverMapper.renderRotaryActionIcon(
                            kind = KartaRotaryActionKind.END_TRIP,
                            theme = theme,
                            destructive = true,
                        ),
                    )
                    .setOnClickListener {
                        KartaAutoStateStore.updateRouteOverview(false)
                        mapRenderer.setRouteOverviewMode(false)
                        KartaAutoStateStore.emitNavigationControlAction("end_trip")
                    }
                    .build()
            } else {
                Action.Builder()
                    .setTitle("Overview")
                    .setIcon(
                        KartaValhallaManeuverMapper.renderRotaryActionIcon(
                            kind = KartaRotaryActionKind.ROUTE_OVERVIEW,
                            theme = theme,
                        ),
                    )
                    .setOnClickListener {
                        KartaAutoStateStore.updateRouteOverview(true)
                        mapRenderer.setRouteOverviewMode(true)
                        KartaAutoStateStore.emitNavigationControlAction("toggle_overview")
                    }
                    .build()
            }
        } else {
            // Free-drive mode (no active route to cancel): 3rd slot offers 1-tap Hazard Grid
            Action.Builder()
                .setTitle("Hazard")
                .setIcon(
                    KartaValhallaManeuverMapper.renderRotaryActionIcon(
                        kind = KartaRotaryActionKind.REPORT_HAZARD,
                        theme = theme,
                        destructive = true,
                    ),
                )
                .setOnClickListener {
                    screenManager.push(KartaHazardReportScreen(carContext))
                }
                .build()
        }

        return ActionStrip.Builder()
            .addAction(voiceActionBuilder.build())
            .addAction(audioAction)
            .addAction(thirdAction)
            .build()
    }

    /**
     * Minimal map chrome (`Action.PAN` + conditional `Recenter` only when panned or in Route Overview)
     * reclaiming right-edge canvas space and reducing rotary knob detents.
     */
    private fun buildMapActionStrip(theme: KartaAutoTheme): ActionStrip {
        val builder = ActionStrip.Builder()
            .addAction(Action.PAN)

        if (mapRenderer.isPannedOrOverview || isRouteOverviewActive) {
            builder.addAction(
                Action.Builder()
                    .setIcon(
                        KartaValhallaManeuverMapper.renderRotaryActionIcon(
                            kind = KartaRotaryActionKind.RECENTER,
                            theme = theme,
                            highlighted = true,
                        ),
                    )
                    .setOnClickListener {
                        KartaAutoStateStore.updateRouteOverview(false)
                        mapRenderer.recenterOnVehicle()
                        KartaAutoStateStore.emitNavigationControlAction("recenter")
                    }
                    .build(),
            )
        }
        return builder.build()
    }

    private fun buildCurrentStep(f: KartaAutoFrame, theme: KartaAutoTheme): Step {
        val cue = buildString {
            if (!f.roadRef.isNullOrBlank()) {
                append("[${f.roadRef}] ")
            }
            append(f.primaryInstruction)
            if (!f.approachingTollName.isNullOrBlank()) {
                val distM = (f.approachingTollDistanceMeters ?: 0.0).roundToInt()
                val pay = f.approachingTollPayments.take(2).joinToString("/")
                append(" · Toll ${distM}m: ${f.approachingTollName}")
                if (pay.isNotEmpty()) append(" ($pay)")
            }
        }

        val stepBuilder = Step.Builder(cue)
            .setManeuver(
                KartaValhallaManeuverMapper.toCarManeuver(
                    valhallaType = f.maneuverType,
                    isLeftHandTraffic = f.isLeftHandTraffic,
                    theme = theme,
                ),
            )

        val roadLabel = f.roadName ?: f.roadRef
        if (!roadLabel.isNullOrBlank()) {
            stepBuilder.setRoad(roadLabel)
        }

        for (lane in f.laneItems.take(5)) {
            stepBuilder.addLane(KartaValhallaManeuverMapper.toCarLane(lane))
        }
        KartaValhallaManeuverMapper.renderLanesImage(
            lanes = f.laneItems,
            theme = theme,
            approachingTollPayments = f.approachingTollPayments,
            approachingTollName = f.approachingTollName,
        )?.let { lanesIcon ->
            stepBuilder.setLanesImage(lanesIcon)
        }

        return stepBuilder.build()
    }

    private fun buildTravelEstimate(f: KartaAutoFrame): TravelEstimate {
        val remainingSec = max(0L, f.remainingDurationSeconds.roundToLong())
        val arrivalZdt = if (f.etaEpochMs > 0L) {
            ZonedDateTime.ofInstant(Instant.ofEpochMilli(f.etaEpochMs), ZoneId.systemDefault())
        } else {
            ZonedDateTime.now().plusSeconds(remainingSec)
        }

        val timeColor = when {
            f.liveTrafficDelaySeconds >= 600.0 -> CarColor.RED
            f.liveTrafficDelaySeconds >= 180.0 -> CarColor.YELLOW
            else -> CarColor.GREEN
        }

        val tollSummary = route?.tollDisplayTotal ?: f.tripTollSummaryText
        val tripText = if (tollSummary.equals("Free", ignoreCase = true)) {
            "${f.countryCode} · Toll-free"
        } else {
            "${f.countryCode} · Tolls: $tollSummary"
        }

        return TravelEstimate.Builder(
            KartaValhallaManeuverMapper.toCarDistance(f.remainingDistanceMeters),
            DateTimeWithZone.create(arrivalZdt),
        )
            .setRemainingTimeSeconds(remainingSec)
            .setRemainingTimeColor(timeColor)
            .setTripText(CarText.create(tripText))
            .build()
    }

    /**
     * Synchronizes trip progress with Android Auto's `NavigationManager` so dashboard
     * cards and vehicle instrument clusters receive live turn-by-turn & MY/SG/BN toll info.
     */
    private fun syncNavigationManager(f: KartaAutoFrame) {
        if (!f.isNavigating) {
            if (isNavigationActiveOnHost) {
                navigationManager.navigationEnded()
                isNavigationActiveOnHost = false
            }
            return
        }

        if (!isNavigationActiveOnHost) {
            navigationManager.navigationStarted()
            isNavigationActiveOnHost = true
        }

        val activeTheme = KartaAutoTheme.resolve(isDarkMode)
        val destName = route?.destinationName ?: "Destination"
        val destAddress = buildString {
            append(f.countryCode)
            val tollText = route?.tollDisplayTotal ?: f.tripTollSummaryText
            if (!tollText.equals("Free", ignoreCase = true)) {
                append(" · Tolls: $tollText")
            }
        }
        val destination = Destination.Builder()
            .setName(destName)
            .setAddress(destAddress)
            .build()

        val estimate = buildTravelEstimate(f)
        val step = buildCurrentStep(f, activeTheme)
        val stepEstimate = TravelEstimate.Builder(
            KartaValhallaManeuverMapper.toCarDistance(f.distanceToManeuverMeters),
            estimate.arrivalTimeAtDestination!!,
        )
            .setRemainingTimeSeconds(max(1L, f.remainingDurationSeconds.roundToLong()))
            .build()

        val tripBuilder = Trip.Builder()
            .addDestination(destination, estimate)
            .addStep(step, stepEstimate)
            .setLoading(false)

        val currentRoad = f.roadName ?: f.roadRef
        if (!currentRoad.isNullOrBlank()) {
            tripBuilder.setCurrentRoad(currentRoad)
        }
        navigationManager.updateTrip(tripBuilder.build())
    }

    private fun evaluateAlerts(f: KartaAutoFrame) {
        if (carContext.carAppApiLevel < 5) {
            return
        }

        val now = System.currentTimeMillis()

        // 1. Prioritize live dynamic Valhalla reroute proposals
        val rerouteId = f.rerouteProposalId
        val rerouteBanner = f.rerouteBannerText
        if (!rerouteId.isNullOrBlank() && !rerouteBanner.isNullOrBlank() &&
            shouldTriggerAlert("reroute:$rerouteId", now, 60_000L)
        ) {
            val alertId = rerouteId.hashCode()
            val alert = Alert.Builder(alertId, CarText.create(rerouteBanner), 10_000L)
                .setSubtitle(CarText.create(f.rerouteTollDeltaText ?: "Faster corridor"))
                .addAction(
                    Action.Builder()
                        .setTitle("Switch")
                        .setOnClickListener {
                            appManager.dismissAlert(alertId)
                            activeAlertId = null
                            KartaAutoStateStore.emitRerouteDecision(rerouteId, accepted = true)
                        }
                        .build(),
                )
                .addAction(
                    Action.Builder()
                        .setTitle("Keep")
                        .setOnClickListener {
                            appManager.dismissAlert(alertId)
                            activeAlertId = null
                            KartaAutoStateStore.emitRerouteDecision(rerouteId, accepted = false)
                        }
                        .build(),
                )
                .setCallback(
                    object : AlertCallback {
                        override fun onCancel(reason: Int) {
                            if (activeAlertId == alertId) activeAlertId = null
                        }

                        override fun onDismiss() {
                            if (activeAlertId == alertId) activeAlertId = null
                        }
                    },
                )
                .build()
            activeAlertId = alertId
            appManager.showAlert(alert)
            return
        }

        // 2. Approaching crowdsourced road hazard within 1.2 km
        val hazId = f.approachingHazardId
        val hazLabel = f.approachingHazardLabel
        val hazDist = f.approachingHazardDistanceMeters
        if (!hazId.isNullOrBlank() && !hazLabel.isNullOrBlank() &&
            hazDist != null && hazDist <= 1200.0 &&
            shouldTriggerAlert("haz:$hazId", now, 45_000L)
        ) {
            val alertId = hazId.hashCode()
            val alert = Alert.Builder(
                alertId,
                CarText.create("$hazLabel in ${hazDist.roundToInt()}m"),
                8_000L,
            )
                .setSubtitle(CarText.create("Crowdsourced Karta Alert"))
                .addAction(
                    Action.Builder()
                        .setTitle("Still There")
                        .setOnClickListener {
                            appManager.dismissAlert(alertId)
                            activeAlertId = null
                            KartaAutoStateStore.emitHazardVote(hazId, "confirm")
                            CarToast.makeText(carContext, "Hazard confirmed", CarToast.LENGTH_SHORT).show()
                        }
                        .build(),
                )
                .addAction(
                    Action.Builder()
                        .setTitle("Cleared")
                        .setOnClickListener {
                            appManager.dismissAlert(alertId)
                            activeAlertId = null
                            KartaAutoStateStore.emitHazardVote(hazId, "cleared")
                            CarToast.makeText(carContext, "Marked cleared", CarToast.LENGTH_SHORT).show()
                        }
                        .build(),
                )
                .setCallback(
                    object : AlertCallback {
                        override fun onCancel(reason: Int) {
                            if (activeAlertId == alertId) activeAlertId = null
                        }

                        override fun onDismiss() {
                            if (activeAlertId == alertId) activeAlertId = null
                        }
                    },
                )
                .build()
            activeAlertId = alertId
            appManager.showAlert(alert)
        }
    }

    private fun shouldTriggerAlert(key: String, nowMs: Long, cooldownMs: Long): Boolean {
        val prev = alertCooldownsMs[key]
        if (prev != null && (nowMs - prev) < cooldownMs) return false
        alertCooldownsMs[key] = nowMs
        return true
    }
}
