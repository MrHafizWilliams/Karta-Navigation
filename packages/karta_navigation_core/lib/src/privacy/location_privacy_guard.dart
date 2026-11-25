import 'dart:async';
import 'dart:math' as math;
import 'package:karta_api_client/karta_api_client.dart';
import 'package:meta/meta.dart';
import '../gps/position_source.dart';

/// Enforces Karta's strict on-device location privacy policy:
/// - **Zero raw GPS history retention** unless the user explicitly opts in.
/// - Volatile single-fix live RAM register scrubbed immediately on trip end
///   or vehicle head-unit disconnect.
/// - No hardware/device identifiers attached to routing or crowdsource sessions.
@immutable
class LocationPrivacyPolicy {
  const LocationPrivacyPolicy({
    this.retainTripHistoryOptIn = false,
    this.allowAnalyticsTelemetry = false,
    this.stripDeviceIdentifiers = true,
    this.scrubOnSessionEnd = true,
    this.scrubOnHeadUnitDisconnect = true,
    this.coarseGridMeters = 500.0,
    this.maxOptInHistorySamples = 1200,
  });

  /// Canonical strict-default policy enforced out of the box on all platforms.
  const LocationPrivacyPolicy.strictDefault()
      : retainTripHistoryOptIn = false,
        allowAnalyticsTelemetry = false,
        stripDeviceIdentifiers = true,
        scrubOnSessionEnd = true,
        scrubOnHeadUnitDisconnect = true,
        coarseGridMeters = 500.0,
        maxOptInHistorySamples = 1200;

  /// Explicit user opt-in required before any raw GPS breadcrumb is retained in RAM.
  final bool retainTripHistoryOptIn;

  /// Never upload diagnostic/MapLibre telemetry unless explicitly enabled.
  final bool allowAnalyticsTelemetry;

  /// Guarantees ephemeral per-trip session tokens instead of device/advertising IDs.
  final bool stripDeviceIdentifiers;

  /// Scrubs live volatile coordinates from RAM as soon as active navigation stops.
  final bool scrubOnSessionEnd;

  /// Scrubs volatile coordinates across phone + head unit when USB/wireless projection ends.
  final bool scrubOnHeadUnitDisconnect;

  /// Spatial quantization radius applied to non-navigation coarse queries (fuel / carpool).
  final double coarseGridMeters;

  /// Bounded ring-buffer cap if and only if [retainTripHistoryOptIn] is explicitly enabled.
  final int maxOptInHistorySamples;

  LocationPrivacyPolicy copyWith({
    bool? retainTripHistoryOptIn,
    bool? allowAnalyticsTelemetry,
    bool? stripDeviceIdentifiers,
    bool? scrubOnSessionEnd,
    bool? scrubOnHeadUnitDisconnect,
    double? coarseGridMeters,
    int? maxOptInHistorySamples,
  }) =>
      LocationPrivacyPolicy(
        retainTripHistoryOptIn: retainTripHistoryOptIn ?? this.retainTripHistoryOptIn,
        allowAnalyticsTelemetry: allowAnalyticsTelemetry ?? this.allowAnalyticsTelemetry,
        stripDeviceIdentifiers: stripDeviceIdentifiers ?? this.stripDeviceIdentifiers,
        scrubOnSessionEnd: scrubOnSessionEnd ?? this.scrubOnSessionEnd,
        scrubOnHeadUnitDisconnect: scrubOnHeadUnitDisconnect ?? this.scrubOnHeadUnitDisconnect,
        coarseGridMeters: coarseGridMeters ?? this.coarseGridMeters,
        maxOptInHistorySamples: maxOptInHistorySamples ?? this.maxOptInHistorySamples,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'retainTripHistoryOptIn': retainTripHistoryOptIn,
        'allowAnalyticsTelemetry': allowAnalyticsTelemetry,
        'stripDeviceIdentifiers': stripDeviceIdentifiers,
        'scrubOnSessionEnd': scrubOnSessionEnd,
        'scrubOnHeadUnitDisconnect': scrubOnHeadUnitDisconnect,
        'coarseGridMeters': coarseGridMeters,
      };
}

/// Auditable privacy telemetry snapshot rendered in Karta Driver Studio and
/// verified in automated tests. Never contains raw coordinates.
@immutable
class PrivacyAuditSnapshot {
  const PrivacyAuditSnapshot({
    required this.policy,
    required this.retainedHistoryCount,
    required this.hasLiveVolatileFix,
    required this.scrubCount,
    required this.ephemeralSessionToken,
    required this.mapLibreTelemetryDisabled,
    this.lastScrubbedAt,
  });

  final LocationPrivacyPolicy policy;
  final int retainedHistoryCount;
  final bool hasLiveVolatileFix;
  final int scrubCount;
  final String ephemeralSessionToken;
  final bool mapLibreTelemetryDisabled;
  final DateTime? lastScrubbedAt;
}

/// Headless on-device privacy guard mediating every GPS fix before it enters
/// UI, automotive projection, or outbound backend telemetry.
class LocationPrivacyGuard {
  LocationPrivacyGuard({
    LocationPrivacyPolicy policy = const LocationPrivacyPolicy.strictDefault(),
    DateTime Function()? clock,
  })  : _policy = policy,
        _clock = clock ?? DateTime.now {
    _ephemeralSessionToken = _generateEphemeralToken();
  }

  final DateTime Function() _clock;
  final math.Random _rng = math.Random();
  final StreamController<PrivacyAuditSnapshot> _auditController =
      StreamController<PrivacyAuditSnapshot>.broadcast();

  LocationPrivacyPolicy _policy;
  GpsFix? _liveVolatileFix;
  final List<GpsFix> _optInHistory = <GpsFix>[];
  int _scrubCount = 0;
  DateTime? _lastScrubbedAt;
  late String _ephemeralSessionToken;

  LocationPrivacyPolicy get policy => _policy;
  GpsFix? get liveVolatileFix => _liveVolatileFix;
  String get ephemeralSessionToken => _ephemeralSessionToken;
  int get scrubCount => _scrubCount;
  DateTime? get lastScrubbedAt => _lastScrubbedAt;

  /// Strictly empty unless [LocationPrivacyPolicy.retainTripHistoryOptIn] is true.
  List<GpsFix> get retainedHistory =>
      _policy.retainTripHistoryOptIn ? List<GpsFix>.unmodifiable(_optInHistory) : const <GpsFix>[];

  Stream<PrivacyAuditSnapshot> get auditStream => _auditController.stream;

  PrivacyAuditSnapshot get auditSnapshot => PrivacyAuditSnapshot(
        policy: _policy,
        retainedHistoryCount: _policy.retainTripHistoryOptIn ? _optInHistory.length : 0,
        hasLiveVolatileFix: _liveVolatileFix != null,
        scrubCount: _scrubCount,
        ephemeralSessionToken: _ephemeralSessionToken,
        mapLibreTelemetryDisabled: !_policy.allowAnalyticsTelemetry,
        lastScrubbedAt: _lastScrubbedAt,
      );

  /// Updates the active policy. Disabling [retainTripHistoryOptIn] immediately
  /// purges any previously buffered breadcrumbs from RAM.
  void updatePolicy(LocationPrivacyPolicy next) {
    final wasOptedIn = _policy.retainTripHistoryOptIn;
    _policy = next;
    if (wasOptedIn && !next.retainTripHistoryOptIn) {
      _optInHistory.clear();
    } else if (_optInHistory.length > next.maxOptInHistorySamples) {
      _optInHistory.removeRange(0, _optInHistory.length - next.maxOptInHistorySamples);
    }
    _emitAudit();
  }

  /// Convenience toggle for the explicit user opt-in switch in Driver Studio.
  void setTripHistoryOptIn(bool enabled) {
    updatePolicy(_policy.copyWith(retainTripHistoryOptIn: enabled));
  }

  /// Processes a live GPS fix through the privacy boundary:
  /// - Always overwrites the single volatile live slot (zero history accumulation).
  /// - Appends to [_optInHistory] ONLY when [retainTripHistoryOptIn] is explicitly true.
  GpsFix processLiveFix(GpsFix fix) {
    _liveVolatileFix = fix;
    if (_policy.retainTripHistoryOptIn) {
      _optInHistory.add(fix);
      if (_optInHistory.length > _policy.maxOptInHistorySamples) {
        _optInHistory.removeAt(0);
      }
    } else if (_optInHistory.isNotEmpty) {
      _optInHistory.clear();
    }
    return fix;
  }

  /// Scrubs all ephemeral in-memory GPS state and rotates the anonymous session token.
  /// Called automatically on trip end, head-unit disconnect, and disposal.
  void scrubEphemeralState({bool purgeOptInHistory = false}) {
    _liveVolatileFix = null;
    if (purgeOptInHistory || !_policy.retainTripHistoryOptIn) {
      _optInHistory.clear();
    }
    _scrubCount += 1;
    _lastScrubbedAt = _clock();
    if (_policy.stripDeviceIdentifiers) {
      _ephemeralSessionToken = _generateEphemeralToken();
    }
    _emitAudit();
  }

  /// Explicit user action to erase all retained breadcrumbs immediately.
  void purgeAllRetainedHistory() {
    _optInHistory.clear();
    _scrubCount += 1;
    _lastScrubbedAt = _clock();
    _emitAudit();
  }

  /// Quantizes a coordinate to Karta's coarse privacy grid (~500m default) for
  /// non-navigation queries (community fuel discovery, privacy-shielded carpool matching)
  /// so exact home/work addresses are never exposed.
  Coordinate sanitizeForCoarseQuery(Coordinate raw) {
    final stepDeg = (_policy.coarseGridMeters / 111320.0).clamp(0.001, 0.05);
    final qLat = (raw.lat / stepDeg).round() * stepDeg;
    final cosLat = math.cos(raw.lat * math.pi / 180.0).abs().clamp(0.2, 1.0);
    final lonStep = stepDeg / cosLat;
    final qLon = (raw.lon / lonStep).round() * lonStep;
    return Coordinate(
      lat: double.parse(qLat.toStringAsFixed(5)),
      lon: double.parse(qLon.toStringAsFixed(5)),
    );
  }

  /// Redacts sensitive GPS coordinates from diagnostic logs.
  String redactDiagnosticMessage(String input) {
    return input.replaceAll(
      RegExp(r'-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}'),
      '<redacted-coord>',
    );
  }

  String _generateEphemeralToken() {
    final ts = _clock().millisecondsSinceEpoch.toRadixString(36);
    final salt = _rng.nextInt(0xFFFFFF).toRadixString(36).padLeft(5, '0');
    return 'karta-eph-$ts-$salt';
  }

  void _emitAudit() {
    if (!_auditController.isClosed) {
      _auditController.add(auditSnapshot);
    }
  }

  void dispose() {
    scrubEphemeralState(purgeOptInHistory: true);
    _auditController.close();
  }
}
