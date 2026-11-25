#if canImport(CarPlay) && canImport(UIKit)
import CarPlay
import CoreLocation
import Foundation
import MapKit
import UIKit

/// Flagship Apple CarPlay scene delegate implementing `CPTemplateApplicationSceneDelegate`
/// and `CPMapTemplateDelegate` for Karta Navigation (MY / SG / BN).
///
/// Key automotive standards enforced:
/// - **Maximum Map Canvas Visibility**: `automaticallyHidesNavigationBar = true` with minimal
///   floating map chrome (`Pan` + conditional `Recenter` only when off-lock/overview).
/// - **Automatic Headlight / Dimmer Sensor Sync**: dynamically mirrors Karta's Obsidian Night
///   (`#0D0F12` / `#181C22`) and Tropical Daylight (`#F5F2EB` / `#FCFBF8`) across `CPMapTemplate`,
///   MapLibre style, speed-limit HUD, and maneuver/lane glyphs.
/// - **Zero-Distraction 3 Primary One-Tap Controls** with rotary-controller focus rings:
///   1. `Voice Report` (EN / BM / Manglish / Singlish hands-free hazard capture)
///   2. `Guidance Audio` (`Mute` / `Unmute`)
///   3. `Route Overview / Cancel` (1-tap full corridor fit-bounds + safe Cancel/Resume sheet)
/// - **Strict Distraction Limits**: template stack depth ≤ 2, deduplicated 8s `CPNavigationAlert`.
public final class KartaCarPlaySceneDelegate: UIResponder,
    CPTemplateApplicationSceneDelegate,
    CPMapTemplateDelegate,
    KartaCarPlayStateObserver
{
    private let stateStore: KartaCarPlayStateStore
    private lazy var voiceBridge = KartaCarPlayVoiceBridge(stateStore: stateStore)
    private lazy var thermalMonitor = KartaCarPlayThermalMonitor(stateStore: stateStore)

    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?
    private var mapViewController: KartaCarPlayMapViewController?
    private var mapTemplate: CPMapTemplate?
    private var navigationSession: CPNavigationSession?
    private var activeTripId: String = ""
    private var activeTheme: KartaCarPlayTheme = .obsidianNight

    private var presentedAlertTimestamps: [String: Date] = [:]
    private var hazardGridAutoDismissWorkItem: DispatchWorkItem?
    private var isVoiceMuted = false
    private var isRouteOverviewActive = false
    private var isMapPanned = false

    private struct QuickHazardOption {
        let categoryWire: String
        let severityWire: String
        let title: String
        let sfSymbol: String
        let accent: UIColor
    }

    private static let quickHazardOptions: [QuickHazardOption] = [
        QuickHazardOption(
            categoryWire: "police",
            severityWire: "medium",
            title: "Police",
            sfSymbol: "shield.lefthalf.filled",
            accent: KartaCarPlayPalette.statusInfo
        ),
        QuickHazardOption(
            categoryWire: "accident",
            severityWire: "high",
            title: "Accident",
            sfSymbol: "car.2.fill",
            accent: KartaCarPlayPalette.statusAlert
        ),
        QuickHazardOption(
            categoryWire: "pothole",
            severityWire: "medium",
            title: "Pothole",
            sfSymbol: "exclamationmark.triangle.fill",
            accent: KartaCarPlayPalette.statusCaution
        ),
        QuickHazardOption(
            categoryWire: "hidden_vehicle",
            severityWire: "medium",
            title: "Stopped Car",
            sfSymbol: "car.fill",
            accent: UIColor(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0, alpha: 1.0)
        ),
        QuickHazardOption(
            categoryWire: "road_debris",
            severityWire: "medium",
            title: "Debris",
            sfSymbol: "cone.fill",
            accent: UIColor(red: 0xA8 / 255.0, green: 0x55 / 255.0, blue: 0xF7 / 255.0, alpha: 1.0)
        ),
        QuickHazardOption(
            categoryWire: "road_closure",
            severityWire: "high",
            title: "Closure",
            sfSymbol: "nosign",
            accent: KartaCarPlayPalette.statusAlert
        )
    ]

    public override init() {
        self.stateStore = .shared
        super.init()
    }

    public init(stateStore: KartaCarPlayStateStore) {
        self.stateStore = stateStore
        super.init()
    }

    // MARK: - CPTemplateApplicationSceneDelegate

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.carWindow = window

        // Resolve initial Obsidian Night vs. Tropical Daylight from vehicle headlight sensor.
        let initialDarkMode = window.traitCollection.userInterfaceStyle != .light
        activeTheme = KartaCarPlayTheme.resolve(isDarkMode: initialDarkMode)

        // 1. Mount MapLibre Native iOS renderer + speed-limit HUD into CarPlay CPWindow.
        let mapVC = KartaCarPlayMapViewController(stateStore: stateStore)
        mapVC.onHeadlightAppearanceChanged = { [weak self] isDark in
            self?.applyTemplateTheme(isDarkMode: isDark)
        }
        window.rootViewController = mapVC
        self.mapViewController = mapVC

        // 2. Build dashboard-first CPMapTemplate maximizing unobstructed map canvas area.
        let template = CPMapTemplate()
        template.mapDelegate = self
        template.guidanceBackgroundColor = activeTheme.surfaceCard
        template.tripEstimateStyle = activeTheme.tripEstimateStyle
        template.automaticallyHidesNavigationBar = true
        template.hidesButtonsWithNavigationBar = false
        self.mapTemplate = template
        refreshStreamlinedControls(isNavigating: stateStore.latestFrame.isNavigating)

        interfaceController.setRootTemplate(template, animated: true, completion: nil)

        // 3. Configure navigation audio ducking, thermal monitor, and reactive state observer.
        voiceBridge.configureNavigationAudioSession()
        thermalMonitor.startMonitoring()
        stateStore.addObserver(self)

        // 4. Announce CarPlay connect (with viewport dims & headlight theme) for Phone -> Car handoff.
        let scale = Double(window.screen.scale)
        let widthPx = Int(window.bounds.width * CGFloat(scale))
        let heightPx = Int(window.bounds.height * CGFloat(scale))
        stateStore.emitHeadUnitConnected(
            screenWidthPx: max(widthPx, 800),
            screenHeightPx: max(heightPx, 480),
            densityScale: scale,
            supportsInstrumentCluster: false,
            isDarkMode: initialDarkMode
        )

        applyNavigationFrame(stateStore.latestFrame)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        hazardGridAutoDismissWorkItem?.cancel()
        hazardGridAutoDismissWorkItem = nil

        navigationSession?.finishTrip()
        navigationSession = nil
        activeTripId = ""
        isRouteOverviewActive = false
        isMapPanned = false
        presentedAlertTimestamps.removeAll()

        voiceBridge.stopListening()
        thermalMonitor.stopMonitoring()
        stateStore.removeObserver(self)

        mapViewController?.tearDownRenderer()
        mapViewController = nil
        window.rootViewController = nil

        stateStore.emitHeadUnitDisconnected(reason: "carplay_scene_disconnected")
        stateStore.scrubEphemeralLocationState()

        self.mapTemplate = nil
        self.interfaceController = nil
        self.carWindow = nil
    }

    public func applyNavigationFrame(_ payload: [String: Any]) {
        applyNavigationFrame(KartaCarPlayNavigationFrame.from(payload))
    }

    // MARK: - KartaCarPlayStateObserver

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateFrame frame: KartaCarPlayNavigationFrame) {
        applyNavigationFrame(frame)
    }

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateRoute route: KartaCarPlayRouteGeometry?) {
        if let route = route, stateStore.latestFrame.isNavigating, route.tripId != activeTripId {
            startOrReplaceNavigationSession(frame: stateStore.latestFrame, route: route)
        }
    }

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateHazards hazards: [KartaCarPlayHazardPin]) {}
    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateThermalProfile profile: KartaCarPlayThermalProfile) {}
    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateOfflineConfig config: KartaCarPlayOfflineMapConfig) {}

    public func stateStore(_ store: KartaCarPlayStateStore, didUpdateAppearance isDarkMode: Bool) {
        applyTemplateTheme(isDarkMode: isDarkMode)
    }

    public func stateStoreDidScrubEphemeralLocation(_ store: KartaCarPlayStateStore) {
        navigationSession?.finishTrip()
        navigationSession = nil
        activeTripId = ""
        isRouteOverviewActive = false
        isMapPanned = false
        presentedAlertTimestamps.removeAll()
        refreshStreamlinedControls(isNavigating: false)
    }

    // MARK: - Headlight / Dimmer Theme Sync

    private func applyTemplateTheme(isDarkMode: Bool) {
        let next = KartaCarPlayTheme.resolve(isDarkMode: isDarkMode)
        guard next.isDarkMode != activeTheme.isDarkMode else { return }
        activeTheme = next
        mapTemplate?.guidanceBackgroundColor = activeTheme.surfaceCard
        mapTemplate?.tripEstimateStyle = activeTheme.tripEstimateStyle
        refreshStreamlinedControls(isNavigating: stateStore.latestFrame.isNavigating)
        if stateStore.latestFrame.isNavigating {
            applyNavigationFrame(stateStore.latestFrame)
        }
    }

    // MARK: - High-Contrast Turn-by-Turn, Lane Guidance & Toll/ETA

    public func applyNavigationFrame(_ frame: KartaCarPlayNavigationFrame) {
        guard let mapTemplate = self.mapTemplate else { return }

        if isVoiceMuted != frame.voiceMuted || isRouteOverviewActive != frame.isRouteOverviewActive {
            isVoiceMuted = frame.voiceMuted
            if isRouteOverviewActive != frame.isRouteOverviewActive {
                isRouteOverviewActive = frame.isRouteOverviewActive
                mapViewController?.setRouteOverviewMode(isRouteOverviewActive)
            }
            refreshStreamlinedControls(isNavigating: frame.isNavigating)
        }

        guard frame.isNavigating else {
            if navigationSession != nil {
                navigationSession?.finishTrip()
                navigationSession = nil
                activeTripId = ""
                isRouteOverviewActive = false
                refreshStreamlinedControls(isNavigating: false)
            }
            return
        }

        if navigationSession == nil || (!frame.tripId.isEmpty && frame.tripId != activeTripId) {
            startOrReplaceNavigationSession(frame: frame, route: stateStore.activeRoute)
            refreshStreamlinedControls(isNavigating: true)
        }

        guard let session = navigationSession else { return }

        let primaryManeuver = buildPrimaryManeuver(from: frame)
        var maneuvers: [CPManeuver] = [primaryManeuver]

        if let secondaryText = frame.secondaryInstruction, !secondaryText.isEmpty {
            let nextManeuver = CPManeuver()
            nextManeuver.instructionVariants = ["Then \(secondaryText)", secondaryText]
            if let nextType = frame.nextManeuverType {
                nextManeuver.symbolImage = KartaManeuverGlyphRenderer.maneuverSymbolImage(
                    valhallaType: nextType,
                    isLeftHandTraffic: frame.isLeftHandTraffic,
                    theme: activeTheme,
                    size: CGSize(width: 30, height: 30),
                    isSecondary: true
                )
            }
            maneuvers.append(nextManeuver)
        }

        session.upcomingManeuvers = maneuvers
        session.updateEstimates(
            CPTravelEstimates(
                distanceRemaining: Measurement(value: max(0, frame.distanceToManeuverMeters), unit: UnitLength.meters),
                timeRemaining: max(0, frame.remainingDurationSeconds)
            ),
            for: primaryManeuver
        )

        if #available(iOS 17.4, *) {
            if let laneGuidance = KartaManeuverGlyphRenderer.buildNativeLaneGuidance(
                lanes: frame.laneItems,
                instructionVariants: laneInstructionVariants(for: frame)
            ) {
                session.add([laneGuidance])
                session.currentLaneGuidance = laneGuidance
            } else {
                session.currentLaneGuidance = nil
            }
        }

        let tripEstimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: max(0, frame.remainingDistanceMeters), unit: UnitLength.meters),
            timeRemaining: max(0, frame.remainingDurationSeconds)
        )
        mapTemplate.update(tripEstimates, for: session.trip)

        presentRerouteAlertIfNeeded(frame: frame, on: mapTemplate)
        presentHazardAlertIfNeeded(frame: frame, on: mapTemplate)
    }

    private func startOrReplaceNavigationSession(
        frame: KartaCarPlayNavigationFrame,
        route: KartaCarPlayRouteGeometry?
    ) {
        guard let mapTemplate = self.mapTemplate else { return }
        navigationSession?.finishTrip()

        let origin = MKMapItem.forCurrentLocation()
        let destCoord = CLLocationCoordinate2D(
            latitude: route?.destinationLat ?? frame.currentLat ?? 3.1579,
            longitude: route?.destinationLon ?? frame.currentLon ?? 101.7116
        )
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        destination.name = route?.destinationName ?? "Destination"

        let tollText = route?.tollDisplayTotal ?? frame.tripTollSummaryText
        let tollVariant = tollText.lowercased() == "free" ? "Toll-free route" : "Tolls: \(tollText)"

        let routeChoice = CPRouteChoice(
            summaryVariants: [destination.name ?? "Active Route"],
            additionalInformationVariants: [tollVariant],
            selectionSummaryVariants: ["\(frame.countryCode) · \(tollVariant)"]
        )

        let trip = CPTrip(origin: origin, destination: destination, routeChoices: [routeChoice])
        navigationSession = mapTemplate.startNavigationSession(for: trip)
        activeTripId = !frame.tripId.isEmpty ? frame.tripId : (route?.tripId ?? UUID().uuidString)
    }

    private func buildPrimaryManeuver(from frame: KartaCarPlayNavigationFrame) -> CPManeuver {
        let maneuver = CPManeuver()

        // WCAG AAA bold vector maneuver arrow adapted to Obsidian Night / Tropical Daylight
        maneuver.symbolImage = KartaManeuverGlyphRenderer.maneuverSymbolImage(
            valhallaType: frame.maneuverType,
            isLeftHandTraffic: frame.isLeftHandTraffic,
            theme: activeTheme,
            size: CGSize(width: 56, height: 56),
            isSecondary: false
        )

        var variants: [String] = []
        if let tollName = frame.approachingTollName, !tollName.isEmpty {
            let tollDist = formatCompactMeters(frame.approachingTollDistanceMeters ?? 0)
            let payments = frame.approachingTollPayments.prefix(2).joined(separator: "/")
            let badgeSuffix = payments.isEmpty ? "" : " [\(payments)]"
            variants.append("\(frame.primaryInstruction) · Toll \(tollDist): \(tollName)\(badgeSuffix)")
        }
        if let ref = frame.roadRef, !ref.isEmpty {
            variants.append("[\(ref)] \(frame.primaryInstruction)")
        }
        variants.append(frame.primaryInstruction)
        maneuver.instructionVariants = variants

        let tollTag = frame.tripTollSummaryText.lowercased() == "free"
            ? "Toll-free"
            : "Tolls \(frame.tripTollSummaryText)"
        if let roadName = frame.roadName, !roadName.isEmpty {
            maneuver.dashboardInstructionVariants = ["\(roadName) · \(tollTag)", roadName]
        } else {
            maneuver.dashboardInstructionVariants = [tollTag]
        }

        // Wide-format, dual-theme compound lane-guidance & MY/SG/BN toll payment strip
        maneuver.junctionImage = KartaManeuverGlyphRenderer.renderLaneAndTollStripImage(
            lanes: frame.laneItems,
            approachingTollPayments: frame.approachingTollPayments,
            approachingTollName: frame.approachingTollName,
            theme: activeTheme
        )

        maneuver.initialTravelEstimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: max(0, frame.distanceToManeuverMeters), unit: UnitLength.meters),
            timeRemaining: max(0, frame.remainingDurationSeconds)
        )
        return maneuver
    }

    private func laneInstructionVariants(for frame: KartaCarPlayNavigationFrame) -> [String] {
        if let tollName = frame.approachingTollName, !tollName.isEmpty {
            let payments = frame.approachingTollPayments.prefix(3).joined(separator: " · ")
            return ["\(tollName) (\(payments))", tollName]
        }
        if let ref = frame.roadRef, !ref.isEmpty {
            return ["Keep in highlighted lane for \(ref)", "Follow highlighted lane"]
        }
        return ["Follow highlighted lane"]
    }

    // MARK: - Zero-Distraction 3 Primary One-Tap Controls + Rotary Focus Rings

    private func refreshStreamlinedControls(isNavigating: Bool) {
        guard let mapTemplate = self.mapTemplate else { return }

        // Action 1 (Leading): Hands-Free Voice Report (primary rotary target)
        let voiceIcon = KartaManeuverGlyphRenderer.rotaryActionIcon(
            sfSymbol: "mic.fill",
            theme: activeTheme,
            highlighted: true
        )
        let voiceButton = CPBarButton(image: voiceIcon) { [weak self] _ in
            self?.triggerHandsFreeVoice()
        }
        voiceButton.accessibilityLabel = "Voice Report"
        mapTemplate.leadingNavigationBarButtons = [voiceButton]

        // Action 2 (Trailing 1): Guidance Audio Mute / Unmute
        let audioIcon = KartaManeuverGlyphRenderer.rotaryActionIcon(
            sfSymbol: isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            theme: activeTheme,
            highlighted: !isVoiceMuted
        )
        let muteButton = CPBarButton(image: audioIcon) { [weak self] _ in
            guard let self = self else { return }
            self.isVoiceMuted.toggle()
            self.stateStore.emitNavigationControlAction("toggle_mute")
            self.refreshStreamlinedControls(isNavigating: self.stateStore.latestFrame.isNavigating)
        }
        muteButton.accessibilityLabel = isVoiceMuted ? "Unmute Guidance Audio" : "Mute Guidance Audio"

        // Action 3 (Trailing 2): Route Overview / Cancel (or Quick Hazard when idle)
        var trailing: [CPBarButton] = [muteButton]
        if isNavigating {
            let overviewIcon = KartaManeuverGlyphRenderer.rotaryActionIcon(
                sfSymbol: isRouteOverviewActive ? "xmark.circle.fill" : "map.fill",
                theme: activeTheme,
                highlighted: isRouteOverviewActive,
                destructive: false
            )
            let overviewOrCancelButton = CPBarButton(image: overviewIcon) { [weak self] _ in
                self?.handleOverviewOrCancelTap()
            }
            overviewOrCancelButton.accessibilityLabel = isRouteOverviewActive
                ? "Route Options and End Trip"
                : "Route Overview"
            trailing.append(overviewOrCancelButton)
        } else {
            let hazardIcon = KartaManeuverGlyphRenderer.rotaryActionIcon(
                sfSymbol: "exclamationmark.triangle.fill",
                theme: activeTheme,
                highlighted: false
            )
            let reportBtn = CPBarButton(image: hazardIcon) { [weak self] _ in
                self?.presentQuickHazardGrid()
            }
            reportBtn.accessibilityLabel = "Report Road Hazard"
            trailing.append(reportBtn)
        }
        mapTemplate.trailingNavigationBarButtons = trailing

        // Minimal Map Buttons (maximize unobstructed canvas; <= 2 buttons, Recenter only when needed)
        var mapButtons: [CPMapButton] = []
        if isMapPanned || isRouteOverviewActive {
            let recenterBtn = CPMapButton { [weak self] _ in
                guard let self = self else { return }
                self.isMapPanned = false
                self.isRouteOverviewActive = false
                self.mapViewController?.recenterOnVehicle()
                self.stateStore.emitNavigationControlAction("recenter")
                self.refreshStreamlinedControls(isNavigating: self.stateStore.latestFrame.isNavigating)
            }
            recenterBtn.image = KartaManeuverGlyphRenderer.rotaryActionIcon(
                sfSymbol: "location.north.fill",
                theme: activeTheme,
                highlighted: true,
                size: CGSize(width: 34, height: 34)
            )
            recenterBtn.accessibilityLabel = "Recenter on Vehicle"
            mapButtons.append(recenterBtn)
        }

        let panBtn = CPMapButton { [weak self] _ in
            guard let tmpl = self?.mapTemplate else { return }
            if tmpl.isPanningInterfaceVisible {
                tmpl.dismissPanningInterface(animated: true)
            } else {
                tmpl.showPanningInterface(animated: true)
            }
        }
        panBtn.image = KartaManeuverGlyphRenderer.rotaryActionIcon(
            sfSymbol: "arrow.up.and.down.and.arrow.left.and.right",
            theme: activeTheme,
            highlighted: false,
            size: CGSize(width: 34, height: 34)
        )
        panBtn.accessibilityLabel = "Pan Map"
        mapButtons.append(panBtn)

        mapTemplate.mapButtons = mapButtons
    }

    /// 1st tap enters Route Overview framing the full route; tapping while in Overview presents
    /// a rotary-safe 3-item `CPActionSheetTemplate` (Resume, Report Hazard, End Navigation).
    private func handleOverviewOrCancelTap() {
        if !isRouteOverviewActive {
            isRouteOverviewActive = true
            mapViewController?.setRouteOverviewMode(true)
            stateStore.emitNavigationControlAction("toggle_overview")
            refreshStreamlinedControls(isNavigating: true)
            return
        }

        guard let ic = interfaceController else { return }
        let resume = CPAlertAction(title: "Resume Guidance", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.isRouteOverviewActive = false
            self.mapViewController?.setRouteOverviewMode(false)
            self.stateStore.emitNavigationControlAction("recenter")
            self.refreshStreamlinedControls(isNavigating: true)
        }
        let reportHazard = CPAlertAction(title: "Report Road Hazard", style: .default) { [weak self] _ in
            self?.presentQuickHazardGrid()
        }
        let endTrip = CPAlertAction(title: "End Navigation", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.isRouteOverviewActive = false
            self.stateStore.emitNavigationControlAction("end_trip")
        }

        let sheet = CPActionSheetTemplate(
            title: "Active Route",
            message: stateStore.activeRoute?.destinationName ?? "Manage navigation",
            actions: [resume, reportHazard, endTrip]
        )
        ic.presentTemplate(sheet, animated: true, completion: nil)
    }

    /// Distraction-compliant 1-screen 6-item `CPGridTemplate` (template depth <= 2, 12s auto-pop).
    private func presentQuickHazardGrid() {
        guard let ic = interfaceController, ic.templates.count < 2 else { return }

        let gridButtons: [CPGridButton] = Self.quickHazardOptions.map { option in
            let icon = KartaManeuverGlyphRenderer.hazardGridIcon(
                sfSymbol: option.sfSymbol,
                accent: option.accent,
                theme: activeTheme
            )
            return CPGridButton(titleVariants: [option.title], image: icon) { [weak self] _ in
                guard let self = self else { return }
                self.hazardGridAutoDismissWorkItem?.cancel()
                self.stateStore.emitQuickReportHazard(
                    categoryWire: option.categoryWire,
                    severityWire: option.severityWire,
                    oppositeSide: false
                )
                self.interfaceController?.popToRootTemplate(animated: true, completion: nil)
            }
        }

        let gridTemplate = CPGridTemplate(title: "Report Hazard", gridButtons: gridButtons)
        ic.pushTemplate(gridTemplate, animated: true, completion: nil)

        hazardGridAutoDismissWorkItem?.cancel()
        let dismissTask = DispatchWorkItem { [weak self] in
            self?.interfaceController?.popToRootTemplate(animated: true, completion: nil)
        }
        hazardGridAutoDismissWorkItem = dismissTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: dismissTask)
    }

    private func triggerHandsFreeVoice() {
        let country = stateStore.latestFrame.countryCode.uppercased()
        let locale = (country == "SG") ? "en-SG" : "en-MY"
        voiceBridge.triggerHandsFreeHazardCapture(localeTag: locale)
    }

    // MARK: - Deduplicated Non-Blocking Alerts

    private func presentHazardAlertIfNeeded(
        frame: KartaCarPlayNavigationFrame,
        on mapTemplate: CPMapTemplate
    ) {
        guard let hazardId = frame.approachingHazardId,
              let label = frame.approachingHazardLabel,
              let dist = frame.approachingHazardDistanceMeters,
              dist <= 1200.0,
              shouldPresentAlert(key: "haz:\(hazardId)", cooldownSeconds: 45.0) else {
            return
        }

        let alert = CPNavigationAlert(
            titleVariants: ["\(label) in \(formatCompactMeters(dist))", "\(label) ahead"],
            subtitleVariants: ["Crowdsourced Karta Alert"],
            image: nil,
            primaryAction: CPAlertAction(title: "Still There", style: .default) { [weak self] _ in
                self?.stateStore.emitHazardVote(hazardId: hazardId, vote: "confirm")
            },
            secondaryAction: CPAlertAction(title: "Cleared", style: .cancel) { [weak self] _ in
                self?.stateStore.emitHazardVote(hazardId: hazardId, vote: "cleared")
            },
            duration: 8.0
        )
        mapTemplate.present(navigationAlert: alert, animated: true)
    }

    private func presentRerouteAlertIfNeeded(
        frame: KartaCarPlayNavigationFrame,
        on mapTemplate: CPMapTemplate
    ) {
        guard let proposalId = frame.rerouteProposalId,
              let banner = frame.rerouteBannerText,
              shouldPresentAlert(key: "reroute:\(proposalId)", cooldownSeconds: 60.0) else {
            return
        }

        let subtitle = frame.rerouteTollDeltaText ?? "Faster Valhalla corridor"
        let alert = CPNavigationAlert(
            titleVariants: [banner, "Faster route available"],
            subtitleVariants: [subtitle],
            image: nil,
            primaryAction: CPAlertAction(title: "Switch", style: .default) { [weak self] _ in
                self?.stateStore.emitRerouteDecision(proposalId: proposalId, accepted: true)
            },
            secondaryAction: CPAlertAction(title: "Keep", style: .cancel) { [weak self] _ in
                self?.stateStore.emitRerouteDecision(proposalId: proposalId, accepted: false)
            },
            duration: 10.0
        )
        mapTemplate.present(navigationAlert: alert, animated: true)
    }

    private func shouldPresentAlert(key: String, cooldownSeconds: TimeInterval) -> Bool {
        let now = Date()
        if let prev = presentedAlertTimestamps[key], now.timeIntervalSince(prev) < cooldownSeconds {
            return false
        }
        presentedAlertTimestamps[key] = now
        return true
    }

    private func formatCompactMeters(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000.0)
        }
        return "\(Int((meters / 10.0).rounded() * 10)) m"
    }

    // MARK: - CPMapTemplateDelegate

    public func mapTemplate(_ mapTemplate: CPMapTemplate, panWith direction: CPMapTemplate.PanDirection) {
        if !isMapPanned {
            isMapPanned = true
            refreshStreamlinedControls(isNavigating: stateStore.latestFrame.isNavigating)
        }
        mapViewController?.pan(direction: direction)
    }

    public func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {
        isMapPanned = false
        isRouteOverviewActive = false
        mapViewController?.recenterOnVehicle()
        refreshStreamlinedControls(isNavigating: stateStore.latestFrame.isNavigating)
    }
}
#endif
