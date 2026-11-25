import 'package:meta/meta.dart';
import 'common.dart';

@immutable
class OfflineRegionPack {
  const OfflineRegionPack({
    required this.regionId,
    required this.displayName,
    required this.countryCodes,
    required this.bbox,
    required this.dataVersion,
    required this.pmtilesUrl,
    required this.pmtilesSha256,
    required this.pmtilesBytes,
    required this.valhallaTarUrl,
    required this.valhallaTarSha256,
    required this.valhallaTarBytes,
    this.tollsSqliteUrl,
    this.tollsSqliteSha256,
    this.tollsSqliteBytes = 0,
    required this.updatedAt,
  });

  final String regionId;
  final String displayName;
  final List<String> countryCodes;
  final BoundingBox bbox;
  final String dataVersion;
  final String pmtilesUrl;
  final String pmtilesSha256;
  final int pmtilesBytes;
  final String valhallaTarUrl;
  final String valhallaTarSha256;
  final int valhallaTarBytes;
  final String? tollsSqliteUrl;
  final String? tollsSqliteSha256;
  final int tollsSqliteBytes;
  final DateTime updatedAt;

  int get totalBytes => pmtilesBytes + valhallaTarBytes + tollsSqliteBytes;

  factory OfflineRegionPack.fromJson(Map<String, dynamic> json) => OfflineRegionPack(
        regionId: json['region_id'] as String,
        displayName: json['display_name'] as String,
        countryCodes: (json['country_codes'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => (e as String).trim())
            .toList(),
        bbox: BoundingBox.fromJson(json['bbox'] as Map<String, dynamic>),
        dataVersion: json['data_version'] as String,
        pmtilesUrl: json['pmtiles_url'] as String,
        pmtilesSha256: (json['pmtiles_sha256'] as String).trim(),
        pmtilesBytes: (json['pmtiles_bytes'] as num).toInt(),
        valhallaTarUrl: json['valhalla_tar_url'] as String,
        valhallaTarSha256: (json['valhalla_tar_sha256'] as String).trim(),
        valhallaTarBytes: (json['valhalla_tar_bytes'] as num).toInt(),
        tollsSqliteUrl: json['tolls_sqlite_url'] as String?,
        tollsSqliteSha256: (json['tolls_sqlite_sha256'] as String?)?.trim(),
        tollsSqliteBytes: (json['tolls_sqlite_bytes'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

@immutable
class OfflineRegionListResponse {
  const OfflineRegionListResponse({required this.count, required this.regions});

  final int count;
  final List<OfflineRegionPack> regions;

  factory OfflineRegionListResponse.fromJson(Map<String, dynamic> json) =>
      OfflineRegionListResponse(
        count: (json['count'] as num).toInt(),
        regions: (json['regions'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => OfflineRegionPack.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
