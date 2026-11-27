import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_app/main.dart';

void main() {
  testWidgets('Desktop layout renders left nav rail, Driver Studio, and Offline Map Manager',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
    await tester.pump(const Duration(milliseconds: 120));

    // Switch to 3D Vehicle & Pin Studio via desktop nav rail
    await tester.tap(find.text('Vehicle'));
    await tester.pumpAndSettle();

    expect(find.text('Karta Driver Studio'), findsOneWidget);
    expect(find.text('ACTIVE 2D NAVIGATION ARROW'), findsOneWidget);
    expect(find.text('Karta 2D Arrow'), findsWidgets);
    expect(find.text('Sport Chevron'), findsOneWidget);

    await tester.tap(find.text('Sport Chevron'));
    await tester.pumpAndSettle();

    // Switch to Offline Map Manager via desktop nav rail
    await tester.tap(find.text('Offline'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Offline Map Manager'), findsOneWidget);
  });

  testWidgets('Smartphone compact layout (390x844) renders distinct bottom tab bar without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Vehicle'), findsOneWidget);
    // Compact smartphone layout uses bottom bar, NOT persistent left nav rail
    expect(find.text('KARTA'), findsNothing);
    expect(find.text('SPOTIFY'), findsNothing);
    // Smartphone explore bar starts minimized so users see the full map immediately
    expect(find.byKey(const ValueKey<String>('karta-mobile-explore-minimized')), findsOneWidget);
  });

  testWidgets('Tablet medium layout (820x1180) renders left nav rail, Google Maps floating search bar, and expandable Directions drawer',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp(enableIntroAnimation: false)));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey<String>('karta-floating-search-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('karta-directions-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('karta-header-account-btn')), findsOneWidget);
    expect(find.text('KARTA'), findsOneWidget);
    expect(find.text('SPOTIFY'), findsNothing);

    // Tapping Directions opens the full Start -> Destination drawer
    await tester.tap(find.byKey(const ValueKey<String>('karta-directions-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Karta Navigation'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('karta-close-directions-btn')), findsOneWidget);

    // Tapping Close returns cleanly to the Google Maps floating search bar
    await tester.tap(find.byKey(const ValueKey<String>('karta-close-directions-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('karta-floating-search-bar')), findsOneWidget);
  });
}
