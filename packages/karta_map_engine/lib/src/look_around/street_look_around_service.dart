import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:karta_api_client/karta_api_client.dart';
import 'package:meta/meta.dart';

enum LookAroundSource {
  mapillary,
  interactive3DGroundPerspective,
}

@immutable
class StreetLookAroundResult {
  const StreetLookAroundResult({
    required this.source,
    required this.coordinate,
    required this.headingDeg,
    this.imageUrl,
    this.capturedAt,
    this.attribution = 'Karta 3D Ground Perspective (PMTiles)',
  });

  final LookAroundSource source;
  final Coordinate coordinate;
  final double headingDeg;
  final String? imageUrl;
  final DateTime? capturedAt;
  final String attribution;
}

/// Street-Level Look-Around preview hook.
/// Queries Mapillary Graph API v4 when an access token is provided, and seamlessly
/// falls back to Karta's interactive 3D eye-level ground perspective over live
/// PMTiles 3D extruded buildings (works 100% offline as well).
class StreetLookAroundService {
  StreetLookAroundService({
    this.mapillaryAccessToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String? mapillaryAccessToken;
  final http.Client _http;

  Future<StreetLookAroundResult> fetchNearestPreview({
    required Coordinate coordinate,
    double headingDeg = 0,
  }) async {
    final token = mapillaryAccessToken;
    if (token != null && token.isNotEmpty) {
      try {
        const delta = 0.0012;
        final bbox =
            '${coordinate.lon - delta},${coordinate.lat - delta},${coordinate.lon + delta},${coordinate.lat + delta}';
        final uri = Uri.parse(
          'https://graph.mapillary.com/images?fields=id,thumb_1024_url,compass_angle,captured_at&bbox=$bbox&limit=1',
        );
        final resp = await _http
            .get(uri, headers: <String, String>{'Authorization': 'OAuth $token'})
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
          final data = (decoded['data'] as List<dynamic>?) ?? const <dynamic>[];
          if (data.isNotEmpty) {
            final item = data.first as Map<String, dynamic>;
            final thumb = item['thumb_1024_url'] as String?;
            if (thumb != null && thumb.isNotEmpty) {
              final ms = (item['captured_at'] as num?)?.toInt();
              return StreetLookAroundResult(
                source: LookAroundSource.mapillary,
                coordinate: coordinate,
                headingDeg: (item['compass_angle'] as num?)?.toDouble() ?? headingDeg,
                imageUrl: thumb,
                capturedAt: ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
                attribution: 'Street imagery via Mapillary Open Street Data',
              );
            }
          }
        }
      } catch (_) {
        // Fall through cleanly to interactive 3D eye-level preview
      }
    }

    return StreetLookAroundResult(
      source: LookAroundSource.interactive3DGroundPerspective,
      coordinate: coordinate,
      headingDeg: headingDeg,
      attribution: 'Karta 3D Street-Level Ground Perspective (PMTiles)',
    );
  }
}
