package com.karta.navigation.auto

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.res.Configuration
import androidx.car.app.AppManager
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Production Android Auto [CarAppService] implementing the Android for Cars App Library.
 *
 * - Uses release-safe [HostValidator] allowlist (allowing Desktop Head Unit only in debug builds).
 * - Decoupled from Flutter UI widgets; binds shared routing state, offline MapLibre renderer,
 *   hands-free voice reporting, thermal governor, and zero-retention privacy scrubbing via
 *   [KartaAutoStateStore].
 */
class KartaCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator {
        val isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        return if (isDebuggable) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    override fun onCreateSession(): Session = KartaCarSession()
}

/**
 * Android Auto projection [Session] orchestrating:
 * - [KartaAutoMapSurfaceRenderer] bound to `AppManager.setSurfaceCallback`
 * - [NavigationManager] stop/auto-drive callbacks
 * - [KartaAutoVoiceController] hands-free hazard voice reporting
 * - [KartaAutoThermalGovernor] adaptive FPS & 3D building throttling
 * - Clean Car -> Phone handoff and ephemeral GPS RAM scrubbing on session destroy.
 */
class KartaCarSession : Session(), DefaultLifecycleObserver {

    private lateinit var mapRenderer: KartaAutoMapSurfaceRenderer
    private lateinit var voiceController: KartaAutoVoiceController
    private lateinit var thermalGovernor: KartaAutoThermalGovernor

    override fun onCreateScreen(intent: Intent): Screen {
        lifecycle.addObserver(this)

        // Seed initial vehicle headlight/dimmer state before mounting the MapLibre surface
        KartaAutoStateStore.updateAppearance(carContext.isDarkMode)

        mapRenderer = KartaAutoMapSurfaceRenderer(carContext)
        voiceController = KartaAutoVoiceController(carContext)
        thermalGovernor = KartaAutoThermalGovernor(carContext)

        // Register MapLibre SurfaceCallback onto Android Auto host surface.
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(mapRenderer)

        // Bind NavigationManager stop callback back into Dart's NavigationSessionController.
        val navManager = carContext.getCarService(NavigationManager::class.java)
        navManager.setNavigationManagerCallback(
            object : NavigationManagerCallback {
                override fun onStopNavigation() {
                    KartaAutoStateStore.emitNavigationControlAction("end_trip")
                }

                override fun onAutoDriveEnabled() {
                    // Android Auto DHU simulation notification — no mock override needed.
                }
            },
        )

        // Observe volatile state store reactively to drive the MapLibre surface.
        lifecycleScope.launch {
            KartaAutoStateStore.frame.collectLatest { mapRenderer.applyFrame(it) }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.route.collectLatest { mapRenderer.applyRoute(it) }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.hazards.collectLatest { mapRenderer.applyHazards(it) }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.thermalProfile.collectLatest { mapRenderer.applyThermalProfile(it) }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.offlineConfig.collectLatest { mapRenderer.applyOfflineConfig(it) }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.isDarkMode.collectLatest { mapRenderer.applyAppearance(it) }
        }
        lifecycleScope.launch {
            KartaAutoStateStore.isRouteOverviewActive.collectLatest { mapRenderer.setRouteOverviewMode(it) }
        }

        thermalGovernor.start()

        return KartaNavigationScreen(
            carContext = carContext,
            mapRenderer = mapRenderer,
            voiceController = voiceController,
        )
    }

    override fun onCarConfigurationChanged(newConfiguration: Configuration) {
        super.onCarConfigurationChanged(newConfiguration)
        // Automatic vehicle headlight / dashboard dimmer sensor sync (Obsidian Night <-> Tropical Daylight)
        val darkMode = carContext.isDarkMode
        KartaAutoStateStore.emitHeadUnitAppearanceChanged(
            isDarkMode = darkMode,
            source = "android_auto_headlight_sensor",
        )
        if (::mapRenderer.isInitialized) {
            mapRenderer.applyAppearance(darkMode)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Handle voice search / steering-wheel navigation intents without blocking UI.
        if (intent.action == CarContext.ACTION_NAVIGATE) {
            mapRenderer.recenterOnVehicle()
        }
    }

    override fun onDestroy(owner: LifecycleOwner) {
        if (::voiceController.isInitialized) voiceController.stop()
        if (::thermalGovernor.isInitialized) thermalGovernor.stop()
        if (::mapRenderer.isInitialized) mapRenderer.scrubEphemeralState()

        // Signal seamless Car -> Phone handoff and immediately scrub native location RAM.
        KartaAutoStateStore.emitHeadUnitDisconnected(reason = "android_auto_session_destroyed")
        KartaAutoStateStore.scrubEphemeralLocationState()
    }
}
