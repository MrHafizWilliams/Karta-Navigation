package com.karta.navigation.auto

/**
 * Pure Kotlin bidirectional dispatcher for Flutter's `com.karta.navigation/automotive_bridge`
 * `MethodChannel`. Wire this directly from your Android host `FlutterEngine` plugin:
 *
 * ```kotlin
 * val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KartaAutomotiveBridgeHandler.CHANNEL_NAME)
 * val handler = KartaAutomotiveBridgeHandler { method, args ->
 *     mainHandler.post { channel.invokeMethod(method, args) }
 * }
 * channel.setMethodCallHandler { call, result ->
 *     val handled = handler.handleMethodCall(call.method, call.arguments as? Map<*, *>)
 *     if (handled) result.success(null) else result.notImplemented()
 * }
 * ```
 */
class KartaAutomotiveBridgeHandler(
    outboundSink: KartaAutoBridgeOutboundSink,
) {
    init {
        KartaAutoStateStore.setOutboundSink(outboundSink)
    }

    fun handleMethodCall(method: String, arguments: Map<*, *>?): Boolean {
        val payload = arguments ?: emptyMap<String, Any>()
        return when (method) {
            "syncFullState" -> {
                KartaAutoStateStore.applyFullStateEnvelope(payload)
                true
            }
            "publishNavigationFrame" -> {
                KartaAutoStateStore.updateFrame(KartaAutoFrame.fromMap(payload))
                true
            }
            "updateRouteGeometry" -> {
                KartaAutoStateStore.updateRoute(KartaAutoRouteGeometry.fromMap(payload))
                true
            }
            "updateHazards" -> {
                val list = (payload["hazards"] as? List<*>)
                    ?.mapNotNull { (it as? Map<*, *>)?.let(KartaAutoHazardPin::fromMap) }
                    ?: emptyList()
                KartaAutoStateStore.updateHazards(list)
                true
            }
            "applyThermalRenderProfile" -> {
                KartaAutoStateStore.updateThermalProfile(KartaAutoThermalProfile.fromMap(payload))
                true
            }
            "updateOfflineMapConfig" -> {
                KartaAutoStateStore.updateOfflineConfig(KartaAutoOfflineConfig.fromMap(payload))
                true
            }
            "setVehicleAppearance" -> {
                val isDark = (payload["isDarkMode"] as? Boolean) ?: true
                KartaAutoStateStore.updateAppearance(isDark)
                true
            }
            "endAutomotiveSession", "scrubEphemeralLocationState" -> {
                KartaAutoStateStore.scrubEphemeralLocationState()
                true
            }
            else -> false
        }
    }

    fun detach() {
        KartaAutoStateStore.setOutboundSink(null)
    }

    companion object {
        const val CHANNEL_NAME = "com.karta.navigation/automotive_bridge"
    }
}
