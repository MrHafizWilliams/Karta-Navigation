#if canImport(UIKit)
import Foundation
import UIKit

/// Monitors iOS thermal state (`ProcessInfo.thermalState`), Low Power Mode, and
/// battery charging status during extended CarPlay navigation sessions.
///
/// Feeds live telemetry to Dart's `ThermalAdaptationController` and applies an
/// immediate local fail-safe cap if `.critical` thermal pressure occurs while
/// the Flutter isolate is suspended or backgrounded.
public final class KartaCarPlayThermalMonitor {
    private let stateStore: KartaCarPlayStateStore
    private var isMonitoring = false

    public init(stateStore: KartaCarPlayStateStore = .shared) {
        self.stateStore = stateStore
    }

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        UIDevice.current.isBatteryMonitoringEnabled = true

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleThermalOrPowerChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleThermalOrPowerChange),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleThermalOrPowerChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleThermalOrPowerChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )

        publishCurrentSnapshot()
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        stopMonitoring()
    }

    @objc private func handleThermalOrPowerChange() {
        publishCurrentSnapshot()
    }

    public func publishCurrentSnapshot() {
        let thermalState = ProcessInfo.processInfo.thermalState
        let wireLevel = Self.wireThermalLevel(for: thermalState)
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let rawBattery = UIDevice.current.batteryLevel
        let batteryPct: Int? = rawBattery >= 0 ? Int((rawBattery * 100.0).rounded()) : nil
        let isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

        // Immediate local fail-safe protection if OS reaches critical thermal pressure.
        if thermalState == .critical {
            stateStore.updateThermalProfile(.criticalFailsafe)
        }

        stateStore.emitThermalState(
            thermalLevel: wireLevel,
            batteryLevelPercent: batteryPct,
            isCharging: isCharging,
            isLowPowerMode: lowPower
        )
    }

    private static func wireThermalLevel(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "fair"
        }
    }
}
#endif
