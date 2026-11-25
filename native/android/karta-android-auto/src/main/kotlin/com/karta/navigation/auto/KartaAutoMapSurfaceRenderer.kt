package com.karta.navigation.auto

import android.app.Presentation
import android.content.Context
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.car.app.CarContext
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Flagship MapLibre Native Android surface renderer for Android Auto using
 * `SurfaceCallback` + `VirtualDisplay` + `Presentation`.
 *
 * Capabilities:
 * - Dual-lighting `Obsidian Night` & `Tropical Daylight` styling synced automatically
 *   to the vehicle headlight/dimmer sensor (`carContext.isDarkMode`).
 * - Wide & ultra-wide (21:9 / panoramic) lower-third lookahead camera framing inside
 *   `stableArea` maximizing map canvas visibility ahead of the vehicle puck.
 * - Live non-interactive [KartaAutoSpeedBadgeView] (MY/SG/BN circular speed limit sign +
 *   live tabular `km/h` + overspeed ring) anchored cleanly in the unobstructed corner.
 * - 1-tap `Route Overview` corridor framing (`LatLngBounds`) and conditional recenter signaling.
 * - Offline PMTiles rendering, thermal-adaptive FPS + 3D extrusion throttling, and strict
 *   zero-retention privacy cleanup on [onSurfaceDestroyed].
 */
class KartaAutoMapSurfaceRenderer(
    private val carContext: CarContext,
    private val offlineTileProvider: KartaOfflineTileProvider = KartaOfflineTileProvider(),
) : SurfaceCallback {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var virtualDisplay: VirtualDisplay? = null
    private var presentation: KartaMapPresentation? = null
    private var mapView: MapView? = null
    private var mapLibreMap: MapLibreMap? = null

    private var visibleArea: Rect = Rect()
    private var stableArea: Rect = Rect()
    private var surfaceWidth: Int = 800
    private var surfaceHeight: Int = 480
    private var densityScale: Float = 1.0f
    private var viewportMetrics = KartaAutoViewportMetrics(800, 480, 1.0f)

    private var isCameraLocked: Boolean = true
    private var isRouteOverviewActive: Boolean = false
    private var isDarkMode: Boolean = carContext.isDarkMode
    private var currentZoom: Double = 15.8

    private var latestFrame: KartaAutoFrame = KartaAutoFrame()
    private var latestRouteCoords: List<KartaLatLng> = emptyList()
    private var latestHazards: List<KartaAutoHazardPin> = emptyList()
    private var thermalProfile: KartaAutoThermalProfile = KartaAutoThermalProfile.NOMINAL
    private var offlineConfig: KartaAutoOfflineConfig = KartaAutoOfflineConfig()

    /** Invoked when pan/overview state changes so `KartaNavigationScreen` toggles conditional `Recenter`. */
    var onCameraLockChanged: (() -> Unit)? = null

    val isPannedOrOverview: Boolean
        get() = !isCameraLocked || isRouteOverviewActive

    override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        val surface = surfaceContainer.surface ?: return
        surfaceWidth = max(1, surfaceContainer.width)
        surfaceHeight = max(1, surfaceContainer.height)
        val dpi = max(120, surfaceContainer.dpi)
        densityScale = dpi / 160.0f
        viewportMetrics = KartaAutoViewportMetrics(surfaceWidth, surfaceHeight, densityScale)
        isDarkMode = carContext.isDarkMode

        mainHandler.post {
            tearDownSurface()

            MapLibre.getInstance(carContext)

            val displayManager = carContext.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            virtualDisplay = displayManager.createVirtualDisplay(
                "KartaAndroidAutoMapDisplay",
                surfaceWidth,
                surfaceHeight,
                dpi,
                surface,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
            )

            val display = virtualDisplay?.display ?: return@post
            val activeTheme = KartaAutoTheme.resolve(isDarkMode)
            val pres = KartaMapPresentation(carContext, display, activeTheme)
            pres.show()
            presentation = pres

            val mv = pres.mapView
            mapView = mv
            mv.onCreate(null)
            mv.onStart()
            mv.onResume()
            mv.setMaximumFps(thermalProfile.headUnitTargetFps)

            pres.speedBadgeView.updateFrame(latestFrame, viewportMetrics.speedBadgeScale)
            positionSpeedBadge()

            mv.getMapAsync { map ->
                mapLibreMap = map
                map.uiSettings.apply {
                    isCompassEnabled = false
                    isLogoEnabled = false
                    isAttributionEnabled = false
                }
                loadKartaStyle(map)
            }

            KartaAutoStateStore.emitHeadUnitConnected(
                screenWidthPx = surfaceWidth,
                screenHeightPx = surfaceHeight,
                densityScale = densityScale.toDouble(),
                carAppApiLevel = carContext.carAppApiLevel,
                isDarkMode = isDarkMode,
            )
        }
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        this.visibleArea = Rect(visibleArea)
        mainHandler.post {
            applyCameraPadding()
            positionSpeedBadge()
        }
    }

    override fun onStableAreaChanged(stableArea: Rect) {
        this.stableArea = Rect(stableArea)
        mainHandler.post {
            applyCameraPadding()
            positionSpeedBadge()
        }
    }

    override fun onSurfaceDestroyed(surfaceContainer: SurfaceContainer) {
        mainHandler.post {
            tearDownSurface()
            offlineTileProvider.stop()
        }
    }

    override fun onScroll(distanceX: Float, distanceY: Float) {
        val map = mapLibreMap ?: return
        val wasLocked = isCameraLocked
        isCameraLocked = false
        if (wasLocked) onCameraLockChanged?.invoke()
        mainHandler.post {
            map.scrollBy(-distanceX, -distanceY, 0L)
        }
    }

    override fun onFling(velocityX: Float, velocityY: Float) {
        val map = mapLibreMap ?: return
        val wasLocked = isCameraLocked
        isCameraLocked = false
        if (wasLocked) onCameraLockChanged?.invoke()
        mainHandler.post {
            map.scrollBy(velocityX * 0.08f, velocityY * 0.08f, 220L)
        }
    }

    override fun onScale(focusX: Float, focusY: Float, scaleFactor: Float) {
        val map = mapLibreMap ?: return
        val delta = when {
            scaleFactor > 1.02f -> 0.6
            scaleFactor < 0.98f -> -0.6
            else -> return
        }
        zoomBy(delta, map)
    }

    // ---- Reactive State Bindings ----

    fun applyAppearance(darkMode: Boolean) {
        if (isDarkMode == darkMode && presentation != null) return
        isDarkMode = darkMode
        val theme = KartaAutoTheme.resolve(darkMode)
        mainHandler.post {
            presentation?.applyTheme(theme)
            mapLibreMap?.let { loadKartaStyle(it) }
        }
    }

    fun applyFrame(frame: KartaAutoFrame) {
        latestFrame = frame
        mainHandler.post {
            presentation?.speedBadgeView?.updateFrame(frame, viewportMetrics.speedBadgeScale)
            if (frame.isRouteOverviewActive != isRouteOverviewActive) {
                setRouteOverviewMode(frame.isRouteOverviewActive)
            } else {
                updateVehicleAndCamera()
            }
        }
    }

    fun applyRoute(route: KartaAutoRouteGeometry?) {
        latestRouteCoords = route?.let { KartaPolyline6Decoder.decode(it.routePolyline6) } ?: emptyList()
        mainHandler.post {
            mapLibreMap?.getStyle { style -> upsertRouteOverlay(style) }
            if (isRouteOverviewActive && latestRouteCoords.size >= 2) {
                fitRouteOverviewBounds()
            }
        }
    }

    fun applyHazards(hazards: List<KartaAutoHazardPin>) {
        latestHazards = hazards
        mainHandler.post {
            mapLibreMap?.getStyle { style -> upsertHazardOverlay(style) }
        }
    }

    fun applyThermalProfile(profile: KartaAutoThermalProfile) {
        thermalProfile = profile
        mainHandler.post {
            mapView?.setMaximumFps(profile.headUnitTargetFps)
            mapLibreMap?.getStyle { style ->
                style.getLayer("buildings_3d")?.setProperties(
                    PropertyFactory.visibility(
                        if (profile.enableHeadUnit3DBuildings) Property.VISIBLE else Property.NONE,
                    ),
                )
                style.getLayer(LAYER_VEHICLE_HALO)?.setProperties(
                    PropertyFactory.visibility(
                        if (profile.enableVehicleHaloShader) Property.VISIBLE else Property.NONE,
                    ),
                )
            }
        }
    }

    fun applyOfflineConfig(config: KartaAutoOfflineConfig) {
        val changed = config != offlineConfig
        offlineConfig = config
        if (changed) {
            mainHandler.post {
                mapLibreMap?.let { loadKartaStyle(it) }
            }
        }
    }

    /**
     * Switches between turn-by-turn lower-third follow mode and full-corridor
     * `Route Overview` framing inside Android Auto's `stableArea`.
     */
    fun setRouteOverviewMode(active: Boolean) {
        val changed = isRouteOverviewActive != active
        isRouteOverviewActive = active
        if (active) {
            isCameraLocked = false
            mainHandler.post { fitRouteOverviewBounds() }
        } else {
            isCameraLocked = true
            mainHandler.post {
                applyCameraPadding()
                updateVehicleAndCamera()
            }
        }
        if (changed) {
            onCameraLockChanged?.invoke()
        }
    }

    fun recenterOnVehicle() {
        val wasUnlocked = isPannedOrOverview
        isRouteOverviewActive = false
        isCameraLocked = true
        mainHandler.post {
            applyCameraPadding()
            updateVehicleAndCamera()
        }
        if (wasUnlocked) {
            onCameraLockChanged?.invoke()
        }
    }

    fun zoomBy(delta: Double, explicitMap: MapLibreMap? = null) {
        val map = explicitMap ?: mapLibreMap ?: return
        currentZoom = min(19.0, max(5.5, currentZoom + delta))
        mainHandler.post {
            map.animateCamera(CameraUpdateFactory.zoomTo(currentZoom), 240)
        }
    }

    fun scrubEphemeralState() {
        latestFrame = KartaAutoFrame()
        latestRouteCoords = emptyList()
        latestHazards = emptyList()
        isRouteOverviewActive = false
        isCameraLocked = true
        mainHandler.post {
            presentation?.speedBadgeView?.updateFrame(latestFrame, viewportMetrics.speedBadgeScale)
            mapLibreMap?.getStyle { style ->
                upsertRouteOverlay(style)
                upsertHazardOverlay(style)
                (style.getSourceAs<GeoJsonSource>(SRC_VEHICLE))?.setGeoJson(
                    FeatureCollection.fromFeatures(emptyArray()),
                )
            }
        }
    }

    private fun loadKartaStyle(map: MapLibreMap) {
        val styleJson = offlineTileProvider.buildStyleJson(
            config = offlineConfig,
            enable3DBuildings = thermalProfile.enableHeadUnit3DBuildings,
            isDarkMode = isDarkMode,
        )
        map.setStyle(Style.Builder().fromJson(styleJson)) { style ->
            upsertRouteOverlay(style)
            upsertHazardOverlay(style)
            ensureVehicleLayers(style)
            if (isRouteOverviewActive && latestRouteCoords.size >= 2) {
                fitRouteOverviewBounds()
            } else {
                applyCameraPadding()
                updateVehicleAndCamera()
            }
        }
    }

    private fun applyCameraPadding() {
        val map = mapLibreMap ?: return
        val rect = if (!stableArea.isEmpty) stableArea else visibleArea
        if (rect.isEmpty) return

        val pad = viewportMetrics.navigationPadding(
            stableOrVisible = rect,
            isLeftHandTraffic = latestFrame.isLeftHandTraffic,
        )
        map.moveCamera(
            CameraUpdateFactory.paddingTo(pad[0], pad[1], pad[2], pad[3]),
        )
    }

    private fun fitRouteOverviewBounds() {
        val map = mapLibreMap ?: return
        if (latestRouteCoords.size < 2) return

        val boundsBuilder = LatLngBounds.Builder()
        for (coord in latestRouteCoords) {
            boundsBuilder.include(LatLng(coord.lat, coord.lon))
        }
        val curLat = latestFrame.currentLat
        val curLon = latestFrame.currentLon
        if (curLat != null && curLon != null) {
            boundsBuilder.include(LatLng(curLat, curLon))
        }

        val rect = if (!stableArea.isEmpty) stableArea else visibleArea
        val margin = (24f * max(1f, densityScale)).roundToInt()
        val padL = max(0, rect.left) + margin
        val padT = max(0, rect.top) + margin
        val padR = max(0, surfaceWidth - rect.right) + margin
        val padB = max(0, surfaceHeight - rect.bottom) + margin

        map.animateCamera(
            CameraUpdateFactory.newLatLngBounds(
                boundsBuilder.build(),
                padL,
                padT,
                padR,
                padB,
            ),
            420,
        )
    }

    private fun positionSpeedBadge() {
        val badge = presentation?.speedBadgeView ?: return
        val lp = (badge.layoutParams as? FrameLayout.LayoutParams) ?: FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.END,
        )
        val rect = if (!stableArea.isEmpty) stableArea else visibleArea
        val insetMargin = (14f * max(1f, densityScale)).roundToInt()
        val rightMargin = if (!rect.isEmpty) max(0, surfaceWidth - rect.right) + insetMargin else insetMargin
        val bottomMargin = if (!rect.isEmpty) max(0, surfaceHeight - rect.bottom) + insetMargin else insetMargin
        lp.gravity = Gravity.BOTTOM or Gravity.END
        lp.setMargins(0, 0, rightMargin, bottomMargin)
        badge.layoutParams = lp
    }

    private fun updateVehicleAndCamera() {
        val map = mapLibreMap ?: return
        val lat = latestFrame.currentLat ?: return
        val lon = latestFrame.currentLon ?: return
        val bearing = latestFrame.bearingDeg ?: 0.0

        map.getStyle { style ->
            ensureVehicleLayers(style)
            val pt = Feature.fromGeometry(Point.fromLngLat(lon, lat))
            (style.getSourceAs<GeoJsonSource>(SRC_VEHICLE))?.setGeoJson(pt)
        }

        if (!isCameraLocked || isRouteOverviewActive) return

        currentZoom = when {
            latestFrame.currentSpeedKmh >= 95.0 -> 15.2
            latestFrame.currentSpeedKmh >= 60.0 -> 16.2
            else -> 17.0
        }
        val cam = CameraPosition.Builder()
            .target(LatLng(lat, lon))
            .zoom(currentZoom)
            .tilt(thermalProfile.headUnitCameraPitchDeg)
            .bearing(bearing)
            .build()
        map.animateCamera(CameraUpdateFactory.newCameraPosition(cam), 320)
    }

    private fun upsertRouteOverlay(style: Style) {
        val theme = KartaAutoTheme.resolve(isDarkMode)
        val pts = latestRouteCoords.map { Point.fromLngLat(it.lon, it.lat) }
        val fc = if (pts.size >= 2) {
            FeatureCollection.fromFeature(Feature.fromGeometry(LineString.fromLngLats(pts)))
        } else {
            FeatureCollection.fromFeatures(emptyArray())
        }

        val existing = style.getSourceAs<GeoJsonSource>(SRC_ROUTE)
        if (existing != null) {
            existing.setGeoJson(fc)
            style.getLayer(LAYER_ROUTE_CASING)?.setProperties(
                PropertyFactory.lineColor(theme.routeCasingHex),
                PropertyFactory.lineWidth(viewportMetrics.routeCasingWidth),
            )
            style.getLayer(LAYER_ROUTE_LINE)?.setProperties(
                PropertyFactory.lineColor(theme.routeCoreHex),
                PropertyFactory.lineWidth(viewportMetrics.routeLineWidth),
            )
            return
        }

        style.addSource(GeoJsonSource(SRC_ROUTE, fc))
        style.addLayer(
            LineLayer(LAYER_ROUTE_CASING, SRC_ROUTE).withProperties(
                PropertyFactory.lineColor(theme.routeCasingHex),
                PropertyFactory.lineWidth(viewportMetrics.routeCasingWidth),
                PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
            ),
        )
        style.addLayer(
            LineLayer(LAYER_ROUTE_LINE, SRC_ROUTE).withProperties(
                PropertyFactory.lineColor(theme.routeCoreHex),
                PropertyFactory.lineWidth(viewportMetrics.routeLineWidth),
                PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
            ),
        )
    }

    private fun upsertHazardOverlay(style: Style) {
        val theme = KartaAutoTheme.resolve(isDarkMode)
        val features = latestHazards.map { h ->
            Feature.fromGeometry(Point.fromLngLat(h.lon, h.lat)).apply {
                addStringProperty("category", h.category)
                addStringProperty("severity", h.severity)
            }
        }
        val fc = FeatureCollection.fromFeatures(features)
        val existing = style.getSourceAs<GeoJsonSource>(SRC_HAZARDS)
        if (existing != null) {
            existing.setGeoJson(fc)
            style.getLayer(LAYER_HAZARDS)?.setProperties(
                PropertyFactory.circleColor(theme.hazardFillHex),
                PropertyFactory.circleStrokeColor(theme.hazardStrokeHex),
            )
            return
        }

        style.addSource(GeoJsonSource(SRC_HAZARDS, fc))
        style.addLayer(
            CircleLayer(LAYER_HAZARDS, SRC_HAZARDS).withProperties(
                PropertyFactory.circleRadius(9.5f),
                PropertyFactory.circleColor(theme.hazardFillHex),
                PropertyFactory.circleStrokeColor(theme.hazardStrokeHex),
                PropertyFactory.circleStrokeWidth(2.2f),
            ),
        )
    }

    private fun ensureVehicleLayers(style: Style) {
        val theme = KartaAutoTheme.resolve(isDarkMode)
        if (style.getSource(SRC_VEHICLE) != null) {
            style.getLayer(LAYER_VEHICLE_HALO)?.setProperties(
                PropertyFactory.circleColor(theme.puckHaloHex),
            )
            style.getLayer(LAYER_VEHICLE_CORE)?.setProperties(
                PropertyFactory.circleColor(theme.puckCoreHex),
                PropertyFactory.circleStrokeColor(theme.puckStrokeHex),
            )
            return
        }
        style.addSource(GeoJsonSource(SRC_VEHICLE, FeatureCollection.fromFeatures(emptyArray())))
        style.addLayer(
            CircleLayer(LAYER_VEHICLE_HALO, SRC_VEHICLE).withProperties(
                PropertyFactory.circleRadius(19.0f),
                PropertyFactory.circleColor(theme.puckHaloHex),
                PropertyFactory.circleOpacity(0.28f),
                PropertyFactory.visibility(
                    if (thermalProfile.enableVehicleHaloShader) Property.VISIBLE else Property.NONE,
                ),
            ),
        )
        style.addLayer(
            CircleLayer(LAYER_VEHICLE_CORE, SRC_VEHICLE).withProperties(
                PropertyFactory.circleRadius(8.5f),
                PropertyFactory.circleColor(theme.puckCoreHex),
                PropertyFactory.circleStrokeColor(theme.puckStrokeHex),
                PropertyFactory.circleStrokeWidth(2.6f),
            ),
        )
    }

    private fun tearDownSurface() {
        mapView?.let { mv ->
            mv.onPause()
            mv.onStop()
            mv.onDestroy()
        }
        mapView = null
        mapLibreMap = null
        presentation?.dismiss()
        presentation = null
        virtualDisplay?.release()
        virtualDisplay = null
    }

    private class KartaMapPresentation(
        context: Context,
        display: Display,
        initialTheme: KartaAutoTheme,
    ) : Presentation(context, display) {
        val rootContainer = FrameLayout(context)
        val mapView: MapView = MapView(context)
        val speedBadgeView: KartaAutoSpeedBadgeView = KartaAutoSpeedBadgeView(context)

        init {
            applyTheme(initialTheme)
        }

        fun applyTheme(theme: KartaAutoTheme) {
            mapView.setBackgroundColor(theme.backgroundPrimary)
            speedBadgeView.applyTheme(theme)
        }

        override fun onCreate(savedInstanceState: android.os.Bundle?) {
            super.onCreate(savedInstanceState)
            rootContainer.addView(
                mapView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            rootContainer.addView(
                speedBadgeView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM or Gravity.END,
                ),
            )
            setContentView(rootContainer)
        }
    }

    companion object {
        private const val SRC_ROUTE = "karta-aa-route-src"
        private const val LAYER_ROUTE_CASING = "karta-aa-route-casing"
        private const val LAYER_ROUTE_LINE = "karta-aa-route-line"
        private const val SRC_HAZARDS = "karta-aa-hazards-src"
        private const val LAYER_HAZARDS = "karta-aa-hazards-circle"
        private const val SRC_VEHICLE = "karta-aa-vehicle-src"
        private const val LAYER_VEHICLE_HALO = "karta-aa-vehicle-halo"
        private const val LAYER_VEHICLE_CORE = "karta-aa-vehicle-core"
    }
}
