import 'package:flutter/widgets.dart';

import 'karta_pointer_shield_stub.dart'
    if (dart.library.js_interop) 'karta_pointer_shield_web.dart' as impl;

/// Prevents pointer, click, and wheel events on Flutter Web from falling through
/// overlay UI (navigation rail, side panel, HUD cards, modals) into underlying
/// HTML platform views such as the MapLibre GL JS canvas (`#karta-maplibre-*`).
///
/// On non-web platforms (iOS, Android, macOS, Windows, Linux) and widget tests,
/// this renders [child] directly with zero overhead.
class KartaPointerShield extends StatelessWidget {
  const KartaPointerShield({
    super.key,
    required this.child,
    this.intercepting = true,
  });

  final Widget child;
  final bool intercepting;

  @override
  Widget build(BuildContext context) {
    if (!intercepting) return child;
    return impl.buildPointerShield(child: child);
  }
}
