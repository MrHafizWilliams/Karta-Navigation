import Foundation

#if canImport(Flutter)
import Flutter

/// Decoupled Flutter plugin adapter wiring `com.karta.navigation/automotive_bridge`
/// to `KartaCarPlayStateStore` so `AppDelegate` and `KartaCarPlaySceneDelegate`
/// stay completely independent of Flutter UI widgets.
public final class KartaCarPlayFlutterPlugin: NSObject, FlutterPlugin, KartaCarPlayBridgeOutboundSink {
    private let channel: FlutterMethodChannel
    private let stateStore: KartaCarPlayStateStore

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.karta.navigation/automotive_bridge",
            binaryMessenger: registrar.messenger()
        )
        let instance = KartaCarPlayFlutterPlugin(channel: channel, stateStore: .shared)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public init(channel: FlutterMethodChannel, stateStore: KartaCarPlayStateStore = .shared) {
        self.channel = channel
        self.stateStore = stateStore
        super.init()
        stateStore.outboundSink = self
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let payload = (call.arguments as? [String: Any]) ?? [:]
        switch call.method {
        case "syncFullState":
            stateStore.applyFullStateEnvelope(payload)
            result(nil)

        case "publishNavigationFrame":
            stateStore.updateNavigationFrame(KartaCarPlayNavigationFrame.from(payload))
            result(nil)

        case "updateRouteGeometry":
            stateStore.updateRouteGeometry(KartaCarPlayRouteGeometry.from(payload))
            result(nil)

        case "updateHazards":
            let raw = (payload["hazards"] as? [[String: Any]]) ?? []
            stateStore.updateHazards(raw.map(KartaCarPlayHazardPin.from))
            result(nil)

        case "applyThermalRenderProfile":
            stateStore.updateThermalProfile(KartaCarPlayThermalProfile.from(payload))
            result(nil)

        case "updateOfflineMapConfig":
            stateStore.updateOfflineConfig(KartaCarPlayOfflineMapConfig.from(payload))
            result(nil)

        case "setVehicleAppearance":
            if let isDark = payload["isDarkMode"] as? Bool {
                stateStore.updateAppearance(isDarkMode: isDark)
            }
            result(nil)

        case "endAutomotiveSession":
            stateStore.scrubEphemeralLocationState()
            result(nil)

        case "scrubEphemeralLocationState":
            stateStore.scrubEphemeralLocationState()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func sendToDart(method: String, arguments: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod(method, arguments: arguments)
        }
    }
}
#endif
