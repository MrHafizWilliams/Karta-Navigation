import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';
import 'package:meta/meta.dart';

/// Connected automotive projection target.
enum AutomotivePlatform {
  none('none', 'Phone Only'),
  carPlay('carplay', 'Apple CarPlay'),
  androidAuto('android_auto', 'Android Auto');

  const AutomotivePlatform(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static AutomotivePlatform fromWire(String? raw) {
    final norm = (raw ?? '').trim().toLowerCase();
    for (final p in AutomotivePlatform.values) {
      if (p.wireValue == norm) return p;
    }
    return AutomotivePlatform.none;
  }
}

/// Explicit Phone <-> Vehicle state handoff lifecycle.
enum AutomotiveHandoffPhase {
  phoneOnly,
  handingOffToCar,
  projectedActive,
  handingOffToPhone,
}

/// Vehicle head-unit aspect-ratio classification for camera & HUD scaling.
enum AutomotiveViewportClass {
  standard,  // < 1.65 (e.g. 800x480, 1024x600)
  wide,      // 1.65 .. 2.05 (e.g. 1280x720, 1920x1080)
  ultraWide, // >= 2.05 (e.g. 1920x720, 2400x720 panoramic dashes)
}

/// Structured lane-guidance item preserving OSM turn-lane tokens AND
/// recommendation highlight state for native `CPLaneGuidance` & Android `Lane`.
@immutable
class AutomotiveLaneItem {
  const AutomotiveLaneItem({
    required this.laneSpec,
    required this.isRecommended,
  });

  final String laneSpec;
  final bool isRecommended;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'laneSpec': laneSpec,
        'isRecommended': isRecommended,
      };

  factory AutomotiveLaneItem.fromMap(Map<String, dynamic> map) => AutomotiveLaneItem(
        laneSpec: (map['laneSpec'] as String?) ?? 'through',
        isRecommended: (map['isRecommended'] as bool?) ?? false,
      );
}

/// Strongly-typed automotive projection frame synchronized with Apple CarPlay
/// (`CPMapTemplate` / `CPNavigationSession` / `MLNMapView`) and Android Auto
/// (`NavigationTemplate` / `NavigationManager` / `SurfaceCallback`).
/// Kept 100% independent of Flutter UI widgets.
@immutable
class AutomotiveNavigationFrame {
  const AutomotiveNavigationFrame({
    this.sequenceId = 0,
    this.tripId = '',
    required this.isNavigating,
    this.phase = 'idle',
    this.currentLat,
    this.currentLon,
    this.bearingDeg,
    this.accuracyMeters,
    required this.maneuverType,
    required this.primaryInstruction,
    this.secondaryInstruction,
    this.nextManeuverType,
    this.roadRef,
    this.roadName,
    this.drivingSide = 'left',
    required this.distanceToManeuverMeters,
    required this.remainingDistanceMeters,
    required this.remainingDurationSeconds,
    this.etaEpochMs = 0,
    required this.currentSpeedKmh,
    this.speedLimitKmh,
    required this.speedAlertLevel,
    required this.countryCode,
    required this.currencyCode,
    this.currencySymbol = 'RM',
    this.tripTollSummaryText = 'Free',
    this.turnLanes = const <String>[],
    this.laneItems = const <AutomotiveLaneItem>[],
    this.approachingTollName,
    this.approachingTollDistanceMeters,
    this.approachingTollPayments = const <String>[],
    this.approachingHazardId,
    this.approachingHazardCategory,
    this.approachingHazardLabel,
    this.approachingHazardDistanceMeters,
    this.liveTrafficDelaySeconds = 0.0,
    this.rerouteProposalId,
    this.rerouteBannerText,
    this.rerouteTimeSavedSeconds,
    this.rerouteTollDeltaText,
    this.isOffRoute = false,
    this.voiceMuted = false,
    this.isDarkMode = true,
    this.isRouteOverviewActive = false,
  });

  final int sequenceId;
  final String tripId;
  final bool isNavigating;
  final String phase;
  final double? currentLat;
  final double? currentLon;
  final double? bearingDeg;
  final double? accuracyMeters;
  final int maneuverType;
  final String primaryInstruction;
  final String? secondaryInstruction;
  final int? nextManeuverType;
  final String? roadRef;
  final String? roadName;
  final String drivingSide;
  final double distanceToManeuverMeters;
  final double remainingDistanceMeters;
  final double remainingDurationSeconds;
  final int etaEpochMs;
  final double currentSpeedKmh;
  final int? speedLimitKmh;
  final String speedAlertLevel;
  final String countryCode;
  final String currencyCode;
  final String currencySymbol;
  final String tripTollSummaryText;

  /// Legacy flat lane specs preserved for backward compatibility.
  final List<String> turnLanes;

  /// Full structured lane guidance with recommendation flags.
  final List<AutomotiveLaneItem> laneItems;

  final String? approachingTollName;
  final double? approachingTollDistanceMeters;
  final List<String> approachingTollPayments;
  final String? approachingHazardId;
  final String? approachingHazardCategory;
  final String? approachingHazardLabel;
  final double? approachingHazardDistanceMeters;
  final double liveTrafficDelaySeconds;
  final String? rerouteProposalId;
  final String? rerouteBannerText;
  final double? rerouteTimeSavedSeconds;
  final String? rerouteTollDeltaText;
  final bool isOffRoute;
  final bool voiceMuted;
  final bool isDarkMode;
  final bool isRouteOverviewActive;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'sequenceId': sequenceId,
        'tripId': tripId,
        'isNavigating': isNavigating,
        'phase': phase,
        'currentLat': currentLat,
        'currentLon': currentLon,
        'bearingDeg': bearingDeg,
        'accuracyMeters': accuracyMeters,
        'maneuverType': maneuverType,
        'primaryInstruction': primaryInstruction,
        'secondaryInstruction': secondaryInstruction,
        'nextManeuverType': nextManeuverType,
        'roadRef': roadRef,
        'roadName': roadName,
        'drivingSide': drivingSide,
        'distanceToManeuverMeters': distanceToManeuverMeters,
        'remainingDistanceMeters': remainingDistanceMeters,
        'remainingDurationSeconds': remainingDurationSeconds,
        'etaEpochMs': etaEpochMs,
        'currentSpeedKmh': currentSpeedKmh,
        'speedLimitKmh': speedLimitKmh,
        'speedAlertLevel': speedAlertLevel,
        'countryCode': countryCode,
        'currencyCode': currencyCode,
        'currencySymbol': currencySymbol,
        'tripTollSummaryText': tripTollSummaryText,
        'turnLanes': turnLanes,
        'laneItems': laneItems.map((l) => l.toMap()).toList(),
        'approachingTollName': approachingTollName,
        'approachingTollDistanceMeters': approachingTollDistanceMeters,
        'approachingTollPayments': approachingTollPayments,
        'approachingHazardId': approachingHazardId,
        'approachingHazardCategory': approachingHazardCategory,
        'approachingHazardLabel': approachingHazardLabel,
        'approachingHazardDistanceMeters': approachingHazardDistanceMeters,
        'liveTrafficDelaySeconds': liveTrafficDelaySeconds,
        'rerouteProposalId': rerouteProposalId,
        'rerouteBannerText': rerouteBannerText,
        'rerouteTimeSavedSeconds': rerouteTimeSavedSeconds,
        'rerouteTollDeltaText': rerouteTollDeltaText,
        'isOffRoute': isOffRoute,
        'voiceMuted': voiceMuted,
        'isDarkMode': isDarkMode,
        'isRouteOverviewActive': isRouteOverviewActive,
      };
}

/// Active route geometry & traffic overlay transmitted on trip start, reroute,
/// or Phone -> Car handoff so native MapLibre renders the corridor offline/online.
@immutable
class AutomotiveRouteGeometryPayload {
  const AutomotiveRouteGeometryPayload({
    required this.tripId,
    required this.routePolyline6,
    this.alternatePolylines6 = const <String>[],
    this.congestionSegments = const <CongestionSegment>[],
    required this.originName,
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLon,
    required this.tollDisplayTotal,
    required this.hasTolls,
  });

  final String tripId;
  final String routePolyline6;
  final List<String> alternatePolylines6;
  final List<CongestionSegment> congestionSegments;
  final String originName;
  final String destinationName;
  final double destinationLat;
  final double destinationLon;
  final String tollDisplayTotal;
  final bool hasTolls;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'tripId': tripId,
        'routePolyline6': routePolyline6,
        'alternatePolylines6': alternatePolylines6,
        'congestionSegments': congestionSegments.map((c) => c.toJson()).toList(),
        'originName': originName,
        'destinationName': destinationName,
        'destinationLat': destinationLat,
        'destinationLon': destinationLon,
        'tollDisplayTotal': tollDisplayTotal,
        'hasTolls': hasTolls,
      };
}

/// Lightweight hazard pin pushed to native MapLibre GeoJSON hazard layer.
@immutable
class AutomotiveHazardPin {
  const AutomotiveHazardPin({
    required this.id,
    required this.category,
    required this.label,
    required this.severity,
    required this.lat,
    required this.lon,
    this.distanceMeters,
    this.roadRef,
    this.onActiveRoute = false,
  });

  factory AutomotiveHazardPin.fromRecord(HazardRecord r) => AutomotiveHazardPin(
        id: r.id,
        category: r.category.wireValue,
        label: r.category.label,
        severity: r.severity.wireValue,
        lat: r.coordinate.lat,
        lon: r.coordinate.lon,
        distanceMeters: r.distanceMeters,
        roadRef: r.roadRef,
        onActiveRoute: r.onActiveRoute,
      );

  final String id;
  final String category;
  final String label;
  final String severity;
  final double lat;
  final double lon;
  final double? distanceMeters;
  final String? roadRef;
  final bool onActiveRoute;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'category': category,
        'label': label,
        'severity': severity,
        'lat': lat,
        'lon': lon,
        'distanceMeters': distanceMeters,
        'roadRef': roadRef,
        'onActiveRoute': onActiveRoute,
      };
}

/// Offline vector map configuration passed to CarPlay / Android Auto MapLibre engines.
@immutable
class AutomotiveOfflineMapConfig {
  const AutomotiveOfflineMapConfig({
    this.offlineModeEnabled = false,
    required this.activePmtilesUrl,
    this.darkStyleSchema = 'openmaptiles',
    this.downloadedRegions = const <Map<String, dynamic>>[],
  });

  final bool offlineModeEnabled;
  final String activePmtilesUrl;
  final String darkStyleSchema;
  final List<Map<String, dynamic>> downloadedRegions;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'offlineModeEnabled': offlineModeEnabled,
        'activePmtilesUrl': activePmtilesUrl,
        'darkStyleSchema': darkStyleSchema,
        'downloadedRegions': downloadedRegions,
      };
}

/// Capabilities announced by a vehicle head unit on connect.
@immutable
class AutomotiveHeadUnitInfo {
  const AutomotiveHeadUnitInfo({
    required this.platform,
    this.screenWidthPx = 800,
    this.screenHeightPx = 480,
    this.densityScale = 2.0,
    this.apiLevel = 1,
    this.supportsInstrumentCluster = false,
    this.supportsOfflineSurface = true,
    this.supportsVoiceInput = true,
    this.isDarkMode = true,
  });

  final AutomotivePlatform platform;
  final int screenWidthPx;
  final int screenHeightPx;
  final double densityScale;
  final int apiLevel;
  final bool supportsInstrumentCluster;
  final bool supportsOfflineSurface;
  final bool supportsVoiceInput;
  final bool isDarkMode;

  double get aspectRatio => screenHeightPx > 0 ? screenWidthPx / screenHeightPx : 1.66;

  AutomotiveViewportClass get viewportClass {
    final ar = aspectRatio;
    if (ar >= 2.05) return AutomotiveViewportClass.ultraWide;
    if (ar >= 1.65) return AutomotiveViewportClass.wide;
    return AutomotiveViewportClass.standard;
  }

  factory AutomotiveHeadUnitInfo.fromMap(Map<Object?, Object?> raw) {
    return AutomotiveHeadUnitInfo(
      platform: AutomotivePlatform.fromWire(raw['platform'] as String?),
      screenWidthPx: (raw['screenWidthPx'] as num?)?.toInt() ?? 800,
      screenHeightPx: (raw['screenHeightPx'] as num?)?.toInt() ?? 480,
      densityScale: (raw['densityScale'] as num?)?.toDouble() ?? 2.0,
      apiLevel: (raw['apiLevel'] as num?)?.toInt() ?? 1,
      supportsInstrumentCluster: (raw['supportsInstrumentCluster'] as bool?) ?? false,
      supportsOfflineSurface: (raw['supportsOfflineSurface'] as bool?) ?? true,
      supportsVoiceInput: (raw['supportsVoiceInput'] as bool?) ?? true,
      isDarkMode: (raw['isDarkMode'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'platform': platform.wireValue,
        'screenWidthPx': screenWidthPx,
        'screenHeightPx': screenHeightPx,
        'densityScale': densityScale,
        'apiLevel': apiLevel,
        'supportsInstrumentCluster': supportsInstrumentCluster,
        'supportsOfflineSurface': supportsOfflineSurface,
        'supportsVoiceInput': supportsVoiceInput,
        'isDarkMode': isDarkMode,
      };
}

/// Atomic state snapshot sent on Phone -> Car handoff and reconnect resync.
@immutable
class AutomotiveHandoffEnvelope {
  const AutomotiveHandoffEnvelope({
    required this.sequenceId,
    required this.tripId,
    required this.frame,
    this.routeGeometry,
    this.hazards = const <AutomotiveHazardPin>[],
    required this.thermalProfile,
    required this.offlineConfig,
    required this.retainTripHistoryOptIn,
    this.disableMapTelemetry = true,
    this.isDarkMode = true,
  });

  final int sequenceId;
  final String tripId;
  final AutomotiveNavigationFrame frame;
  final AutomotiveRouteGeometryPayload? routeGeometry;
  final List<AutomotiveHazardPin> hazards;
  final ThermalRenderProfile thermalProfile;
  final AutomotiveOfflineMapConfig offlineConfig;
  final bool retainTripHistoryOptIn;
  final bool disableMapTelemetry;
  final bool isDarkMode;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'sequenceId': sequenceId,
        'tripId': tripId,
        'frame': frame.toMap(),
        'routeGeometry': routeGeometry?.toMap(),
        'hazards': hazards.map((h) => h.toMap()).toList(),
        'thermalProfile': thermalProfile.toMap(),
        'offlineConfig': offlineConfig.toMap(),
        'retainTripHistoryOptIn': retainTripHistoryOptIn,
        'disableMapTelemetry': disableMapTelemetry,
        'isDarkMode': isDarkMode,
      };
}

/// Immutable status snapshot of Phone <-> Vehicle connection & handoff state.
@immutable
class AutomotiveConnectionState {
  const AutomotiveConnectionState({
    this.phase = AutomotiveHandoffPhase.phoneOnly,
    this.platform = AutomotivePlatform.none,
    this.headUnitInfo,
    this.lastSequenceId = 0,
    this.handoffCount = 0,
    this.lastDisconnectReason,
    this.lastTransitionAt,
  });

  final AutomotiveHandoffPhase phase;
  final AutomotivePlatform platform;
  final AutomotiveHeadUnitInfo? headUnitInfo;
  final int lastSequenceId;
  final int handoffCount;
  final String? lastDisconnectReason;
  final DateTime? lastTransitionAt;

  bool get isConnected =>
      phase == AutomotiveHandoffPhase.handingOffToCar ||
      phase == AutomotiveHandoffPhase.projectedActive;

  AutomotiveConnectionState copyWith({
    AutomotiveHandoffPhase? phase,
    AutomotivePlatform? platform,
    AutomotiveHeadUnitInfo? headUnitInfo,
    bool clearHeadUnitInfo = false,
    int? lastSequenceId,
    int? handoffCount,
    String? lastDisconnectReason,
    DateTime? lastTransitionAt,
  }) =>
      AutomotiveConnectionState(
        phase: phase ?? this.phase,
        platform: platform ?? this.platform,
        headUnitInfo: clearHeadUnitInfo ? null : (headUnitInfo ?? this.headUnitInfo),
        lastSequenceId: lastSequenceId ?? this.lastSequenceId,
        handoffCount: handoffCount ?? this.handoffCount,
        lastDisconnectReason: lastDisconnectReason ?? this.lastDisconnectReason,
        lastTransitionAt: lastTransitionAt ?? this.lastTransitionAt,
      );
}

/// Sealed inbound event stream originating from Apple CarPlay or Android Auto head units.
sealed class AutomotiveInboundEvent {
  const AutomotiveInboundEvent();
}

@immutable
final class HeadUnitConnectedEvent extends AutomotiveInboundEvent {
  const HeadUnitConnectedEvent(this.info);
  final AutomotiveHeadUnitInfo info;
}

@immutable
final class HeadUnitDisconnectedEvent extends AutomotiveInboundEvent {
  const HeadUnitDisconnectedEvent({
    required this.platform,
    required this.reason,
    required this.lastSequenceId,
  });

  final AutomotivePlatform platform;
  final String reason;
  final int lastSequenceId;
}

@immutable
final class HeadUnitAppearanceChangedEvent extends AutomotiveInboundEvent {
  const HeadUnitAppearanceChangedEvent({
    required this.platform,
    required this.isDarkMode,
    this.source = 'vehicle_headlight_sensor',
  });

  final AutomotivePlatform platform;
  final bool isDarkMode;
  final String source;
}

@immutable
final class QuickReportHazardEvent extends AutomotiveInboundEvent {
  const QuickReportHazardEvent({
    required this.category,
    required this.severity,
    this.oppositeSide = false,
    required this.source,
  });

  final HazardCategory category;
  final HazardSeverity severity;
  final bool oppositeSide;
  final String source;
}

@immutable
final class HazardVoteEvent extends AutomotiveInboundEvent {
  const HazardVoteEvent({
    required this.hazardId,
    required this.vote,
  });

  final String hazardId;
  final String vote;
}

@immutable
final class VoiceReportTriggerEvent extends AutomotiveInboundEvent {
  const VoiceReportTriggerEvent({
    required this.localeTag,
    this.transcript,
  });

  final String localeTag;
  final String? transcript;
}

@immutable
final class RerouteDecisionEvent extends AutomotiveInboundEvent {
  const RerouteDecisionEvent({
    required this.proposalId,
    required this.accepted,
  });

  final String proposalId;
  final bool accepted;
}

@immutable
final class NavigationControlEvent extends AutomotiveInboundEvent {
  const NavigationControlEvent(this.action);

  /// One of: `end_trip`, `toggle_mute`, `recenter`, `toggle_overview`, `request_fuel_stops`.
  final String action;
}

@immutable
final class DeviceThermalReportEvent extends AutomotiveInboundEvent {
  const DeviceThermalReportEvent({
    required this.platform,
    required this.thermalLevel,
    this.batteryLevelPercent,
    this.isCharging = false,
    this.batteryTempCelsius,
    this.isLowPowerMode = false,
  });

  final AutomotivePlatform platform;
  final DeviceThermalLevel thermalLevel;
  final int? batteryLevelPercent;
  final bool isCharging;
  final double? batteryTempCelsius;
  final bool isLowPowerMode;
}
