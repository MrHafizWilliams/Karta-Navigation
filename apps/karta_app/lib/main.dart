import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_design_system/karta_design_system.dart';

import 'karta_shell.dart';
import 'state/lighting_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KartaApp()));
}

class KartaApp extends ConsumerWidget {
  const KartaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lighting = ref.watch(kartaLightingProvider);

    return MaterialApp(
      title: 'Karta Navigation',
      debugShowCheckedModeBanner: false,
      theme: KartaTheme.tropicalDaylight(),
      darkTheme: KartaTheme.dark(),
      themeMode: lighting.isDaylight ? ThemeMode.light : ThemeMode.dark,
      themeAnimationDuration: const Duration(milliseconds: 300),
      themeAnimationCurve: Curves.easeOutCubic,
      home: const KartaAppShell(),
    );
  }
}
