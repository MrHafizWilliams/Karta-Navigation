import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/common.dart';
import '../models/commuter.dart';
import '../models/fuel.dart';
import '../models/hazards.dart';
import '../models/health.dart';
import '../models/regions.dart';
import '../models/routing.dart';
import '../models/spatial.dart';
import '../models/tolls.dart';
import '../models/users.dart';
import 'public_valhalla_fallback.dart';

class KartaApiException implements Exception {
  const KartaApiException({
    required this.statusCode,
    required this.message,
    this.body,
  });

  final int statusCode;
  final String message;
  final String? body;

  @override
  String toString() => 'KartaApiException($statusCode): $message';
}

/// Real HTTP client talking directly to Phase 1 `services/karta-api` endpoints
/// (PostGIS, Redis Geo, Valhalla routing, Regional MY/SG/BN Toll Engine, Offline Regions).
class KartaApiClient {
  KartaApiClient({
    required String baseUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 25),
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _timeout = timeout;

  final String baseUrl;
  final http.Client _http;
  final bool _ownsClient;
  final Duration _timeout;
  bool _usingPublicFallback = false;

  /// True when the local self-hosted backend (`localhost:8000`) is not running
  /// and live routing is transparently served by public FOSSGIS Valhalla / OSRM.
  bool get isUsingPublicFallback => _usingPublicFallback;

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final raw = Uri.parse('$baseUrl$path');
    if (queryParameters == null || queryParameters.isEmpty) return raw;
    return raw.replace(queryParameters: queryParameters);
  }

  bool get _isLocalHostBase {
    final lower = baseUrl.toLowerCase();
    return lower.contains('localhost') || lower.contains('127.0.0.1');
  }

  Future<KartaHealthStatus> getHealth() async {
    try {
      final resp = await _http
          .get(
            _uri('/v1/health'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(_isLocalHostBase ? const Duration(seconds: 3) : _timeout);
      final json = _decode(resp) as Map<String, dynamic>;
      _usingPublicFallback = false;
      return KartaHealthStatus.fromJson(json);
    } catch (_) {
      final publicOk = await PublicValhallaFallback.probeAlive(_http);
      if (publicOk) {
        _usingPublicFallback = true;
        return const KartaHealthStatus(
          status: 'ok',
          service: 'karta-public-valhalla',
          postgisOk: false,
          redisOk: false,
          valhallaReachable: true,
          valhallaVersion: 'FOSSGIS Valhalla',
          pmtilesReachable: true,
          pmtilesPublicUrl: 'https://tiles.openfreemap.org/planet',
          routingProfiles: <String>[
            'drive_fastest',
            'drive_no_highways',
            'drive_motorcycle',
          ],
        );
      }
      rethrow;
    }
  }

  /// Lightweight low-timeout liveness probe used for silent tunnel/dead-zone recovery.
  Future<bool> pingLiveHealth({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final resp = await _http
          .get(_uri('/v1/health/live'), headers: const <String, String>{'Accept': 'application/json'})
          .timeout(timeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _usingPublicFallback = false;
        return true;
      }
    } catch (_) {}
    final publicOk = await PublicValhallaFallback.probeAlive(_http, timeout: timeout);
    if (publicOk) {
      _usingPublicFallback = true;
    }
    return publicOk;
  }

  Future<TilePrefetchResponse> getPredictiveTilePlan(TilePrefetchRequest request) async {
    final json = await _postJson('/v1/tiles/prefetch-plan', request.toJson()) as Map<String, dynamic>;
    return TilePrefetchResponse.fromJson(json);
  }

  Future<PoiBBoxResponse> getOfflinePoiIndex({
    String? countryCode,
    BoundingBox? bbox,
    int limit = 2500,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      if (countryCode != null && countryCode.isNotEmpty) 'country_code': countryCode,
      if (bbox != null) ...<String, String>{
        'min_lon': bbox.minLon.toString(),
        'min_lat': bbox.minLat.toString(),
        'max_lon': bbox.maxLon.toString(),
        'max_lat': bbox.maxLat.toString(),
      },
    };
    final json = await _getJson('/v1/pois/offline-index', params) as Map<String, dynamic>;
    return PoiBBoxResponse.fromJson(json);
  }

  Future<RouteResponse> computeRoute(RouteRequest request) async {
    try {
      final resp = await _http
          .post(
            _uri('/v1/routes'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(_isLocalHostBase ? const Duration(seconds: 3) : _timeout);
      final json = _decode(resp) as Map<String, dynamic>;
      _usingPublicFallback = false;
      return RouteResponse.fromJson(json);
    } catch (_) {
      // Automatically fall back to real public Valhalla (FOSSGIS) / OSRM when
      // self-hosted Docker backend is not running.
      final fallback = await PublicValhallaFallback.computeRoute(_http, request);
      _usingPublicFallback = true;
      return fallback;
    }
  }

  Future<PoiBBoxResponse> getPoisInBbox({
    required BoundingBox bbox,
    String? category,
    int limit = 150,
  }) async {
    final params = <String, String>{
      'min_lon': bbox.minLon.toString(),
      'min_lat': bbox.minLat.toString(),
      'max_lon': bbox.maxLon.toString(),
      'max_lat': bbox.maxLat.toString(),
      'limit': limit.toString(),
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final json = await _getJson('/v1/pois/bbox', params) as Map<String, dynamic>;
    return PoiBBoxResponse.fromJson(json);
  }

  Future<PoiBBoxResponse> searchPois({
    required String query,
    double? lat,
    double? lon,
    String? category,
    String? countryCode,
    int limit = 25,
  }) async {
    final params = <String, String>{
      'q': query,
      'limit': limit.toString(),
      if (lat != null) 'lat': lat.toString(),
      if (lon != null) 'lon': lon.toString(),
      if (category != null && category.isNotEmpty) 'category': category,
      if (countryCode != null && countryCode.isNotEmpty) 'country_code': countryCode,
    };
    final json = await _getJson('/v1/pois/search', params) as Map<String, dynamic>;
    return PoiBBoxResponse.fromJson(json);
  }

  Future<RoadContextResponse> getRoadContext({
    required double lat,
    required double lon,
    double? heading,
    double lookaheadMeters = 1500.0,
  }) async {
    final params = <String, String>{
      'lat': lat.toStringAsFixed(6),
      'lon': lon.toStringAsFixed(6),
      'lookahead_m': lookaheadMeters.toStringAsFixed(0),
      if (heading != null) 'heading': (heading % 360).toStringAsFixed(1),
    };
    final json = await _getJson('/v1/spatial/road-context', params) as Map<String, dynamic>;
    return RoadContextResponse.fromJson(json);
  }

  Future<List<GantryInfo>> listTollGantries({
    String? countryCode,
    String? corridorId,
    BoundingBox? bbox,
  }) async {
    final params = <String, String>{
      if (countryCode != null) 'country_code': countryCode,
      if (corridorId != null) 'corridor_id': corridorId,
      if (bbox != null) ...<String, String>{
        'min_lon': bbox.minLon.toString(),
        'min_lat': bbox.minLat.toString(),
        'max_lon': bbox.maxLon.toString(),
        'max_lat': bbox.maxLat.toString(),
      },
    };
    final list = await _getJson('/v1/tolls/gantries', params) as List<dynamic>;
    return list.map((e) => GantryInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<TollSummary> estimateTolls(TollEstimateRequest request) async {
    final json = await _postJson('/v1/tolls/estimate', request.toJson()) as Map<String, dynamic>;
    return TollSummary.fromJson(json);
  }

  Future<OfflineRegionListResponse> listOfflineRegions() async {
    final json = await _getJson('/v1/regions') as Map<String, dynamic>;
    return OfflineRegionListResponse.fromJson(json);
  }

  // ============================================================================
  // PHASE 3: HAZARDS, FUEL PRICES, CALENDAR TTL, PRIVACY CARPOOL & VOICE PACKS
  // ============================================================================
  Future<HazardRecord> reportHazard(HazardReportRequest request) async {
    final json = await _postJson('/v1/hazards', request.toJson()) as Map<String, dynamic>;
    return HazardRecord.fromJson(json);
  }

  Future<NearbyHazardsResponse> getNearbyHazards({
    required double lat,
    required double lon,
    double? headingDeg,
    double speedKmh = 0.0,
    double? maxRadiusMeters,
  }) async {
    final params = <String, String>{
      'lat': lat.toStringAsFixed(6),
      'lon': lon.toStringAsFixed(6),
      'speed_kmh': speedKmh.toStringAsFixed(1),
      if (headingDeg != null) 'heading': (headingDeg % 360).toStringAsFixed(1),
      if (maxRadiusMeters != null) 'max_radius_m': maxRadiusMeters.toStringAsFixed(0),
    };
    final json = await _getJson('/v1/hazards/nearby', params) as Map<String, dynamic>;
    return NearbyHazardsResponse.fromJson(json);
  }

  Future<HazardRecord> voteHazard({
    required String hazardId,
    required String vote,
    String? voterSessionId,
    Coordinate? coordinate,
  }) async {
    final json = await _postJson(
      '/v1/hazards/$hazardId/vote',
      <String, dynamic>{
        'vote': vote,
        if (voterSessionId != null) 'voter_session_id': voterSessionId,
        if (coordinate != null) 'coordinate': coordinate.toJson(),
      },
    ) as Map<String, dynamic>;
    return HazardRecord.fromJson(json);
  }

  Future<FuelComparisonResponse> getFuelAlongRoute({
    required String polyline6,
    FuelGrade? fuelGrade,
    String? countryCode,
    double maxDetourMeters = 1800.0,
    String sortBy = 'price',
    int limit = 20,
  }) async {
    final json = await _postJson(
      '/v1/fuel/along-route',
      <String, dynamic>{
        'polyline6': polyline6,
        if (fuelGrade != null) 'fuel_grade': fuelGrade.wireValue,
        if (countryCode != null) 'country_code': countryCode,
        'max_detour_meters': maxDetourMeters,
        'sort_by': sortBy,
        'limit': limit,
      },
    ) as Map<String, dynamic>;
    return FuelComparisonResponse.fromJson(json);
  }

  Future<FuelComparisonResponse> getFuelNearby({
    required double lat,
    required double lon,
    double radiusMeters = 5000.0,
    FuelGrade? fuelGrade,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'lat': lat.toStringAsFixed(6),
      'lon': lon.toStringAsFixed(6),
      'radius_m': radiusMeters.toStringAsFixed(0),
      'limit': limit.toString(),
      if (fuelGrade != null) 'fuel_grade': fuelGrade.wireValue,
    };
    final json = await _getJson('/v1/fuel/nearby', params) as Map<String, dynamic>;
    return FuelComparisonResponse.fromJson(json);
  }

  Future<FuelGradeQuote> updateFuelPrice({
    required int poiId,
    required FuelGrade fuelGrade,
    required int priceMinor,
    String? reporterSessionId,
  }) async {
    final json = await _postJson(
      '/v1/fuel/stations/$poiId/prices',
      <String, dynamic>{
        'fuel_grade': fuelGrade.wireValue,
        'price_minor': priceMinor,
        if (reporterSessionId != null) 'reporter_session_id': reporterSessionId,
      },
    ) as Map<String, dynamic>;
    return FuelGradeQuote.fromJson(json);
  }

  Future<List<CalendarEventItem>> importCalendarIcs({
    required String userToken,
    required String icsContent,
    String provider = 'ics_url',
  }) async {
    final list = await _postJson(
      '/v1/calendar/import-ics',
      <String, dynamic>{
        'user_token': userToken,
        'provider': provider,
        'ics_content': icsContent,
      },
    ) as List<dynamic>;
    return list.map((e) => CalendarEventItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> registerCalendarFeed({
    required String userToken,
    required String provider,
    required String label,
    String? feedUrl,
  }) async {
    final json = await _postJson(
      '/v1/calendar/feeds',
      <String, dynamic>{
        'user_token': userToken,
        'provider': provider,
        'label': label,
        if (feedUrl != null && feedUrl.isNotEmpty) 'feed_url': feedUrl,
      },
    ) as Map<String, dynamic>;
    return json;
  }

  Future<CalendarEventItem> createCalendarEvent({
    required String userToken,
    required String title,
    String provider = 'manual',
    String? locationText,
    Coordinate? destination,
    required DateTime startsAt,
    DateTime? endsAt,
    int parkingBufferSec = 600,
  }) async {
    final json = await _postJson(
      '/v1/calendar/events',
      <String, dynamic>{
        'user_token': userToken,
        'title': title,
        'provider': provider,
        if (locationText != null) 'location_text': locationText,
        if (destination != null) 'destination': destination.toJson(),
        'starts_at': startsAt.toUtc().toIso8601String(),
        if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
        'parking_buffer_sec': parkingBufferSec,
      },
    ) as Map<String, dynamic>;
    return CalendarEventItem.fromJson(json);
  }

  Future<EvaluateDeparturesResponse> evaluateDepartures({
    required String userToken,
    required Coordinate origin,
    int horizonHours = 24,
  }) async {
    final json = await _postJson(
      '/v1/calendar/evaluate-departures',
      <String, dynamic>{
        'user_token': userToken,
        'origin': origin.toJson(),
        'horizon_hours': horizonHours,
      },
    ) as Map<String, dynamic>;
    return EvaluateDeparturesResponse.fromJson(json);
  }

  Future<CarpoolOfferPublic> createCarpoolOffer({
    required String driverToken,
    required String driverAlias,
    String? verifiedBadge,
    required Coordinate origin,
    required Coordinate destination,
    required DateTime departureAt,
    int flexibilityMinutes = 20,
    int seatsTotal = 3,
    String? notes,
  }) async {
    final json = await _postJson(
      '/v1/carpool/offers',
      <String, dynamic>{
        'driver_token': driverToken,
        'driver_alias': driverAlias,
        if (verifiedBadge != null) 'verified_badge': verifiedBadge,
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'departure_at': departureAt.toUtc().toIso8601String(),
        'flexibility_minutes': flexibilityMinutes,
        'seats_total': seatsTotal,
        if (notes != null) 'notes': notes,
      },
    ) as Map<String, dynamic>;
    return CarpoolOfferPublic.fromJson(json);
  }

  Future<List<CarpoolOfferPublic>> listCarpoolOffers({String? countryCode}) async {
    final params = <String, String>{
      if (countryCode != null) 'country_code': countryCode,
    };
    final list = await _getJson('/v1/carpool/offers', params) as List<dynamic>;
    return list.map((e) => CarpoolOfferPublic.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<CarpoolMatchCandidate>> searchCarpoolMatches({
    required String riderToken,
    required Coordinate pickup,
    required Coordinate dropoff,
    required DateTime departureAt,
    double maxDetourMeters = 2500.0,
    int timeWindowMinutes = 30,
  }) async {
    final list = await _postJson(
      '/v1/carpool/matches/search',
      <String, dynamic>{
        'rider_token': riderToken,
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'departure_at': departureAt.toUtc().toIso8601String(),
        'max_detour_meters': maxDetourMeters,
        'time_window_minutes': timeWindowMinutes,
      },
    ) as List<dynamic>;
    return list.map((e) => CarpoolMatchCandidate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CarpoolMatchRecord> requestCarpoolSeat({
    required String offerId,
    required String riderToken,
    required String riderAlias,
    required Coordinate pickup,
    required Coordinate dropoff,
    String? rendezvousNote,
  }) async {
    final json = await _postJson(
      '/v1/carpool/offers/$offerId/request',
      <String, dynamic>{
        'rider_token': riderToken,
        'rider_alias': riderAlias,
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        if (rendezvousNote != null) 'rendezvous_note': rendezvousNote,
      },
    ) as Map<String, dynamic>;
    return CarpoolMatchRecord.fromJson(json);
  }

  Future<VoiceIntentResult> parseVoiceIntent({
    required String transcript,
    String locale = 'en-MY',
    Coordinate? coordinate,
    double? headingDeg,
  }) async {
    final json = await _postJson(
      '/v1/voice/parse-intent',
      <String, dynamic>{
        'transcript': transcript,
        'locale': locale,
        if (coordinate != null) 'coordinate': coordinate.toJson(),
        if (headingDeg != null) 'heading_deg': headingDeg,
      },
    ) as Map<String, dynamic>;
    return VoiceIntentResult.fromJson(json);
  }

  Future<List<CustomVoicePackRecord>> listVoicePacks({
    required String ownerToken,
    bool includeAudio = false,
  }) async {
    final list = await _getJson(
      '/v1/voice/packs',
      <String, String>{
        'owner_token': ownerToken,
        'include_audio': includeAudio.toString(),
      },
    ) as List<dynamic>;
    return list.map((e) => CustomVoicePackRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CustomVoicePackRecord> createVoicePack({
    required String ownerToken,
    required String name,
    String locale = 'en-MY',
    String baseTtsVoice = 'karta_studio_en',
  }) async {
    final json = await _postJson(
      '/v1/voice/packs',
      <String, dynamic>{
        'owner_token': ownerToken,
        'name': name,
        'locale': locale,
        'base_tts_voice': baseTtsVoice,
      },
    ) as Map<String, dynamic>;
    return CustomVoicePackRecord.fromJson(json);
  }

  Future<CustomVoiceClipMeta> uploadVoiceClip({
    required String packId,
    required String cueKey,
    required String mimeType,
    required int durationMs,
    required String audioBase64,
  }) async {
    final json = await _putJson(
      '/v1/voice/packs/$packId/clips/$cueKey',
      <String, dynamic>{
        'mime_type': mimeType,
        'duration_ms': durationMs,
        'audio_base64': audioBase64,
      },
    ) as Map<String, dynamic>;
    return CustomVoiceClipMeta.fromJson(json);
  }

  Future<void> deleteVoiceClip({
    required String packId,
    required String cueKey,
  }) async {
    final resp = await _http
        .delete(_uri('/v1/voice/packs/$packId/clips/$cueKey'))
        .timeout(_timeout);
    _decode(resp);
  }

  // ============================================================================
  // USER ACCOUNTS, SESSIONS & SAVED PLACES / LANDMARKS
  // ============================================================================
  Future<AuthSessionResponse> registerUser({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final json = await _postJson(
      '/v1/auth/register',
      <String, dynamic>{
        'email': email,
        'display_name': displayName,
        'password': password,
      },
    ) as Map<String, dynamic>;
    return AuthSessionResponse.fromJson(json);
  }

  Future<AuthSessionResponse> loginUser({
    required String email,
    required String password,
  }) async {
    final json = await _postJson(
      '/v1/auth/login',
      <String, dynamic>{
        'email': email,
        'password': password,
      },
    ) as Map<String, dynamic>;
    return AuthSessionResponse.fromJson(json);
  }

  Future<void> logoutUser({required String accessToken}) async {
    final resp = await _http
        .post(
          _uri('/v1/auth/logout'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        )
        .timeout(_timeout);
    _decode(resp);
  }

  Future<KartaUserProfile> getCurrentUser({required String accessToken}) async {
    final resp = await _http
        .get(
          _uri('/v1/auth/me'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        )
        .timeout(_timeout);
    return KartaUserProfile.fromJson(_decode(resp) as Map<String, dynamic>);
  }

  Future<SavedPlacesListResponse> listSavedPlaces({required String accessToken}) async {
    final resp = await _http
        .get(
          _uri('/v1/saved-places'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        )
        .timeout(_timeout);
    return SavedPlacesListResponse.fromJson(_decode(resp) as Map<String, dynamic>);
  }

  Future<SavedPlaceItem> createSavedPlace({
    required String accessToken,
    required SavedPlaceCreateRequest request,
  }) async {
    final resp = await _http
        .post(
          _uri('/v1/saved-places'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(request.toJson()),
        )
        .timeout(_timeout);
    return SavedPlaceItem.fromJson(_decode(resp) as Map<String, dynamic>);
  }

  Future<void> deleteSavedPlace({
    required String accessToken,
    required String placeId,
  }) async {
    final resp = await _http
        .delete(
          _uri('/v1/saved-places/$placeId'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        )
        .timeout(_timeout);
    _decode(resp);
  }

  Future<dynamic> _putJson(String path, Map<String, dynamic> payload) async {
    final resp = await _http
        .put(
          _uri(path),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    return _decode(resp);
  }

  Future<dynamic> _getJson(String path, [Map<String, String>? query]) async {
    final resp = await _http
        .get(_uri(path, query), headers: const <String, String>{'Accept': 'application/json'})
        .timeout(_timeout);
    return _decode(resp);
  }

  Future<dynamic> _postJson(String path, Map<String, dynamic> payload) async {
    final resp = await _http
        .post(
          _uri(path),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    return _decode(resp);
  }

  dynamic _decode(http.Response resp) {
    final text = utf8.decode(resp.bodyBytes);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = 'HTTP ${resp.statusCode}';
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
          msg = decoded['detail'].toString();
        }
      } catch (_) {}
      throw KartaApiException(
        statusCode: resp.statusCode,
        message: msg,
        body: text,
      );
    }
    return jsonDecode(text);
  }

  void close() {
    if (_ownsClient) {
      _http.close();
    }
  }
}
