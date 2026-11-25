import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_app/main.dart';

void main() {
  testWidgets('KartaApp boots with Karta Navigation branding, single-destination planner, and zero Spotify/tolls',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KartaApp()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Karta Navigation'), findsOneWidget);
    expect(find.text('ROUTE · START TO DESTINATION'), findsOneWidget);
    expect(find.textContaining('George Town'), findsOneWidget);
    expect(find.textContaining('Petronas Twin Towers'), findsOneWidget);
    expect(find.text('PEN→KL→SG'), findsNothing);
    expect(find.text('SPOTIFY'), findsNothing);
    expect(find.text('Tolls & Class'), findsNothing);
    expect(find.text('Avoid Tolls'), findsNothing);
  });
}
