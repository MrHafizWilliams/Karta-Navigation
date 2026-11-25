import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_design_system/karta_design_system.dart';
import 'package:karta_offline_routing/karta_offline_routing.dart';

import '../../state/karta_app_state.dart';

/// Offline Map Manager enabling 1-tap full-country downloads for Malaysia,
/// Singapore, and Brunei Darussalam (plus granular Malaysian sub-region packs)
/// backed directly by `GET /v1/regions` and SHA-256 verified artifacts.
class OfflineMapManagerPanel extends ConsumerWidget {
  const OfflineMapManagerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kartaPalette;
    final mgr = ref.watch(offlineRegionManagerProvider);
    final regionsAsync = ref.watch(offlineRegionsStreamProvider);
    final offlineMode = ref.watch(offlineModeEnabledProvider);

    final bundles = mgr.groupedByCountry();
    final totalDownloaded = mgr.totalDownloadedBytes;

    return KartaSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: KartaSpacing.radiusLg,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: Row(
              children: <Widget>[
                Icon(Icons.download_for_offline_rounded, color: palette.accentPrimary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Offline Map Manager',
                        style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                      ),
                      Text(
                        'PMTiles + Valhalla Graph + POIs · ${totalDownloaded > 0 ? formatBytesReadable(totalDownloaded) : '0 MB stored'}',
                        style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh manifest from karta-api',
                  constraints: const BoxConstraints(
                    minWidth: KartaSpacing.minTouchTarget,
                    minHeight: KartaSpacing.minTouchTarget,
                  ),
                  onPressed: () => mgr.refreshCatalog(),
                  icon: Icon(Icons.refresh_rounded, size: 20, color: palette.textSecondary),
                ),
              ],
            ),
          ),

          // Offline Mode Toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: offlineMode ? palette.accentPrimary : palette.borderSubtle,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    offlineMode ? Icons.airplanemode_active_rounded : Icons.cloud_done_rounded,
                    size: 18,
                    color: offlineMode ? palette.accentBright : palette.statusClear,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Offline Navigation Mode',
                          style: KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
                        ),
                        Text(
                          'Prefer local PMTiles & downloaded offline routing packs',
                          style:
                              KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: offlineMode,
                    activeThumbColor: palette.accentPrimary,
                    onChanged: (v) {
                      ref.read(offlineModeEnabledProvider.notifier).state = v;
                      ref.read(connectivityResilienceProvider).setManualOfflineOverride(v);
                    },
                  ),
                ],
              ),
            ),
          ),

          Divider(height: 1, color: palette.borderSubtle),

          Expanded(
            child: regionsAsync.when(
              data: (_) {
                if (mgr.regions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.cloud_off_rounded, size: 32, color: palette.textSecondary),
                          const SizedBox(height: 10),
                          Text(
                            'No regional manifests loaded yet.',
                            style:
                                KartaTypography.bodyPrimary.copyWith(color: palette.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => mgr.refreshCatalog(),
                            child: const Text('Retry GET /v1/regions'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: bundles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) => _CountryOfflineCard(
                    bundle: bundles[idx],
                    onDownloadCountry: () => mgr.downloadCountry(bundles[idx].countryCode),
                    onDeleteCountry: () => mgr.deleteCountry(bundles[idx].countryCode),
                    onDownloadRegion: mgr.downloadRegion,
                    onDeleteRegion: mgr.deleteRegion,
                  ),
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: palette.accentPrimary),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Error fetching /v1/regions: $err',
                    style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryOfflineCard extends StatelessWidget {
  const _CountryOfflineCard({
    required this.bundle,
    required this.onDownloadCountry,
    required this.onDeleteCountry,
    required this.onDownloadRegion,
    required this.onDeleteRegion,
  });

  final CountryOfflineBundle bundle;
  final VoidCallback onDownloadCountry;
  final VoidCallback onDeleteCountry;
  final ValueChanged<String> onDownloadRegion;
  final ValueChanged<String> onDeleteRegion;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.surfaceElevated.withValues(alpha: palette.isDaylight ? 0.92 : 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: bundle.isFullyDownloaded ? palette.statusClear : palette.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: palette.accentGlow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  bundle.countryCode,
                  style: KartaTypography.monoBadge.copyWith(color: palette.accentBright),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      bundle.countryName,
                      style: KartaTypography.sectionTitle.copyWith(color: palette.textPrimary),
                    ),
                    Text(
                      '${bundle.regions.length} ${bundle.regions.length == 1 ? 'pack' : 'sub-regions'} · ${formatBytesReadable(bundle.totalBytes)}',
                      style: KartaTypography.bodySecondary.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              if (bundle.isFullyDownloaded)
                IconButton(
                  tooltip: 'Remove ${bundle.countryName} offline data',
                  constraints: const BoxConstraints(
                    minWidth: KartaSpacing.minTouchTarget,
                    minHeight: KartaSpacing.minTouchTarget,
                  ),
                  onPressed: onDeleteCountry,
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: palette.statusAlert),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, KartaSpacing.minTouchTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    textStyle: KartaTypography.captionLabel.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: bundle.isAnyDownloading ? null : onDownloadCountry,
                  child: Text(bundle.isAnyDownloading ? 'Downloading...' : 'Download All'),
                ),
            ],
          ),
          if (bundle.isAnyDownloading) ...<Widget>[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: bundle.aggregateProgress,
              backgroundColor: palette.surfaceCard,
              color: palette.accentPrimary,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
          const SizedBox(height: 10),
          for (final reg in bundle.regions) ...<Widget>[
            _RegionPackTile(
              state: reg,
              onDownload: () => onDownloadRegion(reg.pack.regionId),
              onDelete: () => onDeleteRegion(reg.pack.regionId),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _RegionPackTile extends StatelessWidget {
  const _RegionPackTile({
    required this.state,
    required this.onDownload,
    required this.onDelete,
  });

  final OfflineRegionDownloadState state;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    final p = state.pack;
    final busy = state.status == OfflineDownloadStatus.downloading ||
        state.status == OfflineDownloadStatus.verifying;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      p.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: KartaTypography.bodyPrimary.copyWith(
                        fontSize: 12.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'v${p.dataVersion} · ${formatBytesReadable(p.totalBytes)}'
                      '${state.verifiedSha256 ? ' · SHA-256 Verified' : ''}',
                      style: KartaTypography.bodySecondary.copyWith(
                        fontSize: 11.5,
                        color:
                            state.verifiedSha256 ? palette.statusClear : palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (state.status == OfflineDownloadStatus.downloaded)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.verified_rounded, size: 18, color: palette.statusClear),
                    IconButton(
                      constraints: const BoxConstraints(
                        minWidth: KartaSpacing.minTouchTarget,
                        minHeight: KartaSpacing.minTouchTarget,
                      ),
                      onPressed: onDelete,
                      icon: Icon(Icons.close_rounded, size: 18, color: palette.textSecondary),
                    ),
                  ],
                )
              else if (busy)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    value: state.progress > 0.05 ? state.progress : null,
                    strokeWidth: 2,
                    color: palette.accentPrimary,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Download ${p.regionId}',
                  constraints: const BoxConstraints(
                    minWidth: KartaSpacing.minTouchTarget,
                    minHeight: KartaSpacing.minTouchTarget,
                  ),
                  onPressed: onDownload,
                  icon: Icon(Icons.download_rounded, size: 20, color: palette.accentBright),
                ),
            ],
          ),
          if (busy && state.activeArtifact != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              '${state.activeArtifact} (${(state.progress * 100).round()}%)',
              style: KartaTypography.monoBadge.copyWith(
                fontSize: 11,
                color: palette.accentBright,
              ),
            ),
          ],
          if (state.errorMessage != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              state.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: KartaTypography.bodySecondary.copyWith(
                fontSize: 11,
                color: palette.statusAlert,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
