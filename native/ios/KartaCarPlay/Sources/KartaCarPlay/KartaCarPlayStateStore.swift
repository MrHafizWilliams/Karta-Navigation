import Foundation

/// Outbound callback sink sending Apple CarPlay head-unit events back to Dart's
/// `KartaAutomotiveBridge` (`com.karta.navigation/automotive_bridge`).
public protocol KartaCarPlayBridgeOutboundSink: AnyObject {
    func sendToDart(method: String, arguments: [String: Any])
}

/// Observer interface implemented by `KartaCarPlaySceneDelegate` and
/// `KartaCarPlayMapViewController` to receive reactive updates without coupling to Flutter.
public protocol KartaCarPlayStateObserver: AnyObject {
    func stateStore(_ store: KartaCarPlayStateStore, didUpdateFrame frame: KartaCarPlayNavigationFrame)
    func stateStore(_ store: KartaCarPlayStateStore, didUpdateRoute route: KartaCarPlayRouteGeometry?)
    func stateStore(_ store: KartaCarPlayStateStore, didUpdateHazards hazards: [KartaCarPlayHazardPin])
    func stateStore(_ store: KartaCarPlayStateStore, didUpdateThermalProfile profile: KartaCarPlayThermalProfile)
    func stateStore(_ store: KartaCarPlayStateStore, didUpdateOfflineConfig config: KartaCarPlayOfflineMapConfig)
    func stateStore(_ store: KartaCarPlayStateStore, didUpdateAppearance isDarkMode: Bool)
    func stateStoreDidScrubEphemeralLocation(_ store: KartaCarPlayStateStore)
}

/// Volatile, RAM-only automotive state store shared between `KartaCarPlayFlutterPlugin`
/// and `KartaCarPlaySceneDelegate`.
///
/// Privacy invariant:
/// - **Zero disk persistence**: coordinates are never written to `UserDefaults`,
///   files, caches, or `os_log`.
/// - Stores only the single active navigation frame and scrubs all coordinates
///   immediately on `scrubEphemeralLocationState()` or vehicle disconnect.
public final class KartaCarPlayStateStore {
    public static let shared = KartaCarPlayStateStore()

    private let lock = NSLock()
    private var _latestFrame: KartaCarPlayNavigationFrame = .idle
    private var _activeRoute: KartaCarPlayRouteGeometry?
    private var _hazards: [KartaCarPlayHazardPin] = []
    private var _thermalProfile: KartaCarPlayThermalProfile = .nominal
    private var _offlineConfig: KartaCarPlayOfflineMapConfig = .defaultConfig
    private var _isDarkMode: Bool = true
    private var _lastSequenceId: Int = 0
    private var _observers = NSHashTable<AnyObject>.weakObjects()

    public weak var outboundSink: KartaCarPlayBridgeOutboundSink?

    private init() {}

    public var isDarkMode: Bool {
        lock.withLock { _isDarkMode }
    }

    public var latestFrame: KartaCarPlayNavigationFrame {
        lock.withLock { _latestFrame }
    }

    public var activeRoute: KartaCarPlayRouteGeometry? {
        lock.withLock { _activeRoute }
    }

    public var hazards: [KartaCarPlayHazardPin] {
        lock.withLock { _hazards }
    }

    public var thermalProfile: KartaCarPlayThermalProfile {
        lock.withLock { _thermalProfile }
    }

    public var offlineConfig: KartaCarPlayOfflineMapConfig {
        lock.withLock { _offlineConfig }
    }

    public var lastSequenceId: Int {
        lock.withLock { _lastSequenceId }
    }

    public func addObserver(_ observer: KartaCarPlayStateObserver) {
        lock.withLock { _observers.add(observer) }
    }

    public func removeObserver(_ observer: KartaCarPlayStateObserver) {
        lock.withLock { _observers.remove(observer) }
    }

    /// Atomic Phone -> Car full-state hydration on connect / reconnect.
    public func applyFullStateEnvelope(_ payload: [String: Any]) {
        let seq = (payload["sequenceId"] as? NSNumber)?.intValue ?? 0
        if let offlineDict = payload["offlineConfig"] as? [String: Any] {
            updateOfflineConfig(KartaCarPlayOfflineMapConfig.from(offlineDict))
        }
        if let dark = payload["isDarkMode"] as? Bool {
            updateAppearance(isDarkMode: dark)
        }
        if let thermalDict = payload["thermalProfile"] as? [String: Any] {
            updateThermalProfile(KartaCarPlayThermalProfile.from(thermalDict))
        }
        if let routeDict = payload["routeGeometry"] as? [String: Any] {
            updateRouteGeometry(KartaCarPlayRouteGeometry.from(routeDict))
        } else {
            updateRouteGeometry(nil)
        }
        if let hazardDicts = payload["hazards"] as? [[String: Any]] {
            updateHazards(hazardDicts.map(KartaCarPlayHazardPin.from))
        }
        if let frameDict = payload["frame"] as? [String: Any] {
            let frame = KartaCarPlayNavigationFrame.from(frameDict)
            lock.withLock { _lastSequenceId = max(_lastSequenceId, max(seq, frame.sequenceId)) }
            updateNavigationFrame(frame, bypassSequenceCheck: true)
        }
    }

    public func updateNavigationFrame(
        _ frame: KartaCarPlayNavigationFrame,
        bypassSequenceCheck: Bool = false
    ) {
        let shouldApply: Bool = lock.withLock {
            if !bypassSequenceCheck && frame.sequenceId > 0 && frame.sequenceId < _lastSequenceId {
                return false
            }
            if frame.sequenceId > 0 {
                _lastSequenceId = frame.sequenceId
            }
            _latestFrame = frame
            return true
        }
        guard shouldApply else { return }
        notifyObservers { $0.stateStore(self, didUpdateFrame: frame) }
    }

    public func updateRouteGeometry(_ route: KartaCarPlayRouteGeometry?) {
        lock.withLock { _activeRoute = route }
        notifyObservers { $0.stateStore(self, didUpdateRoute: route) }
    }

    public func updateHazards(_ hazards: [KartaCarPlayHazardPin]) {
        lock.withLock { _hazards = hazards }
        notifyObservers { $0.stateStore(self, didUpdateHazards: hazards) }
    }

    public func updateThermalProfile(_ profile: KartaCarPlayThermalProfile) {
        lock.withLock { _thermalProfile = profile }
        notifyObservers { $0.stateStore(self, didUpdateThermalProfile: profile) }
    }

    public func updateOfflineConfig(_ config: KartaCarPlayOfflineMapConfig) {
        lock.withLock { _offlineConfig = config }
        notifyObservers { $0.stateStore(self, didUpdateOfflineConfig: config) }
    }

    public func updateAppearance(isDarkMode: Bool) {
        let changed: Bool = lock.withLock {
            if _isDarkMode == isDarkMode { return false }
            _isDarkMode = isDarkMode
            return true
        }
        guard changed else { return }
        notifyObservers { $0.stateStore(self, didUpdateAppearance: isDarkMode) }
    }

    /// Immediately zeroes all live GPS coordinates and transient route state from RAM.
    public func scrubEphemeralLocationState() {
        lock.withLock {
            _latestFrame = .idle
            _activeRoute = nil
            _hazards = []
        }
        notifyObservers { $0.stateStoreDidScrubEphemeralLocation(self) }
    }

    // MARK: - Outbound CarPlay -> Dart Event Helpers

    public func emitHeadUnitConnected(
        screenWidthPx: Int,
        screenHeightPx: Int,
        densityScale: Double,
        supportsInstrumentCluster: Bool,
        isDarkMode: Bool = true
    ) {
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        outboundSink?.sendToDart(
            method: "onHeadUnitConnected",
            arguments: [
                "platform": "carplay",
                "screenWidthPx": screenWidthPx,
                "screenHeightPx": screenHeightPx,
                "densityScale": densityScale,
                "apiLevel": majorVersion,
                "supportsInstrumentCluster": supportsInstrumentCluster,
                "supportsOfflineSurface": true,
                "supportsVoiceInput": true,
                "isDarkMode": isDarkMode
            ]
        )
    }

    public func emitHeadUnitAppearanceChanged(
        isDarkMode: Bool,
        source: String = "vehicle_headlight_sensor"
    ) {
        updateAppearance(isDarkMode: isDarkMode)
        outboundSink?.sendToDart(
            method: "onHeadUnitAppearanceChanged",
            arguments: [
                "platform": "carplay",
                "isDarkMode": isDarkMode,
                "source": source
            ]
        )
    }

    public func emitHeadUnitDisconnected(reason: String) {
        let seq = lastSequenceId
        outboundSink?.sendToDart(
            method: "onHeadUnitDisconnected",
            arguments: [
                "platform": "carplay",
                "reason": reason,
                "lastSequenceId": seq
            ]
        )
    }

    public func emitQuickReportHazard(
        categoryWire: String,
        severityWire: String = "medium",
        oppositeSide: Bool = false
    ) {
        outboundSink?.sendToDart(
            method: "onQuickReportHazard",
            arguments: [
                "category": categoryWire,
                "severity": severityWire,
                "oppositeSide": oppositeSide,
                "source": "carplay"
            ]
        )
    }

    public func emitHazardVote(hazardId: String, vote: String) {
        outboundSink?.sendToDart(
            method: "onHazardVote",
            arguments: [
                "hazardId": hazardId,
                "vote": vote
            ]
        )
    }

    public func emitVoiceReportTriggered(localeTag: String = "en-MY") {
        outboundSink?.sendToDart(
            method: "onVoiceReportTriggered",
            arguments: ["localeTag": localeTag]
        )
    }

    public func emitVoiceTranscript(_ transcript: String, localeTag: String = "en-MY") {
        outboundSink?.sendToDart(
            method: "onVoiceTranscriptCaptured",
            arguments: [
                "transcript": transcript,
                "localeTag": localeTag
            ]
        )
    }

    public func emitRerouteDecision(proposalId: String, accepted: Bool) {
        outboundSink?.sendToDart(
            method: "onRerouteDecision",
            arguments: [
                "proposalId": proposalId,
                "accepted": accepted
            ]
        )
    }

    public func emitNavigationControlAction(_ action: String) {
        outboundSink?.sendToDart(
            method: "onNavigationControlAction",
            arguments: ["action": action]
        )
    }

    public func emitThermalState(
        thermalLevel: String,
        batteryLevelPercent: Int?,
        isCharging: Bool,
        isLowPowerMode: Bool
    ) {
        var args: [String: Any] = [
            "platform": "carplay",
            "thermalLevel": thermalLevel,
            "isCharging": isCharging,
            "isLowPowerMode": isLowPowerMode
        ]
        if let battery = batteryLevelPercent {
            args["batteryLevelPercent"] = battery
        }
        outboundSink?.sendToDart(method: "onThermalStateChanged", arguments: args)
    }

    private func notifyObservers(_ block: @escaping (KartaCarPlayStateObserver) -> Void) {
        let snapshot: [KartaCarPlayStateObserver] = lock.withLock {
            _observers.allObjects.compactMap { $0 as? KartaCarPlayStateObserver }
        }
        if Thread.isMainThread {
            snapshot.forEach(block)
        } else {
            DispatchQueue.main.async {
                snapshot.forEach(block)
            }
        }
    }
}
