import 'package:flutter/widgets.dart';
import 'package:karta_api_client/karta_api_client.dart';
import '../controller/karta_map_controller.dart';
import 'karta_map_view_native.dart'
    if (dart.library.js_interop) 'karta_map_view_web.dart' as platform;

/// Cross-platform 3D MapLibre view connected to Karta's MY/SG/BN PMTiles.
/// - On Web: embeds MapLibre GL JS + `pmtiles` protocol + custom WebGL2 3D vehicle layer.
/// - On iOS/Android/Windows/macOS/Linux: binds to MapLibre Native via the identical controller.
class KartaMapView extends StatelessWidget {
  const KartaMapView({
    super.key,
    required this.controller,
    required this.pmtilesUrl,
    this.initialCenter = const Coordinate(lat: 3.1579, lon: 101.7116),
    this.initialZoom = 11.2,
    this.initialPitch = 54.0,
  });

  final KartaMapController controller;
  final String pmtilesUrl;
  final Coordinate initialCenter;
  final double initialZoom;
  final double initialPitch;

  @override
  Widget build(BuildContext context) {
    return platform.buildPlatformKartaMapView(
      controller: controller,
      pmtilesUrl: pmtilesUrl,
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      initialPitch: initialPitch,
    );
  }
}
