import 'package:flutter/material.dart';
import '../tokens/karta_palette.dart';
import '../tokens/karta_typography.dart';

enum KartaConnectivityVisualMode {
  online,
  offlineRoutingActive,
  syncingQuietly,
}

/// Subtle, non-intrusive status pill for tunnels and rural dead zones.
/// Adapts seamlessly to both Obsidian Night and High-Glare Tropical Daylight.
class KartaOfflineStatusPill extends StatelessWidget {
  const KartaOfflineStatusPill({
    super.key,
    required this.mode,
    this.regionLabel,
    this.pendingSyncCount = 0,
    this.compact = false,
  });

  final KartaConnectivityVisualMode mode;
  final String? regionLabel;
  final int pendingSyncCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.kartaPalette;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: mode == KartaConnectivityVisualMode.online
          ? const SizedBox.shrink(key: ValueKey<String>('conn-online'))
          : _buildPill(palette),
    );
  }

  Widget _buildPill(KartaPalette palette) {
    final isSyncing = mode == KartaConnectivityVisualMode.syncingQuietly;
    final dotColor = isSyncing ? palette.accentBright : palette.accentPrimary;
    final headline = isSyncing ? 'Syncing Quietly…' : 'Offline Routing Active';
    final subParts = <String>[
      if (!isSyncing && regionLabel != null && regionLabel!.isNotEmpty) regionLabel!,
      if (pendingSyncCount > 0) '$pendingSyncCount queued',
    ];

    return Container(
      key: ValueKey<String>('conn-${mode.name}-$pendingSyncCount'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: palette.hudDeepGlass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dotColor.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isSyncing)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: dotColor,
              ),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 7),
          Text(
            headline,
            style: KartaTypography.monoBadge.copyWith(
              fontSize: compact ? 9.5 : 10.5,
              color: palette.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          if (!compact && subParts.isNotEmpty) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              '· ${subParts.join(' · ')}',
              style: KartaTypography.bodySecondary.copyWith(
                fontSize: 10,
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
