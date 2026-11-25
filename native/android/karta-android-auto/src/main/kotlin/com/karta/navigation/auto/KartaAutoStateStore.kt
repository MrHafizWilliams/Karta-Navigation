package com.karta.navigation.auto

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Outbound sink delivering Android Auto user & lifecycle actions back to Dart's `KartaAutomotiveBridge`. */
fun interface KartaAutoBridgeOutboundSink {
    fun sendToDart(method: String, arguments: Map<String, Any?>)
}

/**
 * Volatile, RAM-only automotive state store shared across [KartaCarAppService],
 * [KartaNavigationScreen], [KartaAutoMapSurfaceRenderer], and [KartaAutomotiveBridgeHandler].
 *
 * Location privacy guarantee:
 * - Zero disk/SharedPreferences/SQLite persistence of raw GPS coordinates.
 * - Zero raw coordinates emitted to Android Logcat.
 * - [scrubEphemeralLocationState] immediately clears active coordinates and route buffers in RAM.
 */
object KartaAutoStateStore {
    private val _frame = MutableStateFlow(KartaAutoFrame())
    private val _route = MutableStateFlow<KartaAutoRouteGeometry?>(null)
    private val _hazards = MutableStateFlow<List<KartaAutoHazardPin>>(emptyList())
    private val _thermalProfile = MutableStateFlow(KartaAutoThermalProfile.NOMINAL)
    private val _offlineConfig = MutableStateFlow(KartaAutoOfflineConfig())
    private val _isDarkMode = MutableStateFlow(true)
    private val _isRouteOverviewActive = MutableStateFlow(false)
    private val _lastSequenceId = AtomicInteger(0)
    private val _outboundSink = AtomicReference<KartaAutoBridgeOutboundSink?>(null)

    val frame: StateFlow<KartaAutoFrame> = _frame.asStateFlow()
    val route: StateFlow<KartaAutoRouteGeometry?> = _route.asStateFlow()
    val hazards: StateFlow<List<KartaAutoHazardPin>> = _hazards.asStateFlow()
    val thermalProfile: StateFlow<KartaAutoThermalProfile> = _thermalProfile.asStateFlow()
    val offlineConfig: StateFlow<KartaAutoOfflineConfig> = _offlineConfig.asStateFlow()
    val isDarkMode: StateFlow<Boolean> = _isDarkMode.asStateFlow()
    val isRouteOverviewActive: StateFlow<Boolean> = _isRouteOverviewActive.asStateFlow()
    val lastSequenceId: Int get() = _lastSequenceId.get()

    fun setOutboundSink(sink: KartaAutoBridgeOutboundSink?) {
        _outboundSink.set(sink)
    }

    /** Atomic Phone -> Android Auto handoff state hydration on head-unit connect. */
    fun applyFullStateEnvelope(payload: Map<*, *>) {
        val envelopeSeq = (payload["sequenceId"] as? Number)?.toInt() ?: 0
        (payload["offlineConfig"] as? Map<*, *>)?.let {
            _offlineConfig.value = KartaAutoOfflineConfig.fromMap(it)
        }
        (payload["thermalProfile"] as? Map<*, *>)?.let {
            _thermalProfile.value = KartaAutoThermalProfile.fromMap(it)
        }
        val routeMap = payload["routeGeometry"] as? Map<*, *>
        _route.value = routeMap?.let(KartaAutoRouteGeometry::fromMap)

        val hazardMaps = (payload["hazards"] as? List<*>)
            ?.mapNotNull { (it as? Map<*, *>)?.let(KartaAutoHazardPin::fromMap) }
            ?: emptyList()
        _hazards.value = hazardMaps

        (payload["isDarkMode"] as? Boolean)?.let { _isDarkMode.value = it }

        (payload["frame"] as? Map<*, *>)?.let { frameMap ->
            val next = KartaAutoFrame.fromMap(frameMap)
            val seq = maxOf(envelopeSeq, next.sequenceId)
            if (seq > _lastSequenceId.get()) _lastSequenceId.set(seq)
            _frame.value = next
            _isRouteOverviewActive.value = next.isRouteOverviewActive
        }
    }

    fun updateFrame(next: KartaAutoFrame) {
        if (next.sequenceId > 0 && next.sequenceId < _lastSequenceId.get()) {
            return // Ignore stale out-of-order IPC frame
        }
        if (next.sequenceId > 0) {
            _lastSequenceId.set(next.sequenceId)
        }
        _frame.value = next
        if (_isRouteOverviewActive.value != next.isRouteOverviewActive) {
            _isRouteOverviewActive.value = next.isRouteOverviewActive
        }
    }

    fun updateAppearance(isDarkMode: Boolean) {
        _isDarkMode.value = isDarkMode
    }

    fun updateRouteOverview(active: Boolean) {
        _isRouteOverviewActive.value = active
    }

    fun updateRoute(route: KartaAutoRouteGeometry?) {
        _route.value = route
    }

    fun updateHazards(hazards: List<KartaAutoHazardPin>) {
        _hazards.value = hazards
    }

    fun updateThermalProfile(profile: KartaAutoThermalProfile) {
        _thermalProfile.value = profile
    }

    fun updateOfflineConfig(config: KartaAutoOfflineConfig) {
        _offlineConfig.value = config
    }

    /** Zeroes all live volatile GPS fix & trip geometry references in RAM. */
    fun scrubEphemeralLocationState() {
        _frame.value = KartaAutoFrame()
        _route.value = null
        _hazards.value = emptyList()
        _isRouteOverviewActive.value = false
    }

    // ---- Outbound Android Auto -> Dart Callbacks ----

    fun emitHeadUnitConnected(
        screenWidthPx: Int,
        screenHeightPx: Int,
        densityScale: Double,
        carAppApiLevel: Int,
        isDarkMode: Boolean = true,
    ) {
        _isDarkMode.value = isDarkMode
        _outboundSink.get()?.sendToDart(
            method = "onHeadUnitConnected",
            arguments = mapOf(
                "platform" to "android_auto",
                "screenWidthPx" to screenWidthPx,
                "screenHeightPx" to screenHeightPx,
                "densityScale" to densityScale,
                "apiLevel" to carAppApiLevel,
                "supportsInstrumentCluster" to (carAppApiLevel >= 2),
                "supportsOfflineSurface" to true,
                "supportsVoiceInput" to (carAppApiLevel >= 5),
                "isDarkMode" to isDarkMode,
            ),
        )
    }

    fun emitHeadUnitAppearanceChanged(
        isDarkMode: Boolean,
        source: String = "android_auto_headlight_sensor",
    ) {
        _isDarkMode.value = isDarkMode
        _outboundSink.get()?.sendToDart(
            method = "onHeadUnitAppearanceChanged",
            arguments = mapOf(
                "platform" to "android_auto",
                "isDarkMode" to isDarkMode,
                "source" to source,
            ),
        )
    }

    fun emitHeadUnitDisconnected(reason: String) {
        _outboundSink.get()?.sendToDart(
            method = "onHeadUnitDisconnected",
            arguments = mapOf(
                "platform" to "android_auto",
                "reason" to reason,
                "lastSequenceId" to _lastSequenceId.get(),
            ),
        )
    }

    fun emitQuickReportHazard(
        categoryWire: String,
        severityWire: String = "medium",
        oppositeSide: Boolean = false,
    ) {
        _outboundSink.get()?.sendToDart(
            method = "onQuickReportHazard",
            arguments = mapOf(
                "category" to categoryWire,
                "severity" to severityWire,
                "oppositeSide" to oppositeSide,
                "source" to "android_auto",
            ),
        )
    }

    fun emitHazardVote(hazardId: String, vote: String) {
        _outboundSink.get()?.sendToDart(
            method = "onHazardVote",
            arguments = mapOf("hazardId" to hazardId, "vote" to vote),
        )
    }

    fun emitVoiceReportTriggered(localeTag: String = "en-MY") {
        _outboundSink.get()?.sendToDart(
            method = "onVoiceReportTriggered",
            arguments = mapOf("localeTag" to localeTag),
        )
    }

    fun emitVoiceTranscript(transcript: String, localeTag: String = "en-MY") {
        _outboundSink.get()?.sendToDart(
            method = "onVoiceTranscriptCaptured",
            arguments = mapOf("transcript" to transcript, "localeTag" to localeTag),
        )
    }

    fun emitRerouteDecision(proposalId: String, accepted: Boolean) {
        _outboundSink.get()?.sendToDart(
            method = "onRerouteDecision",
            arguments = mapOf("proposalId" to proposalId, "accepted" to accepted),
        )
    }

    fun emitNavigationControlAction(action: String) {
        _outboundSink.get()?.sendToDart(
            method = "onNavigationControlAction",
            arguments = mapOf("action" to action),
        )
    }

    fun emitThermalState(
        thermalLevel: String,
        batteryLevelPercent: Int?,
        isCharging: Boolean,
        batteryTempCelsius: Double?,
        isLowPowerMode: Boolean,
    ) {
        _outboundSink.get()?.sendToDart(
            method = "onThermalStateChanged",
            arguments = mapOf(
                "platform" to "android_auto",
                "thermalLevel" to thermalLevel,
                "batteryLevelPercent" to batteryLevelPercent,
                "isCharging" to isCharging,
                "batteryTempCelsius" to batteryTempCelsius,
                "isLowPowerMode" to isLowPowerMode,
            ),
        )
    }
}
