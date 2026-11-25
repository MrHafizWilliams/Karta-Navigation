#if canImport(CarPlay) && canImport(UIKit)
import CarPlay
import CoreLocation
import UIKit

#if canImport(MapLibre)
import MapLibre
#endif

/// Projects Karta's MapLibre Native iOS renderer onto the CarPlay `CPWindow` with:
/// - Automatic **Obsidian Night** (`#0D0F12`) & **Tropical Daylight** (`#F5F2EB`) synchronization
///   driven by the vehicle's headlight/dimmer sensor (`traitCollection.userInterfaceStyle`).
/// - Wide & ultra-wide (16:9, 21:9, 24:9) lower-third lookahead camera framing & route scaling.
/// - Non-interactive MY/SG/BN Speed-Limit & Speedometer HUD overlay anchored in safe area.
/// - 1-tap Route Overview (`fitBounds`) mode, offline PMTiles/TileJSON support, and thermal FPS caps.
public final class KartaCarPlayMapViewController: UIViewController, KartaCarPlayStateObserver {
    private let stateStore: KartaCarPlayStateStore
    private let speedBadgeView = KartaCarPlaySpeedBadgeView()

    private var currentFrame: KartaCarPlayNavigationFrame = .idle
    private var activeRouteCoords: [CLLocationCoordinate2D] = []
    private var activeHazards: [KartaCarPlayHazardPin] = []
    private var thermalProfile: KartaCarPlayThermalProfile = .nominal
    private var offlineConfig: KartaCarPlayOfflineMapConfig = .defaultConfig
    private var activeTheme: KartaCarPlayTheme = .obsidianNight
    private var viewportMetrics: KartaCarPlayViewportMetrics = KartaCarPlayViewportMetrics(
        boundsSize: CGSize(width: 800, height: 480),
        scale: 2.0
    )

    private var isCameraLockedToVehicle = true
    private var isRouteOverviewActive = false
    private var currentZoomLevel: Double = 15.8

    private var speedBadgeTrailingConstraint: NSLayoutConstraint?
    private var speedBadgeBottomConstraint: NSLayoutConstraint?

    /// Notifies `KartaCarPlaySceneDelegate` whenever the vehicle headlight/dimmer sensor toggles.
    public var onHeadlightAppearanceChanged: ((Bool) -> Void)?

    #if canImport(MapLibre)
    private var mapView: MLNMapView?
    #else
    private let tacticalCanvasView = KartaCarPlayFallbackCanvasView()
    #endif

    public init(stateStore: KartaCarPlayStateStore = .shared) {
        self.stateStore = stateStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        activeTheme = KartaCarPlayTheme.resolve(for: traitCollection)
        view.backgroundColor = activeTheme.backgroundPrimary

        #if canImport(MapLibre)
        setupMapLibreView()
        #else
        setupFallbackCanvasView()
        #endif

        setupSpeedBadgeOverlay()

        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.handleVehicleHeadlightTraitChange()
            }
        }

        stateStore.addObserver(self)
        hydrateFromStore()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let nextMetrics = KartaCarPlayViewportMetrics(
            boundsSize: view.bounds.size,
            scale: view.window?.screen.scale ?? UIScreen.main.scale
        )
        if nextMetrics != viewportMetrics {
            viewportMetrics = nextMetrics
            applySafeAreaCameraPadding()
            updateSpeedBadgeLayout()
            syncRouteAndOverlays()
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applySafeAreaCameraPadding()
        updateSpeedBadgeLayout()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0) {
            if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
                handleVehicleHeadlightTraitChange()
            }
        }
    }

    deinit {
        tearDownRenderer()
    }

    public var isCurrentlyDarkMode: Bool {
        activeTheme.isDarkMode
    }

    public var isOverviewMode: Bool {
        isRouteOverviewActive
    }

    public var isCameraLocked: Bool {
        isCameraLockedToVehicle
    }

    /// Releases GPU / Metal resources and scrubs volatile location coordinates when
    /// CarPlay disconnects to protect thermals and privacy.
    public func tearDownRenderer() {
        stateStore.removeObserver(self)
        activeRouteCoords = []
        activeHazards = []
        currentFrame = .idle
        speedBadgeView.isHidden = true

        #if canImport(MapLibre)
        mapView?.delegate = nil
        mapView?.removeFromSuperview()
        mapView = nil
        #else
        tacticalCanvasView.scrub()
        #endif
    }

    // MARK: - Vehicle Headlight / Dimmer Sensor Theme Sync

    private func handleVehicleHeadlightTraitChange() {
        let sensorDark = traitCollection.userInterfaceStyle != .light
        applyTheme(isDarkMode: sensorDark, notifyBridge: true)
    }

    public func applyTheme(isDarkMode: Bool, notifyBridge: Bool) {
        let next = KartaCarPlayTheme.resolve(isDarkMode: isDarkMode)
        guard next.isDarkMode != activeTheme.isDarkMode else { return }
        activeTheme = next
        view.backgroundColor = activeTheme.backgroundPrimary
        speedBadgeView.applyTheme(activeTheme)
        reloadBasemapStyle()

        if notifyBridge {
            stateStore.emitHeadUnitAppearanceChanged(
                isDarkMode: isDarkMode,
                source: "carplay_headlight_sensor"
            )
            onHeadlightAppearanceChanged?(isDarkMode)
        }
    }

    // MARK: - CarPlay Overview / Pan / Zoom / Recenter Controls

    public func setRouteOverviewMode(_ active: Bool) {
        isRouteOverviewActive = active
        if active {
            isCameraLockedToVehicle = false
            fitActiveRouteOverview(animated: true)
        } else {
            isCameraLockedToVehicle = true
            updateCameraForCurrentFrame(animated: true)
        }
    }

    public func recenterOnVehicle() {
        isRouteOverviewActive = false
        isCameraLockedToVehicle = true
        updateCameraForCurrentFrame(animated: true)
    }

    public func zoomBy(delta: Double) {
        isRouteOverviewActive = false
        currentZoomLevel = min(19.0, max(5.5, currentZoomLevel + delta))
        #if canImport(MapLibre)
        if let mv = mapView {
            mv.setZoomLevel(currentZoomLevel, animated: true)
        }
        #else
        tacticalCanvasView.zoom = currentZoomLevel
        tacticalCanvasView.setNeedsDisplay()
        #endif
    }

    public func pan(direction: CPMapTemplate.PanDirection) {
        isRouteOverviewActive = false
        isCameraLockedToVehicle = false
        let stepDeg = 0.004 * pow(2.0, max(0.0, 15.0 - currentZoomLevel))
        var dLat = 0.0
        var dLon = 0.0
        if direction.contains(.up) { dLat += stepDeg }
        if direction.contains(.down) { dLat -= stepDeg }
        if direction.contains(.right) { dLon += stepDeg }
        if direction.contains(.left) { dLon -= stepDeg }

        #if canImport(MapLibre)
        if let mv = mapView {
            let next = CLLocationCoordinate2D(
                latitude: mv.centerCoordinate.latitude + dLat,
                longitude: mv.centerCoordinate.longitude + dLon
            )
            mv.setCenter(next, animated: true)
        }
        #else
        tacticalCanvasView.panBy(dLat: dLat, dLon: dLon)
        #endif
    }

    // MARK: - KartaCarPlayStateObserver

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateFrame frame: KartaCarPlayNavigationFrame) {
        currentFrame = frame
        speedBadgeView.update(frame: frame, scale: viewportMetrics.speedBadgeScale)
        if !isRouteOverviewActive {
            updateCameraForCurrentFrame(animated: true)
        }
    }

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateRoute route: KartaCarPlayRouteGeometry?) {
        if let route = route {
            activeRouteCoords = KartaPolyline6Decoder.decode(route.routePolyline6)
        } else {
            activeRouteCoords = []
        }
        syncRouteAndOverlays()
        if isRouteOverviewActive {
            fitActiveRouteOverview(animated: true)
        }
    }

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateHazards hazards: [KartaCarPlayHazardPin]) {
        activeHazards = hazards
        syncRouteAndOverlays()
    }

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateThermalProfile profile: KartaCarPlayThermalProfile) {
        thermalProfile = profile
        applyThermalBudget(profile)
    }

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateOfflineConfig config: KartaCarPlayOfflineMapConfig) {
        let changed = config != offlineConfig
        offlineConfig = config
        if changed {
            reloadBasemapStyle()
        }
    }

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateAppearance isDarkMode: Bool) {
        applyTheme(isDarkMode: isDarkMode, notifyBridge: false)
    }

    public func stateStoreDidScrubEphemeralLocation(_ store: KartaCarPlayStateStore) {
        currentFrame = .idle
        activeRouteCoords = []
        activeHazards = []
        isRouteOverviewActive = false
        speedBadgeView.isHidden = true
        syncRouteAndOverlays()
        #if !canImport(MapLibre)
        tacticalCanvasView.scrub()
        #endif
    }

    // MARK: - Private Setup & Rendering

    private func setupSpeedBadgeOverlay() {
        speedBadgeView.translatesAutoresizingMaskIntoConstraints = false
        speedBadgeView.isHidden = true
        speedBadgeView.applyTheme(activeTheme)
        view.addSubview(speedBadgeView)

        let trailing = speedBadgeView.trailingAnchor.constraint(
            equalTo: view.trailingAnchor,
            constant: -(view.safeAreaInsets.right + 16)
        )
        let bottom = speedBadgeView.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -(view.safeAreaInsets.bottom + 14)
        )
        speedBadgeTrailingConstraint = trailing
        speedBadgeBottomConstraint = bottom
        NSLayoutConstraint.activate([trailing, bottom])
    }

    private func updateSpeedBadgeLayout() {
        speedBadgeTrailingConstraint?.constant = -(view.safeAreaInsets.right + 16)
        speedBadgeBottomConstraint?.constant = -(view.safeAreaInsets.bottom + 14)
        speedBadgeView.update(frame: currentFrame, scale: viewportMetrics.speedBadgeScale)
    }

    private func hydrateFromStore() {
        offlineConfig = stateStore.offlineConfig
        thermalProfile = stateStore.thermalProfile
        if let route = stateStore.activeRoute {
            activeRouteCoords = KartaPolyline6Decoder.decode(route.routePolyline6)
        }
        activeHazards = stateStore.hazards
        currentFrame = stateStore.latestFrame
        speedBadgeView.update(frame: currentFrame, scale: viewportMetrics.speedBadgeScale)
        applyThermalBudget(thermalProfile)
        syncRouteAndOverlays()
        updateCameraForCurrentFrame(animated: false)
    }

    #if canImport(MapLibre)
    private func setupMapLibreView() {
        UserDefaults.standard.set(false, forKey: "MGLMapboxMetricsEnabled")

        let mv = MLNMapView(frame: view.bounds)
        mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mv.backgroundColor = activeTheme.backgroundPrimary
        mv.delegate = self
        mv.compassView.isHidden = true
        mv.logoView.isHidden = true
        mv.attributionButton.isHidden = true
        mv.allowsRotating = true
        mv.allowsTilting = true
        mv.showsUserLocation = false
        mv.preferredFramesPerSecond = MLNMapViewPreferredFramesPerSecond(rawValue: thermalProfile.headUnitTargetFps)

        view.addSubview(mv)
        self.mapView = mv
        reloadBasemapStyle()
    }
    #else
    private func setupFallbackCanvasView() {
        tacticalCanvasView.frame = view.bounds
        tacticalCanvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tacticalCanvasView.theme = activeTheme
        view.addSubview(tacticalCanvasView)
    }
    #endif

    private func reloadBasemapStyle() {
        #if canImport(MapLibre)
        guard let mv = mapView else { return }
        mv.backgroundColor = activeTheme.backgroundPrimary
        if let styleURL = buildTemporaryKartaStyleURL(isDarkMode: activeTheme.isDarkMode) {
            mv.styleURL = styleURL
        }
        #else
        tacticalCanvasView.theme = activeTheme
        tacticalCanvasView.setNeedsDisplay()
        #endif
    }

    private func applyThermalBudget(_ profile: KartaCarPlayThermalProfile) {
        #if canImport(MapLibre)
        guard let mv = mapView else { return }
        mv.preferredFramesPerSecond = MLNMapViewPreferredFramesPerSecond(rawValue: profile.headUnitTargetFps)
        if let style = mv.style, let bldg3d = style.layer(withIdentifier: "buildings_3d") {
            bldg3d.isVisible = profile.enableHeadUnit3DBuildings
        }
        #else
        tacticalCanvasView.enable3D = profile.enableHeadUnit3DBuildings
        tacticalCanvasView.setNeedsDisplay()
        #endif
    }

    private func applySafeAreaCameraPadding() {
        #if canImport(MapLibre)
        guard let mv = mapView else { return }
        mv.automaticallyAdjustsContentInset = false
        mv.contentInset = viewportMetrics.navigationEdgePadding(
            safeArea: view.safeAreaInsets,
            isLeftHandTraffic: currentFrame.isLeftHandTraffic
        )
        #endif
    }

    private func fitActiveRouteOverview(animated: Bool) {
        guard activeRouteCoords.count >= 2 else { return }
        #if canImport(MapLibre)
        guard let mv = mapView else { return }
        var minLat = activeRouteCoords[0].latitude
        var maxLat = minLat
        var minLon = activeRouteCoords[0].longitude
        var maxLon = minLon
        for c in activeRouteCoords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        )
        let pad = UIEdgeInsets(
            top: view.safeAreaInsets.top + 36,
            left: view.safeAreaInsets.left + 36,
            bottom: view.safeAreaInsets.bottom + 42,
            right: view.safeAreaInsets.right + 36
        )
        mv.setVisibleCoordinateBounds(bounds, edgePadding: pad, animated: animated, completionHandler: nil)
        #else
        tacticalCanvasView.zoom = 11.2
        tacticalCanvasView.setNeedsDisplay()
        #endif
    }

    private func updateCameraForCurrentFrame(animated: Bool) {
        guard let lat = currentFrame.currentLat, let lon = currentFrame.currentLon else {
            return
        }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let bearing = currentFrame.bearingDeg ?? 0.0
        let speed = currentFrame.currentSpeedKmh

        if isCameraLockedToVehicle {
            let wideOffset = viewportMetrics.viewportClass == .ultraWide ? -0.25 : 0.0
            currentZoomLevel = (speed >= 95 ? 15.2 : (speed >= 60 ? 16.2 : 17.0)) + wideOffset
        }

        #if canImport(MapLibre)
        guard let mv = mapView else { return }
        updateVehiclePuckGeoJSON(coord: coord, bearing: bearing)
        guard isCameraLockedToVehicle else { return }

        let altitude = altitudeForZoom(currentZoomLevel, latitude: lat)
        let pitch = CGFloat(thermalProfile.headUnitCameraPitchDeg)
        let camera = MLNMapCamera(
            lookingAtCenter: coord,
            altitude: altitude,
            pitch: pitch,
            heading: bearing
        )
        let navPadding = viewportMetrics.navigationEdgePadding(
            safeArea: view.safeAreaInsets,
            isLeftHandTraffic: currentFrame.isLeftHandTraffic
        )
        mv.setCamera(
            camera,
            withDuration: animated ? 0.35 : 0.0,
            animationTimingFunction: CAMediaTimingFunction(name: .easeOut),
            edgePadding: navPadding,
            completionHandler: nil
        )
        #else
        tacticalCanvasView.vehicleCoord = coord
        tacticalCanvasView.vehicleBearing = bearing
        tacticalCanvasView.zoom = currentZoomLevel
        tacticalCanvasView.setNeedsDisplay()
        #endif
    }

    private func syncRouteAndOverlays() {
        #if canImport(MapLibre)
        guard let style = mapView?.style else { return }
        upsertRouteLayer(in: style)
        upsertHazardLayer(in: style)
        #else
        tacticalCanvasView.routeCoords = activeRouteCoords
        tacticalCanvasView.hazards = activeHazards
        tacticalCanvasView.setNeedsDisplay()
        #endif
    }

    #if canImport(MapLibre)
    private func altitudeForZoom(_ zoom: Double, latitude: Double) -> CLLocationDistance {
        let metersPerPixel = (156543.03392 * cos(latitude * .pi / 180.0)) / pow(2.0, zoom)
        return max(120.0, metersPerPixel * 640.0)
    }

    private func upsertRouteLayer(in style: MLNStyle) {
        let sourceId = "karta-carplay-route-src"
        let casingId = "karta-carplay-route-casing"
        let lineId = "karta-carplay-route-line"

        let shape: MLNShape
        if activeRouteCoords.count >= 2 {
            var coords = activeRouteCoords
            shape = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
        } else {
            shape = MLNShapeCollectionFeature(shapes: [])
        }

        if let existing = style.source(withIdentifier: sourceId) as? MLNShapeSource {
            existing.shape = shape
            if let casing = style.layer(withIdentifier: casingId) as? MLNLineStyleLayer {
                casing.lineColor = NSExpression(forConstantValue: activeTheme.routeCasing)
                casing.lineWidth = NSExpression(forConstantValue: viewportMetrics.routeCasingWidth)
            }
            if let line = style.layer(withIdentifier: lineId) as? MLNLineStyleLayer {
                line.lineColor = NSExpression(forConstantValue: activeTheme.routeCore)
                line.lineWidth = NSExpression(forConstantValue: viewportMetrics.routeLineWidth)
            }
        } else {
            let src = MLNShapeSource(identifier: sourceId, shape: shape, options: nil)
            style.addSource(src)

            let casing = MLNLineStyleLayer(identifier: casingId, source: src)
            casing.lineColor = NSExpression(forConstantValue: activeTheme.routeCasing)
            casing.lineWidth = NSExpression(forConstantValue: viewportMetrics.routeCasingWidth)
            casing.lineCap = NSExpression(forConstantValue: "round")
            casing.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(casing)

            let line = MLNLineStyleLayer(identifier: lineId, source: src)
            line.lineColor = NSExpression(forConstantValue: activeTheme.routeCore)
            line.lineWidth = NSExpression(forConstantValue: viewportMetrics.routeLineWidth)
            line.lineCap = NSExpression(forConstantValue: "round")
            line.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(line)
        }
    }

    private func upsertHazardLayer(in style: MLNStyle) {
        let sourceId = "karta-carplay-hazards-src"
        let layerId = "karta-carplay-hazards-circle"

        let features: [MLNPointFeature] = activeHazards.map { haz in
            let pt = MLNPointFeature()
            pt.coordinate = CLLocationCoordinate2D(latitude: haz.lat, longitude: haz.lon)
            pt.attributes = ["category": haz.category, "severity": haz.severity]
            return pt
        }
        let collection = MLNShapeCollectionFeature(shapes: features)

        if let existing = style.source(withIdentifier: sourceId) as? MLNShapeSource {
            existing.shape = collection
        } else {
            let src = MLNShapeSource(identifier: sourceId, shape: collection, options: nil)
            style.addSource(src)

            let circle = MLNCircleStyleLayer(identifier: layerId, source: src)
            circle.circleRadius = NSExpression(forConstantValue: 10.0)
            circle.circleColor = NSExpression(forConstantValue: activeTheme.statusAlert)
            circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            circle.circleStrokeWidth = NSExpression(forConstantValue: 2.4)
            style.addLayer(circle)
        }
    }

    private func updateVehiclePuckGeoJSON(coord: CLLocationCoordinate2D, bearing: Double) {
        guard let style = mapView?.style else { return }
        let sourceId = "karta-carplay-vehicle-src"
        let haloId = "karta-carplay-vehicle-halo"
        let puckId = "karta-carplay-vehicle-core"

        let pt = MLNPointFeature()
        pt.coordinate = coord
        pt.attributes = ["bearing": bearing]

        if let existing = style.source(withIdentifier: sourceId) as? MLNShapeSource {
            existing.shape = pt
            if let halo = style.layer(withIdentifier: haloId) {
                halo.isVisible = thermalProfile.enableVehicleHaloShader
            }
        } else {
            let src = MLNShapeSource(identifier: sourceId, shape: pt, options: nil)
            style.addSource(src)

            let halo = MLNCircleStyleLayer(identifier: haloId, source: src)
            halo.circleRadius = NSExpression(forConstantValue: 19.0)
            halo.circleColor = NSExpression(forConstantValue: activeTheme.accentPrimary.withAlphaComponent(0.30))
            halo.isVisible = thermalProfile.enableVehicleHaloShader
            style.addLayer(halo)

            let core = MLNCircleStyleLayer(identifier: puckId, source: src)
            core.circleRadius = NSExpression(forConstantValue: 9.0)
            core.circleColor = NSExpression(forConstantValue: activeTheme.accentBright)
            core.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            core.circleStrokeWidth = NSExpression(forConstantValue: 2.6)
            style.addLayer(core)
        }
    }

    /// Generates Karta Obsidian Night (`#0D0F12`) or Tropical Daylight (`#F5F2EB`) MapLibre style JSON.
    private func buildTemporaryKartaStyleURL(isDarkMode: Bool) -> URL? {
        let tileUrl: String
        if offlineConfig.offlineModeEnabled, let localPath = offlineConfig.localPmtilesPaths.first {
            tileUrl = localPath.hasPrefix("pmtiles://") ? localPath : "pmtiles://file://\(localPath)"
        } else {
            let raw = offlineConfig.activePmtilesUrl
            tileUrl = raw.hasSuffix(".json") ? raw : raw.replacingOccurrences(of: ".pmtiles", with: ".json")
        }

        let isDay = !isDarkMode
        let styleObject: [String: Any] = [
            "version": 8,
            "name": isDay ? "Karta Tropical Daylight CarPlay v1" : "Karta Obsidian Night CarPlay v1",
            "sources": [
                "karta_basemap": [
                    "type": "vector",
                    "url": tileUrl
                ]
            ],
            "layers": [
                [
                    "id": "background",
                    "type": "background",
                    "paint": ["background-color": isDay ? "#F5F2EB" : "#0D0F12"]
                ],
                [
                    "id": "park",
                    "type": "fill",
                    "source": "karta_basemap",
                    "source-layer": "park",
                    "paint": ["fill-color": isDay ? "#D4E6D9" : "#132622", "fill-opacity": 0.88]
                ],
                [
                    "id": "water",
                    "type": "fill",
                    "source": "karta_basemap",
                    "source-layer": "water",
                    "paint": ["fill-color": isDay ? "#C9E0EA" : "#070B12"]
                ],
                [
                    "id": "roads_minor",
                    "type": "line",
                    "source": "karta_basemap",
                    "source-layer": "transportation",
                    "minzoom": 11,
                    "filter": ["in", "class", "minor", "service", "street"],
                    "paint": ["line-color": isDay ? "#FFFFFF" : "#252E3B", "line-width": 2.6]
                ],
                [
                    "id": "roads_major",
                    "type": "line",
                    "source": "karta_basemap",
                    "source-layer": "transportation",
                    "minzoom": 6,
                    "filter": ["in", "class", "primary", "secondary", "tertiary", "trunk"],
                    "paint": ["line-color": isDay ? "#FCEFD8" : "#384759", "line-width": 5.0]
                ],
                [
                    "id": "roads_motorway_casing",
                    "type": "line",
                    "source": "karta_basemap",
                    "source-layer": "transportation",
                    "filter": ["==", "class", "motorway"],
                    "paint": ["line-color": isDay ? "#163834" : "#090B0E", "line-width": 8.6]
                ],
                [
                    "id": "roads_motorway",
                    "type": "line",
                    "source": "karta_basemap",
                    "source-layer": "transportation",
                    "filter": ["==", "class", "motorway"],
                    "paint": ["line-color": isDay ? "#2F756F" : "#5B9A94", "line-width": 6.4, "line-opacity": 0.92]
                ],
                [
                    "id": "buildings_3d",
                    "type": "fill-extrusion",
                    "source": "karta_basemap",
                    "source-layer": "building",
                    "minzoom": 13.5,
                    "layout": ["visibility": thermalProfile.enableHeadUnit3DBuildings ? "visible" : "none"],
                    "paint": [
                        "fill-extrusion-color": isDay ? "#E2DED4" : "#181C22",
                        "fill-extrusion-height": ["coalesce", ["get", "render_height"], ["get", "height"], 14],
                        "fill-extrusion-opacity": 0.90
                    ]
                ]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: styleObject, options: []) else {
            return nil
        }
        let filename = isDay ? "karta-carplay-day-v1.json" : "karta-carplay-night-v1.json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return url
    }
    #endif
}

#if canImport(MapLibre)
extension KartaCarPlayMapViewController: MLNMapViewDelegate {
    public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        applyThermalBudget(thermalProfile)
        syncRouteAndOverlays()
        if isRouteOverviewActive {
            fitActiveRouteOverview(animated: false)
        } else {
            updateCameraForCurrentFrame(animated: false)
        }
    }
}
#endif

#if !canImport(MapLibre)
/// Compile-safe dual-theme vector canvas used when SwiftPM builds without the binary MapLibre XCFramework.
private final class KartaCarPlayFallbackCanvasView: UIView {
    var theme: KartaCarPlayTheme = .obsidianNight
    var routeCoords: [CLLocationCoordinate2D] = []
    var hazards: [KartaCarPlayHazardPin] = []
    var vehicleCoord: CLLocationCoordinate2D?
    var vehicleBearing: Double = 0
    var zoom: Double = 15.5
    var enable3D: Bool = true
    private var panOffset = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    func panBy(dLat: Double, dLon: Double) {
        panOffset = CLLocationCoordinate2D(
            latitude: panOffset.latitude + dLat,
            longitude: panOffset.longitude + dLon
        )
        setNeedsDisplay()
    }

    func scrub() {
        routeCoords = []
        hazards = []
        vehicleCoord = nil
        panOffset = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        theme.backgroundPrimary.setFill()
        ctx.fill(rect)

        let center = vehicleCoord ?? CLLocationCoordinate2D(latitude: 3.1579, longitude: 101.7116)
        let effCenter = CLLocationCoordinate2D(
            latitude: center.latitude + panOffset.latitude,
            longitude: center.longitude + panOffset.longitude
        )
        let scale = pow(2.0, zoom) * 0.35

        func project(_ c: CLLocationCoordinate2D) -> CGPoint {
            let dx = (c.longitude - effCenter.longitude) * scale
            let dy = -(c.latitude - effCenter.latitude) * scale
            return CGPoint(x: rect.midX + dx, y: rect.height * 0.66 + dy)
        }

        ctx.setStrokeColor(theme.borderSubtle.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1.0)
        stride(from: CGFloat(0), to: rect.width, by: 48).forEach { x in
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: rect.height))
        }
        stride(from: CGFloat(0), to: rect.height, by: 48).forEach { y in
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: rect.width, y: y))
        }
        ctx.strokePath()

        if routeCoords.count >= 2 {
            ctx.setStrokeColor(theme.routeCore.cgColor)
            ctx.setLineWidth(7.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: project(routeCoords[0]))
            for c in routeCoords.dropFirst() {
                ctx.addLine(to: project(c))
            }
            ctx.strokePath()
        }

        for haz in hazards {
            let pt = project(CLLocationCoordinate2D(latitude: haz.lat, longitude: haz.lon))
            theme.statusAlert.setFill()
            ctx.fillEllipse(in: CGRect(x: pt.x - 9, y: pt.y - 9, width: 18, height: 18))
        }

        if let vc = vehicleCoord {
            let pt = project(vc)
            theme.accentPrimary.withAlphaComponent(0.30).setFill()
            ctx.fillEllipse(in: CGRect(x: pt.x - 18, y: pt.y - 18, width: 36, height: 36))
            theme.accentBright.setFill()
            ctx.fillEllipse(in: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16))
        }
    }
}
#endif
#endif
