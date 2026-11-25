import 'dart:async';
import 'dart:math' as math;
import 'package:meta/meta.dart';

enum NetworkTransitionState {
  online,
  offlineRoutingActive,
  syncingQuietly,
}

@immutable
class ConnectivitySnapshot {
  const ConnectivitySnapshot({
    this.mode = NetworkTransitionState.online,
    this.offlineSince,
    this.lastSyncedAt,
    this.pendingSyncCount = 0,
    this.activeOfflineRegion,
    this.consecutiveFailures = 0,
    this.manualOfflineOverride = false,
  });

  final NetworkTransitionState mode;
  final DateTime? offlineSince;
  final DateTime? lastSyncedAt;
  final int pendingSyncCount;
  final String? activeOfflineRegion;
  final int consecutiveFailures;
  final bool manualOfflineOverride;

  bool get isOffline => mode == NetworkTransitionState.offlineRoutingActive;
  bool get isSyncing => mode == NetworkTransitionState.syncingQuietly;
  bool get isOnline => mode == NetworkTransitionState.online;

  ConnectivitySnapshot copyWith({
    NetworkTransitionState? mode,
    DateTime? offlineSince,
    bool clearOfflineSince = false,
    DateTime? lastSyncedAt,
    int? pendingSyncCount,
    String? activeOfflineRegion,
    int? consecutiveFailures,
    bool? manualOfflineOverride,
  }) =>
      ConnectivitySnapshot(
        mode: mode ?? this.mode,
        offlineSince: clearOfflineSince ? null : (offlineSince ?? this.offlineSince),
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
        activeOfflineRegion: activeOfflineRegion ?? this.activeOfflineRegion,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        manualOfflineOverride: manualOfflineOverride ?? this.manualOfflineOverride,
      );
}

typedef ConnectivityProbeFn = Future<bool> Function();
typedef QuietSyncActionFn = Future<void> Function();

/// Headless online/offline state transition controller built for tunnels
/// (SMART Tunnel, CTE Tunnel) and rural Malaysian/Borneo dead zones.
///
/// - Applies anti-flap hysteresis ([failureThreshold] consecutive failures before
///   entering [NetworkTransitionState.offlineRoutingActive]) so transient 4G
///   handoffs never flash error UI.
/// - Eliminates jarring "No Internet" alerts in favor of a subtle non-intrusive
///   status stream.
/// - Quietly probes signal recovery with capped exponential backoff and flushes
///   queued offline actions (hazards, votes, live telemetry) automatically once
///   connectivity returns.
class ConnectivityResilienceController {
  ConnectivityResilienceController({
    required ConnectivityProbeFn probeOnline,
    this.failureThreshold = 2,
    this.baseRetryDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(seconds: 15),
    this.syncGraceDisplayDuration = const Duration(milliseconds: 1200),
  }) : _probeOnline = probeOnline;

  final ConnectivityProbeFn _probeOnline;
  final int failureThreshold;
  final Duration baseRetryDelay;
  final Duration maxRetryDelay;
  final Duration syncGraceDisplayDuration;

  final StreamController<ConnectivitySnapshot> _controller =
      StreamController<ConnectivitySnapshot>.broadcast();
  final List<QuietSyncActionFn> _pendingActions = <QuietSyncActionFn>[];
  final List<QuietSyncActionFn> _onReconnectHooks = <QuietSyncActionFn>[];

  ConnectivitySnapshot _snapshot = const ConnectivitySnapshot();
  Timer? _retryTimer;
  Timer? _syncFinishTimer;
  int _retryAttempt = 0;
  bool _syncInFlight = false;
  bool _disposed = false;

  Stream<ConnectivitySnapshot> get stream => _controller.stream;
  ConnectivitySnapshot get current => _snapshot;

  void registerReconnectHook(QuietSyncActionFn hook) {
    _onReconnectHooks.add(hook);
  }

  void setActiveOfflineRegion(String? regionName) {
    if (_snapshot.activeOfflineRegion == regionName) return;
    _emit(_snapshot.copyWith(activeOfflineRegion: regionName));
  }

  /// Toggles explicit user-requested offline mode (e.g., from Offline Map Manager).
  Future<void> setManualOfflineOverride(bool enabled) async {
    if (enabled) {
      _retryTimer?.cancel();
      _emit(
        _snapshot.copyWith(
          mode: NetworkTransitionState.offlineRoutingActive,
          manualOfflineOverride: true,
          offlineSince: _snapshot.offlineSince ?? DateTime.now(),
        ),
      );
    } else {
      _emit(_snapshot.copyWith(manualOfflineOverride: false));
      await triggerRecoveryCheckNow();
    }
  }

  /// Reports a successful live backend call (resets failure hysteresis & triggers
  /// quiet queue flush if recovering from a dead zone).
  void recordNetworkSuccess() {
    if (_disposed || _snapshot.manualOfflineOverride) return;
    _retryTimer?.cancel();
    _retryAttempt = 0;

    if (_snapshot.mode == NetworkTransitionState.offlineRoutingActive || _pendingActions.isNotEmpty) {
      unawaited(_runQuietSync());
    } else if (_snapshot.consecutiveFailures > 0) {
      _emit(_snapshot.copyWith(consecutiveFailures: 0, lastSyncedAt: DateTime.now()));
    }
  }

  /// Reports a transient network failure (e.g., tunnel drop or timeout).
  /// Transitions calmly into [NetworkTransitionState.offlineRoutingActive] once
  /// [failureThreshold] consecutive failures occur.
  void recordNetworkFailure() {
    if (_disposed) return;
    final nextFailures = _snapshot.consecutiveFailures + 1;
    if (_snapshot.mode == NetworkTransitionState.offlineRoutingActive) {
      _emit(_snapshot.copyWith(consecutiveFailures: nextFailures));
      _scheduleBackgroundProbe();
      return;
    }

    if (nextFailures >= failureThreshold) {
      _emit(
        _snapshot.copyWith(
          mode: NetworkTransitionState.offlineRoutingActive,
          consecutiveFailures: nextFailures,
          offlineSince: _snapshot.offlineSince ?? DateTime.now(),
        ),
      );
      _scheduleBackgroundProbe();
    } else {
      _emit(_snapshot.copyWith(consecutiveFailures: nextFailures));
    }
  }

  /// Queues a mutation (e.g., hazard report or community vote submitted while inside
  /// a tunnel) to be quietly flushed the moment signal returns.
  void enqueueOfflineSyncAction(QuietSyncActionFn action) {
    if (_disposed) return;
    _pendingActions.add(action);
    _emit(_snapshot.copyWith(pendingSyncCount: _pendingActions.length));
    if (_snapshot.isOnline && !_snapshot.manualOfflineOverride) {
      unawaited(_runQuietSync());
    } else if (!_snapshot.manualOfflineOverride) {
      _scheduleBackgroundProbe();
    }
  }

  /// Manually executes an immediate quiet recovery probe (useful on OS network-change events).
  Future<bool> triggerRecoveryCheckNow() async {
    if (_disposed || _snapshot.manualOfflineOverride) return false;
    final ok = await _probeOnline();
    if (_disposed) return false;
    if (ok) {
      _retryTimer?.cancel();
      _retryAttempt = 0;
      await _runQuietSync();
      return true;
    }
    recordNetworkFailure();
    return false;
  }

  void _scheduleBackgroundProbe() {
    if (_disposed || _snapshot.manualOfflineOverride) return;
    if (_retryTimer != null && _retryTimer!.isActive) return;

    final backoffFactor = math.pow(2, math.min(_retryAttempt, 4)).toInt();
    final delayMs = math.min(
      baseRetryDelay.inMilliseconds * backoffFactor,
      maxRetryDelay.inMilliseconds,
    );
    _retryAttempt += 1;

    _retryTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (_disposed || _snapshot.manualOfflineOverride) return;
      final recovered = await _probeOnline();
      if (_disposed) return;
      if (recovered) {
        _retryAttempt = 0;
        await _runQuietSync();
      } else {
        _scheduleBackgroundProbe();
      }
    });
  }

  Future<void> _runQuietSync() async {
    if (_syncInFlight || _disposed || _snapshot.manualOfflineOverride) return;
    _syncInFlight = true;
    _syncFinishTimer?.cancel();

    _emit(
      _snapshot.copyWith(
        mode: NetworkTransitionState.syncingQuietly,
        consecutiveFailures: 0,
      ),
    );

    try {
      // Flush queued actions in FIFO order; retain any that fail due to brief re-entry into tunnel
      final remaining = <QuietSyncActionFn>[];
      final batch = List<QuietSyncActionFn>.from(_pendingActions);
      _pendingActions.clear();

      for (final action in batch) {
        try {
          await action();
        } catch (_) {
          remaining.add(action);
        }
      }
      _pendingActions.addAll(remaining);

      for (final hook in List<QuietSyncActionFn>.from(_onReconnectHooks)) {
        try {
          await hook();
        } catch (_) {}
      }

      if (_disposed) return;

      if (_pendingActions.isEmpty) {
        _emit(
          _snapshot.copyWith(
            mode: NetworkTransitionState.syncingQuietly,
            pendingSyncCount: 0,
            lastSyncedAt: DateTime.now(),
          ),
        );
        // Smooth transition back to silent online state
        if (syncGraceDisplayDuration == Duration.zero) {
          _emit(
            _snapshot.copyWith(
              mode: NetworkTransitionState.online,
              clearOfflineSince: true,
              pendingSyncCount: 0,
              lastSyncedAt: DateTime.now(),
            ),
          );
        } else {
          _syncFinishTimer = Timer(syncGraceDisplayDuration, () {
            if (_disposed || _snapshot.manualOfflineOverride) return;
            if (_snapshot.mode == NetworkTransitionState.syncingQuietly) {
              _emit(
                _snapshot.copyWith(
                  mode: NetworkTransitionState.online,
                  clearOfflineSince: true,
                  pendingSyncCount: 0,
                  lastSyncedAt: DateTime.now(),
                ),
              );
            }
          });
        }
      } else {
        // Partial failure: return quietly to offline routing and retry later
        _emit(
          _snapshot.copyWith(
            mode: NetworkTransitionState.offlineRoutingActive,
            pendingSyncCount: _pendingActions.length,
          ),
        );
        _scheduleBackgroundProbe();
      }
    } finally {
      _syncInFlight = false;
    }
  }

  void _emit(ConnectivitySnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _syncFinishTimer?.cancel();
    _controller.close();
  }
}
