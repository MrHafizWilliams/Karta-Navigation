import 'package:meta/meta.dart';

@immutable
class KartaHealthStatus {
  const KartaHealthStatus({
    required this.status,
    required this.service,
    required this.postgisOk,
    required this.redisOk,
    required this.valhallaReachable,
    this.valhallaVersion,
    required this.pmtilesReachable,
    required this.pmtilesPublicUrl,
    this.routingProfiles = const <String>[],
  });

  final String status;
  final String service;
  final bool postgisOk;
  final bool redisOk;
  final bool valhallaReachable;
  final String? valhallaVersion;
  final bool pmtilesReachable;
  final String pmtilesPublicUrl;
  final List<String> routingProfiles;

  bool get isHealthy => status == 'ok';

  factory KartaHealthStatus.fromJson(Map<String, dynamic> json) {
    final deps = (json['dependencies'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final pg = deps['postgis'];
    final redis = (deps['redis_geo'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final valhalla = (deps['valhalla'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final pmtiles = (deps['pmtiles'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

    return KartaHealthStatus(
      status: (json['status'] as String?) ?? 'degraded',
      service: (json['service'] as String?) ?? 'karta-api',
      postgisOk: pg is Map ? (pg.isNotEmpty) : (pg == true),
      redisOk: redis['ping'] == true,
      valhallaReachable: valhalla['reachable'] == true,
      valhallaVersion: valhalla['version'] as String?,
      pmtilesReachable: pmtiles['reachable'] == true,
      pmtilesPublicUrl: (pmtiles['public_url'] as String?) ?? 'http://localhost:8081',
      routingProfiles: (json['routing_profiles'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e as String)
          .toList(),
    );
  }
}
