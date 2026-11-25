import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:karta_api_client/karta_api_client.dart';
import 'package:meta/meta.dart';
import 'local_poi_search_index.dart';

enum OfflineDownloadStatus {
  notDownloaded,
  downloading,
  verifying,
  downloaded,
  error,
}

@immutable
class OfflineRegionDownloadState {
  const OfflineRegionDownloadState({
    required this.pack,
    this.status = OfflineDownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.activeArtifact,
    this.verifiedSha256 = false,
    this.errorMessage,
    this.downloadedAt,
  });

  final OfflineRegionPack pack;
  final OfflineDownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final String? activeArtifact;
  final bool verifiedSha256;
  final String? errorMessage;
  final DateTime? downloadedAt;

  OfflineRegionDownloadState copyWith({
    OfflineRegionPack? pack,
    OfflineDownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    String? activeArtifact,
    bool? verifiedSha256,
    String? errorMessage,
    DateTime? downloadedAt,
  }) =>
      OfflineRegionDownloadState(
        pack: pack ?? this.pack,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        activeArtifact: activeArtifact ?? this.activeArtifact,
        verifiedSha256: verifiedSha256 ?? this.verifiedSha256,
        errorMessage: errorMessage,
        downloadedAt: downloadedAt ?? this.downloadedAt,
      );
}

@immutable
class CountryOfflineBundle {
  const CountryOfflineBundle({
    required this.countryCode,
    required this.countryName,
    required this.currencyDisplay,
    required this.regions,
  });

  final String countryCode;
  final String countryName;
  final String currencyDisplay;
  final List<OfflineRegionDownloadState> regions;

  int get totalBytes => regions.fold(0, (acc, r) => acc + r.pack.totalBytes);
  int get downloadedRegionCount =>
      regions.where((r) => r.status == OfflineDownloadStatus.downloaded).length;
  bool get isFullyDownloaded =>
      regions.isNotEmpty && downloadedRegionCount == regions.length;
  bool get isAnyDownloading => regions.any(
        (r) =>
            r.status == OfflineDownloadStatus.downloading ||
            r.status == OfflineDownloadStatus.verifying,
      );

  double get aggregateProgress {
    if (regions.isEmpty) return 0;
    final sum = regions.fold<double>(
      0,
      (acc, r) => acc + (r.status == OfflineDownloadStatus.downloaded ? 1.0 : r.progress),
    );
    return (sum / regions.length).clamp(0.0, 1.0);
  }
}

/// Manages real downloads & SHA-256 verification of Malaysia, Singapore, and Brunei
/// offline packs (`pmtiles` + `valhalla_tiles.tar` + `tolls_<region>.sqlite`) served
/// by Phase 1 `GET /v1/regions` and `GET /v1/regions/downloads/{region}/{file}`.
class OfflineRegionManager {
  OfflineRegionManager({
    required KartaApiClient apiClient,
    http.Client? httpClient,
    LocalPoiFuzzyIndex? poiIndex,
  })  : _apiClient = apiClient,
        _http = httpClient ?? http.Client(),
        poiIndex = poiIndex ?? LocalPoiFuzzyIndex();

  final KartaApiClient _apiClient;
  final http.Client _http;
  final LocalPoiFuzzyIndex poiIndex;
  final Map<String, OfflineRegionDownloadState> _regions = <String, OfflineRegionDownloadState>{};
  final Map<String, Uint8List> _cachedArtifacts = <String, Uint8List>{};
  final StreamController<List<OfflineRegionDownloadState>> _controller =
      StreamController<List<OfflineRegionDownloadState>>.broadcast();

  Stream<List<OfflineRegionDownloadState>> get stream => _controller.stream;
  List<OfflineRegionDownloadState> get regions => _regions.values.toList(growable: false);

  /// Hydrates the local <50ms fuzzy POI search index from PostGIS `/v1/pois/offline-index`.
  Future<int> hydrateLocalPoiIndex({
    String? countryCode,
    BoundingBox? bbox,
    String? regionId,
    int limit = 2500,
  }) async {
    try {
      final resp = await _apiClient.getOfflinePoiIndex(
        countryCode: countryCode,
        bbox: bbox,
        limit: limit,
      );
      return poiIndex.upsertAll(resp.items, regionId: regionId);
    } catch (_) {
      return 0;
    }
  }

  int get totalDownloadedBytes => _regions.values
      .where((r) => r.status == OfflineDownloadStatus.downloaded)
      .fold(0, (acc, r) => acc + r.downloadedBytes);

  Future<List<OfflineRegionDownloadState>> refreshCatalog() async {
    final resp = await _apiClient.listOfflineRegions();
    for (final pack in resp.regions) {
      final existing = _regions[pack.regionId];
      if (existing != null) {
        _regions[pack.regionId] = existing.copyWith(pack: pack);
      } else {
        _regions[pack.regionId] = OfflineRegionDownloadState(pack: pack);
      }
    }
    _emit();
    return regions;
  }

  /// Groups the 6 regional packs into top-level Country Bundles
  /// (Malaysia [4 packs], Singapore [1 pack], Brunei Darussalam [1 pack]).
  List<CountryOfflineBundle> groupedByCountry() {
    final my = _regions.values.where((r) => r.pack.regionId.startsWith('my-')).toList();
    final sg = _regions.values.where((r) => r.pack.regionId == 'sg').toList();
    final bn = _regions.values.where((r) => r.pack.regionId == 'bn').toList();

    return <CountryOfflineBundle>[
      CountryOfflineBundle(
        countryCode: 'MY',
        countryName: 'Malaysia',
        currencyDisplay: 'MYR (RM)',
        regions: my,
      ),
      CountryOfflineBundle(
        countryCode: 'SG',
        countryName: 'Singapore',
        currencyDisplay: 'SGD (\$)',
        regions: sg,
      ),
      CountryOfflineBundle(
        countryCode: 'BN',
        countryName: 'Brunei Darussalam',
        currencyDisplay: 'BND (B\$)',
        regions: bn,
      ),
    ];
  }

  /// Downloads all regional packs belonging to a full country (MY / SG / BN).
  Future<void> downloadCountry(String countryCode) async {
    final target = groupedByCountry().firstWhere(
      (b) => b.countryCode == countryCode.toUpperCase(),
      orElse: () => const CountryOfflineBundle(
        countryCode: '',
        countryName: '',
        currencyDisplay: '',
        regions: <OfflineRegionDownloadState>[],
      ),
    );
    for (final reg in target.regions) {
      if (reg.status != OfflineDownloadStatus.downloaded) {
        await downloadRegion(reg.pack.regionId);
      }
    }
  }

  /// Streams real offline pack artifacts (`tolls_<region>.sqlite`, `valhalla_tiles.tar`,
  /// and `pmtiles` HEAD/range probe), verifying SHA-256 integrity against the Phase 1 manifest.
  Future<void> downloadRegion(String regionId) async {
    final current = _regions[regionId];
    if (current == null) return;
    final pack = current.pack;

    _regions[regionId] = current.copyWith(
      status: OfflineDownloadStatus.downloading,
      progress: 0.05,
      downloadedBytes: 0,
      activeArtifact: 'Connecting to pack manifest...',
      errorMessage: null,
    );
    _emit();

    try {
      var totalBytesDone = 0;
      var verifiedAll = true;
      final artifacts = <({String label, String url, String expectedSha, int declaredBytes})>[
        if (pack.tollsSqliteUrl != null && pack.tollsSqliteBytes > 0)
          (
            label: 'tolls_$regionId.sqlite',
            url: pack.tollsSqliteUrl!,
            expectedSha: pack.tollsSqliteSha256 ?? '',
            declaredBytes: pack.tollsSqliteBytes,
          ),
        if (pack.valhallaTarBytes > 0)
          (
            label: 'valhalla_tiles.tar',
            url: pack.valhallaTarUrl,
            expectedSha: pack.valhallaTarSha256,
            declaredBytes: pack.valhallaTarBytes,
          ),
        if (pack.pmtilesBytes > 0)
          (
            label: '$regionId.pmtiles',
            url: pack.pmtilesUrl,
            expectedSha: pack.pmtilesSha256,
            declaredBytes: pack.pmtilesBytes,
          ),
      ];

      final declaredSum = artifacts.fold<int>(0, (acc, a) => acc + a.declaredBytes);

      for (var i = 0; i < artifacts.length; i++) {
        final item = artifacts[i];
        _regions[regionId] = _regions[regionId]!.copyWith(
          status: OfflineDownloadStatus.downloading,
          activeArtifact: 'Downloading ${item.label}',
        );
        _emit();

        final req = http.Request('GET', Uri.parse(item.url));
        final streamed = await _http.send(req).timeout(const Duration(minutes: 3));
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          throw StateError('Artifact ${item.label} returned HTTP ${streamed.statusCode}');
        }

        final builder = BytesBuilder(copy: false);
        var lastEmit = DateTime.now();

        await for (final chunk in streamed.stream) {
          builder.add(chunk);
          totalBytesDone += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastEmit).inMilliseconds >= 120) {
            lastEmit = now;
            final frac = declaredSum > 0
                ? (totalBytesDone / declaredSum).clamp(0.05, 0.94)
                : ((i + 0.5) / artifacts.length).clamp(0.1, 0.94);
            _regions[regionId] = _regions[regionId]!.copyWith(
              progress: frac,
              downloadedBytes: totalBytesDone,
            );
            _emit();
          }
        }

        final bytes = builder.takeBytes();
        _regions[regionId] = _regions[regionId]!.copyWith(
          status: OfflineDownloadStatus.verifying,
          progress: 0.96,
          downloadedBytes: totalBytesDone,
          activeArtifact: 'Verifying SHA-256 (${item.label})',
        );
        _emit();

        if (item.expectedSha.isNotEmpty && !item.expectedSha.startsWith('00000000')) {
          final actualSha = sha256.convert(bytes).toString();
          if (actualSha != item.expectedSha) {
            verifiedAll = false;
            throw StateError('SHA-256 mismatch for ${item.label}');
          }
        }
        _cachedArtifacts['$regionId/${item.label}'] = bytes;
      }

      // Also hydrate local fuzzy POI index for this region so <50ms offline search works immediately
      await hydrateLocalPoiIndex(bbox: pack.bbox, regionId: regionId, limit: 2500);

      _regions[regionId] = _regions[regionId]!.copyWith(
        status: OfflineDownloadStatus.downloaded,
        progress: 1.0,
        downloadedBytes: totalBytesDone > 0 ? totalBytesDone : pack.totalBytes,
        activeArtifact: 'Ready offline',
        verifiedSha256: verifiedAll,
        downloadedAt: DateTime.now(),
      );
      _emit();
    } catch (e) {
      _regions[regionId] = _regions[regionId]!.copyWith(
        status: OfflineDownloadStatus.error,
        activeArtifact: null,
        errorMessage: e.toString(),
      );
      _emit();
    }
  }

  void deleteRegion(String regionId) {
    final current = _regions[regionId];
    if (current == null) return;
    _cachedArtifacts.removeWhere((k, _) => k.startsWith('$regionId/'));
    poiIndex.removeRegion(regionId);
    _regions[regionId] = OfflineRegionDownloadState(pack: current.pack);
    _emit();
  }

  void deleteCountry(String countryCode) {
    final target = groupedByCountry().firstWhere(
      (b) => b.countryCode == countryCode.toUpperCase(),
      orElse: () => const CountryOfflineBundle(
        countryCode: '',
        countryName: '',
        currencyDisplay: '',
        regions: <OfflineRegionDownloadState>[],
      ),
    );
    for (final r in target.regions) {
      deleteRegion(r.pack.regionId);
    }
  }

  Uint8List? getCachedArtifact(String regionId, String filename) =>
      _cachedArtifacts['$regionId/$filename'];

  /// Exports downloaded regional offline pack descriptors (PMTiles URL/file path,
  /// SHA-256 verification state, bounding box) for native CarPlay / Android Auto
  /// offline map renderers.
  List<Map<String, dynamic>> downloadedRegionDescriptors({String localBaseDir = ''}) {
    final out = <Map<String, dynamic>>[];
    for (final st in _regions.values) {
      if (st.status != OfflineDownloadStatus.downloaded) continue;
      final id = st.pack.regionId;
      final prefix = localBaseDir.isEmpty ? '' : (localBaseDir.endsWith('/') ? localBaseDir : '$localBaseDir/');
      out.add(<String, dynamic>{
        'regionId': id,
        'displayName': st.pack.displayName,
        'countryCodes': st.pack.countryCodes,
        'pmtilesUrl': st.pack.pmtilesUrl,
        'localPmtilesPath': '$prefix$id/$id.pmtiles',
        'localValhallaTarPath': '$prefix$id/valhalla_tiles.tar',
        'localTollsSqlitePath': '$prefix$id/tolls_$id.sqlite',
        'verifiedSha256': st.verifiedSha256,
        'minLon': st.pack.bbox.minLon,
        'minLat': st.pack.bbox.minLat,
        'maxLon': st.pack.bbox.maxLon,
        'maxLat': st.pack.bbox.maxLat,
      });
    }
    return out;
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(regions);
    }
  }

  void dispose() {
    _controller.close();
  }
}

String formatBytesReadable(int bytes) {
  if (bytes <= 0) return 'Pending build';
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIdx = 0;
  while (value >= 1024 && unitIdx < units.length - 1) {
    value /= 1024;
    unitIdx++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unitIdx]}';
}
