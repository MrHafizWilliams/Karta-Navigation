import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';

import '../models/common.dart';
import '../models/hazards.dart';
import 'ws_transport.dart';
import 'ws_transport_stub.dart'
    if (dart.library.js_interop) 'ws_transport_web.dart'
    if (dart.library.io) 'ws_transport_io.dart' as transport;

enum RealtimeConnectionState {
  disconnected,
  connecting,
  connected,
}

@immutable
class RealtimeFrame {
  const RealtimeFrame({
    required this.eventType,
    required this.raw,
    this.hazard,
    this.removedHazardId,
    this.initialHazards,
    this.rerouteProposal,
    this.congestionSegments,
    this.trafficDelaySeconds,
  });

  final String eventType;
  final Map<String, dynamic> raw;
  final HazardRecord? hazard;
  final String? removedHazardId;
  final List<HazardRecord>? initialHazards;
  final RerouteProposal? rerouteProposal;
  final List<CongestionSegment>? congestionSegments;
  final double? trafficDelaySeconds;

  factory RealtimeFrame.parse(Map<String, dynamic> json) {
    final type = (json['event_type'] as String?) ?? 'unknown';
    HazardRecord? hazard;
    if (json['hazard'] is Map<String, dynamic>) {
      hazard = HazardRecord.fromJson(json['hazard'] as Map<String, dynamic>);
    }
    List<HazardRecord>? initial;
    if (json['initial_hazards'] is List<dynamic>) {
      initial = (json['initial_hazards'] as List<dynamic>)
          .map((e) => HazardRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    RerouteProposal? proposal;
    if (json['proposal'] is Map<String, dynamic>) {
      proposal = RerouteProposal.fromJson(json['proposal'] as Map<String, dynamic>);
    }
    List<CongestionSegment>? segs;
    if (json['congestion_segments'] is List<dynamic>) {
      segs = (json['congestion_segments'] as List<dynamic>)
          .map((e) => CongestionSegment.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return RealtimeFrame(
      eventType: type,
      raw: json,
      hazard: hazard,
      removedHazardId: json['hazard_id'] as String?,
      initialHazards: initial,
      rerouteProposal: proposal,
      congestionSegments: segs,
      trafficDelaySeconds: (json['traffic_delay_seconds'] as num?)?.toDouble(),
    );
  }
}

/// Cross-platform low-latency WebSocket client connecting to Karta Phase 3
/// `/v1/realtime/ws` with automatic exponential-backoff reconnection.
class KartaRealtimeClient {
  KartaRealtimeClient({
    required this.httpBaseUrl,
    required this.sessionId,
  });

  final String httpBaseUrl;
  final String sessionId;

  final StreamController<RealtimeFrame> _framesCtrl = StreamController<RealtimeFrame>.broadcast();
  final StreamController<RealtimeConnectionState> _statusCtrl =
      StreamController<RealtimeConnectionState>.broadcast();

  KartaWebSocketHandle? _handle;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _shouldReconnect = false;
  int _retryAttempt = 0;
  Coordinate _lastCoord = const Coordinate(lat: 3.1579, lon: 101.7116);
  String _lastCountry = 'MY';
  RealtimeConnectionState _status = RealtimeConnectionState.disconnected;

  Stream<RealtimeFrame> get frames => _framesCtrl.stream;
  Stream<RealtimeConnectionState> get statusStream => _statusCtrl.stream;
  RealtimeConnectionState get status => _status;

  String buildWsUri({required Coordinate initialCoord, String country = 'MY'}) {
    final base = httpBaseUrl.endsWith('/')
        ? httpBaseUrl.substring(0, httpBaseUrl.length - 1)
        : httpBaseUrl;
    final wsBase = base.startsWith('https://')
        ? base.replaceFirst('https://', 'wss://')
        : base.replaceFirst('http://', 'ws://');
    final uri = Uri.parse('$wsBase/v1/realtime/ws').replace(
      queryParameters: <String, String>{
        'session_id': sessionId,
        'lat': initialCoord.lat.toStringAsFixed(6),
        'lon': initialCoord.lon.toStringAsFixed(6),
        'country': country,
      },
    );
    return uri.toString();
  }

  Future<void> connect({
    Coordinate initialCoord = const Coordinate(lat: 3.1579, lon: 101.7116),
    String country = 'MY',
  }) async {
    if (_disposed) return;
    _lastCoord = initialCoord;
    _lastCountry = country;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();

    _setStatus(RealtimeConnectionState.connecting);
    try {
      final wsUrl = buildWsUri(initialCoord: initialCoord, country: country);
      final handle = await transport.connectPlatformWebSocket(wsUrl);
      if (_disposed) {
        await handle.close();
        return;
      }
      _handle = handle;
      _retryAttempt = 0;
      _setStatus(RealtimeConnectionState.connected);

      handle.messages.listen((raw) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic> && !_framesCtrl.isClosed) {
            _framesCtrl.add(RealtimeFrame.parse(decoded));
          }
        } catch (_) {}
      });

      handle.onClosed.listen((_) {
        _heartbeatTimer?.cancel();
        if (!_disposed) {
          _setStatus(RealtimeConnectionState.disconnected);
          if (_shouldReconnect) _scheduleReconnect();
        }
      });

      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        sendRaw(<String, dynamic>{'type': 'ping'});
      });
    } catch (_) {
      _setStatus(RealtimeConnectionState.disconnected);
      if (_shouldReconnect && !_disposed) _scheduleReconnect();
    }
  }

  void sendTelemetry({
    required Coordinate coordinate,
    required double headingDeg,
    required double speedKmh,
    String? countryCode,
    String? routeId,
    String? routePolyline6,
    String routeProfile = 'drive_fastest',
    String vehicleProfile = 'car',
    String vehicleRegistrationCountry = 'MY',
    Coordinate? destination,
    List<Coordinate> waypoints = const <Coordinate>[],
  }) {
    _lastCoord = coordinate;
    if (countryCode != null) _lastCountry = countryCode;
    sendRaw(<String, dynamic>{
      'type': 'telemetry.update',
      'coordinate': coordinate.toJson(),
      'heading_deg': headingDeg % 360.0,
      'speed_kmh': speedKmh,
      if (countryCode != null) 'country_code': countryCode,
      if (routeId != null) 'route_id': routeId,
      if (routePolyline6 != null) 'route_polyline6': routePolyline6,
      'route_profile': routeProfile,
      'vehicle_profile': vehicleProfile,
      'vehicle_registration_country': vehicleRegistrationCountry,
      if (destination != null) 'destination': destination.toJson(),
      if (waypoints.isNotEmpty) 'waypoints': waypoints.map((w) => w.toJson()).toList(),
    });
  }

  void sendHazardReport(HazardReportRequest request) {
    sendRaw(<String, dynamic>{
      'type': 'hazard.report',
      ...request.toJson(),
    });
  }

  void sendHazardVote({
    required String hazardId,
    required String vote,
    Coordinate? coordinate,
  }) {
    sendRaw(<String, dynamic>{
      'type': 'hazard.vote',
      'hazard_id': hazardId,
      'vote': vote,
      if (coordinate != null) 'coordinate': coordinate.toJson(),
    });
  }

  void sendRerouteDecision({required String proposalId, required String action}) {
    sendRaw(<String, dynamic>{
      'type': 'route.reroute_decision',
      'proposal_id': proposalId,
      'action': action,
    });
  }

  void sendRaw(Map<String, dynamic> payload) {
    if (_handle != null && _handle!.isOpen) {
      _handle!.sendText(jsonEncode(payload));
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _retryAttempt += 1;
    final delaySec = (_retryAttempt * 2).clamp(2, 16);
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_disposed && _shouldReconnect) {
        connect(initialCoord: _lastCoord, country: _lastCountry);
      }
    });
  }

  void _setStatus(RealtimeConnectionState next) {
    _status = next;
    if (!_statusCtrl.isClosed) _statusCtrl.add(next);
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _handle?.close();
    _handle = null;
    _setStatus(RealtimeConnectionState.disconnected);
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _framesCtrl.close();
    await _statusCtrl.close();
  }
}
