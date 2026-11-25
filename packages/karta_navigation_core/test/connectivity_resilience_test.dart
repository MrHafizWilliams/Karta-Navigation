import 'package:flutter_test/flutter_test.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

void main() {
  test('ConnectivityResilienceController applies tunnel hysteresis and quietly auto-syncs on recovery', () async {
    var signalBack = false;
    var flushedReports = 0;
    var reconnectHookCalls = 0;

    final ctrl = ConnectivityResilienceController(
      probeOnline: () async => signalBack,
      failureThreshold: 2,
      baseRetryDelay: const Duration(milliseconds: 25),
      maxRetryDelay: const Duration(milliseconds: 60),
      syncGraceDisplayDuration: Duration.zero,
    );
    addTearDown(ctrl.dispose);

    ctrl.registerReconnectHook(() async {
      reconnectHookCalls += 1;
    });

    final modesSeen = <NetworkTransitionState>[];
    final sub = ctrl.stream.listen((snap) => modesSeen.add(snap.mode));
    addTearDown(sub.cancel);

    // 1. Single brief blip under a flyover -> stays calmly online (anti-flap hysteresis)
    ctrl.recordNetworkFailure();
    expect(ctrl.current.mode, NetworkTransitionState.online);
    expect(ctrl.current.consecutiveFailures, 1);

    // 2. Second consecutive failure (entered SMART Tunnel / rural dead zone) -> Offline Routing Active
    ctrl.recordNetworkFailure();
    expect(ctrl.current.mode, NetworkTransitionState.offlineRoutingActive);
    expect(ctrl.current.offlineSince, isNotNull);

    // 3. Driver submits a hazard report while offline -> queued silently without error
    ctrl.enqueueOfflineSyncAction(() async {
      flushedReports += 1;
    });
    expect(ctrl.current.pendingSyncCount, 1);

    // 4. Signal returns -> background prober quietly syncs queued actions & returns to online
    signalBack = true;
    await ctrl.triggerRecoveryCheckNow();
    await Future<void>.delayed(Duration.zero);

    expect(flushedReports, 1);
    expect(reconnectHookCalls, 1);
    expect(ctrl.current.mode, NetworkTransitionState.online);
    expect(ctrl.current.pendingSyncCount, 0);
    expect(ctrl.current.offlineSince, isNull);
    expect(modesSeen, contains(NetworkTransitionState.offlineRoutingActive));
    expect(modesSeen, contains(NetworkTransitionState.syncingQuietly));
    expect(modesSeen.last, NetworkTransitionState.online);
  });

  test('ConnectivityResilienceController auto-recovers via background backoff probe and honors manual offline override', () async {
    var signalBack = false;
    final ctrl = ConnectivityResilienceController(
      probeOnline: () async => signalBack,
      failureThreshold: 2,
      baseRetryDelay: const Duration(milliseconds: 20),
      maxRetryDelay: const Duration(milliseconds: 40),
      syncGraceDisplayDuration: Duration.zero,
    );
    addTearDown(ctrl.dispose);

    ctrl.recordNetworkFailure();
    ctrl.recordNetworkFailure();
    expect(ctrl.current.mode, NetworkTransitionState.offlineRoutingActive);

    // Signal returns automatically after exiting tunnel
    signalBack = true;
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(ctrl.current.mode, NetworkTransitionState.online);

    // Explicit manual offline toggle stays offline even while network is healthy
    await ctrl.setManualOfflineOverride(true);
    expect(ctrl.current.mode, NetworkTransitionState.offlineRoutingActive);
    expect(ctrl.current.manualOfflineOverride, isTrue);

    // Turning off manual override quietly probes and returns online
    await ctrl.setManualOfflineOverride(false);
    expect(ctrl.current.mode, NetworkTransitionState.online);
  });
}
