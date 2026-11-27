import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_design_system/karta_design_system.dart';

import 'karta_shell.dart';
import 'state/language_providers.dart';
import 'state/lighting_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KartaApp()));
}

class KartaApp extends ConsumerStatefulWidget {
  const KartaApp({
    super.key,
    this.enableIntroAnimation = true,
  });

  /// Shows the branded Karta launch intro animation across all devices
  /// (smartphones, tablets, desktops, Web, automotive) while the map preloads.
  final bool enableIntroAnimation;

  @override
  ConsumerState<KartaApp> createState() => _KartaAppState();
}

class _KartaAppState extends ConsumerState<KartaApp> {
  late bool _showIntro;

  @override
  void initState() {
    super.initState();
    _showIntro = widget.enableIntroAnimation;
  }

  @override
  Widget build(BuildContext context) {
    final lighting = ref.watch(kartaLightingProvider);
    final language = ref.watch(kartaLanguageProvider);
    final l10n = KartaStrings.of(language);

    return KartaL10nScope(
      language: language,
      child: MaterialApp(
        title: l10n.appTitle,
        debugShowCheckedModeBanner: false,
        theme: KartaTheme.tropicalDaylight(),
        darkTheme: KartaTheme.dark(),
        themeMode: lighting.isDaylight ? ThemeMode.light : ThemeMode.dark,
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeOutCubic,
        home: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const KartaAppShell(),
            if (_showIntro)
              KartaIntroSplashOverlay(
                onFinished: () {
                  if (mounted) {
                    setState(() => _showIntro = false);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
