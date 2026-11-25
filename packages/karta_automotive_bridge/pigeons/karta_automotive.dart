/// Bidirectional Pigeon IDL Specification for Karta Native Automotive Bridge
/// (Apple CarPlay `CPMapTemplate` & Android Auto `NavigationTemplate`).
///
/// Run `dart run pigeon --input pigeons/karta_automotive.dart` when regenerating
/// typed Swift/Kotlin codec bindings for iOS/Android host builds.

class PigeonLaneItem {
  late String laneSpec;
  late bool isRecommended;
}

class PigeonCongestionSegment {
  late double startFraction;
  late double endFraction;
  late String severity;
  late int speedKmh;
}

class PigeonHazardPin {
  late String id;
  late String category;
  late String label;
  late String severity;
  late double lat;
  late double lon;
  double? distanceMeters;
  String? roadRef;
  late bool onActiveRoute;
}

class PigeonNavigationFrame {
  late int sequenceId;
  late String tripId;
  late bool isNavigating;
  late String phase;
  double? currentLat;
  double? currentLon;
  double? bearingDeg;
  double? accuracyMeters;
  late int maneuverType;
  late String primaryInstruction;
  String? secondaryInstruction;
  int? nextManeuverType;
  String? roadRef;
  String? roadName;
  late String drivingSide;
  late double distanceToManeuverMeters;
  late double remainingDistanceMeters;
  late double remainingDurationSeconds;
  late int etaEpochMs;
  late double currentSpeedKmh;
  int? speedLimitKmh;
  late String speedAlertLevel;
  late String countryCode;
  late String currencyCode;
  late String currencySymbol;
  late String tripTollSummaryText;
  late List<PigeonLaneItem?> laneItems;
  String? approachingTollName;
  double? approachingTollDistanceMeters;
  late List<String?> approachingTollPayments;
  String? approachingHazardId;
  String? approachingHazardCategory;
  String? approachingHazardLabel;
  double? approachingHazardDistanceMeters;
  late double liveTrafficDelaySeconds;
  String? rerouteProposalId;
  String? rerouteBannerText;
  double? rerouteTimeSavedSeconds;
  String? rerouteTollDeltaText;
  late bool isOffRoute;
  late bool voiceMuted;
  late bool isDarkMode;
  late bool isRouteOverviewActive;
}

class PigeonRouteGeometry {
  late String tripId;
  late String routePolyline6;
  late List<String?> alternatePolylines6;
  late List<PigeonCongestionSegment?> congestionSegments;
  late String originName;
  late String destinationName;
  late double destinationLat;
  late double destinationLon;
  late String tollDisplayTotal;
  late bool hasTolls;
}

class PigeonThermalRenderProfile {
  late String thermalTier;
  late int headUnitTargetFps;
  late int phoneTargetFps;
  late bool pausePhoneMapCanvas;
  late bool enableHeadUnit3DBuildings;
  late bool enablePhone3DBuildings;
  late bool enableVehicleHaloShader;
  late double headUnitCameraPitchDeg;
  late int bridgePublishIntervalMs;
  late int roadContextPollIntervalMs;
  late int maxOfflineTileCacheMb;
  late bool isProjectedToHeadUnit;
  late String reason;
}

class PigeonOfflineRegion {
  late String regionId;
  late String displayName;
  late String pmtilesUrl;
  late String localPmtilesPath;
  late bool verifiedSha256;
  late double minLon;
  late double minLat;
  late double maxLon;
  late double maxLat;
}

class PigeonOfflineMapConfig {
  late bool offlineModeEnabled;
  late String activePmtilesUrl;
  late String darkStyleSchema;
  late List<PigeonOfflineRegion?> downloadedRegions;
}

class PigeonHandoffEnvelope {
  late int sequenceId;
  late String tripId;
  late PigeonNavigationFrame frame;
  PigeonRouteGeometry? routeGeometry;
  late List<PigeonHazardPin?> hazards;
  late PigeonThermalRenderProfile thermalProfile;
  late PigeonOfflineMapConfig offlineConfig;
  late bool retainTripHistoryOptIn;
  late bool disableMapTelemetry;
  late bool isDarkMode;
}

class PigeonHeadUnitInfo {
  late String platform;
  late int screenWidthPx;
  late int screenHeightPx;
  late double densityScale;
  late int apiLevel;
  late bool supportsInstrumentCluster;
  late bool supportsOfflineSurface;
  late bool supportsVoiceInput;
  late bool isDarkMode;
}

class PigeonDeviceThermalReport {
  late String platform;
  late String thermalLevel;
  int? batteryLevelPercent;
  late bool isCharging;
  double? batteryTempCelsius;
  late bool isLowPowerMode;
}

/// Dart -> Native head-unit command surface (CarPlay & Android Auto).
abstract class KartaAutomotiveHostApi {
  void syncFullState(PigeonHandoffEnvelope envelope);
  void publishNavigationFrame(PigeonNavigationFrame frame);
  void updateRouteGeometry(PigeonRouteGeometry route);
  void updateHazards(List<PigeonHazardPin> hazards);
  void applyThermalRenderProfile(PigeonThermalRenderProfile profile);
  void updateOfflineMapConfig(PigeonOfflineMapConfig config);
  void setVehicleAppearance(bool isDarkMode);
  void endAutomotiveSession(String reason);
  void scrubEphemeralLocationState();
}

/// Native -> Dart bidirectional callback surface from vehicle head-unit UI & OS monitors.
abstract class KartaAutomotiveFlutterApi {
  void onHeadUnitConnected(PigeonHeadUnitInfo info);
  void onHeadUnitDisconnected(String platform, String reason, int lastSequenceId);
  void onHeadUnitAppearanceChanged(String platform, bool isDarkMode, String source);
  void onQuickReportHazard(
    String categoryWire,
    String severityWire,
    bool oppositeSide,
    String source,
  );
  void onHazardVote(String hazardId, String vote);
  void onVoiceReportTriggered(String localeTag);
  void onVoiceTranscriptCaptured(String transcript, String localeTag);
  void onRerouteDecision(String proposalId, bool accepted);
  void onNavigationControlAction(String action);
  void onThermalStateChanged(PigeonDeviceThermalReport report);
}
