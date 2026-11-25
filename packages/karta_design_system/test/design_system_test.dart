import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_design_system/karta_design_system.dart';

void main() {
  test('KartaColors strictly matches GEMINI.md palette', () {
    expect(KartaColors.backgroundPrimary, equals(const Color(0xFF0D0F12)));
    expect(KartaColors.surfaceCard, equals(const Color(0xFF181C22)));
    expect(KartaColors.accentPrimary, equals(const Color(0xFF5B9A94)));
    expect(KartaColors.textPrimary, equals(const Color(0xFFF4F6F8)));
    expect(KartaColors.textSecondary, equals(const Color(0xFF8E96A0)));
  });

  test('KartaPalette provides distinct Obsidian Night & High-Glare Tropical Daylight tokens', () {
    expect(KartaPalette.obsidianNight.isDaylight, isFalse);
    expect(KartaPalette.obsidianNight.backgroundPrimary, equals(const Color(0xFF0D0F12)));
    expect(KartaPalette.obsidianNight.accentPrimary, equals(const Color(0xFF5B9A94)));

    expect(KartaPalette.tropicalDaylight.isDaylight, isTrue);
    expect(KartaPalette.tropicalDaylight.backgroundPrimary, equals(const Color(0xFFF5F2EB)));
    expect(KartaPalette.tropicalDaylight.surfaceCard, equals(const Color(0xFFFCFBF8)));
    expect(KartaPalette.tropicalDaylight.accentPrimary, equals(const Color(0xFF2F756F)));
    expect(KartaPalette.tropicalDaylight.textPrimary, equals(const Color(0xFF11161C)));
    expect(KartaSpacing.minDrivingTouchTarget, equals(60.0));
  });

  test('KartaBreakpoints classifies compact, medium, and expanded viewports', () {
    expect(KartaBreakpoints.resolve(390), equals(KartaViewportClass.compact));
    expect(KartaBreakpoints.resolve(820), equals(KartaViewportClass.medium));
    expect(KartaBreakpoints.resolve(1440), equals(KartaViewportClass.expanded));
  });

  test('KartaHighwaySignboard classifies MY/SG/BN Expressways (Green) vs Federal/Municipal (Blue)', () {
    expect(
      KartaHighwaySignboard.classifyRoad(roadRef: 'E1', highwayClass: 'motorway'),
      equals(KartaSignboardType.expresswayGreen),
    );
    expect(
      KartaHighwaySignboard.classifyRoad(roadRef: 'CTE', highwayClass: 'trunk'),
      equals(KartaSignboardType.expresswayGreen),
    );
    expect(
      KartaHighwaySignboard.classifyRoad(instruction: 'Keep right onto Lebuhraya Utara-Selatan'),
      equals(KartaSignboardType.expresswayGreen),
    );
    expect(
      KartaHighwaySignboard.classifyRoad(roadRef: 'FT1', highwayClass: 'primary', instruction: 'Turn left onto Jalan Ampang'),
      equals(KartaSignboardType.federalBlue),
    );
  });

  testWidgets('KartaLogoMark, KartaManeuverIcon, and KartaPaymentBadge render cleanly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KartaTheme.dark(),
        home: const Scaffold(
          body: Row(
            children: <Widget>[
              KartaLogoMark(size: 32),
              KartaManeuverIcon(valhallaType: 10, size: 32),
              KartaLaneArrow(laneSpec: 'through;right', isRecommended: true),
              KartaPaymentBadge(methodCode: 'RFID'),
              KartaPaymentBadge(methodCode: 'ERP2_OBU'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('RFID'), findsOneWidget);
    expect(find.text('ERP 2.0'), findsOneWidget);
  });

  testWidgets('KartaHighwaySignboard and KartaAnimatedLaneGuidanceStrip render in Tropical Daylight',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KartaTheme.tropicalDaylight(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                KartaHighwaySignboard(
                  valhallaManeuverType: 18,
                  distanceText: '850 m',
                  primaryInstruction: 'Take exit toward Jambatan Pulau Pinang',
                  roadRef: 'E1',
                  highwayClass: 'motorway',
                  countryCode: 'MY',
                  isTollRoad: true,
                  exitLabel: 'EXIT 161',
                ),
                SizedBox(height: 8),
                KartaAnimatedLaneGuidanceStrip(
                  lanes: <KartaAnimatedLaneSpec>[
                    KartaAnimatedLaneSpec(laneSpec: 'through', isRecommended: false),
                    KartaAnimatedLaneSpec(laneSpec: 'through;right', isRecommended: true),
                    KartaAnimatedLaneSpec(laneSpec: 'right', isRecommended: true),
                  ],
                  tollBannerText: 'TOLL IN 450 m · Plaza Tol Jambatan Pulau Pinang',
                  tollPaymentCodes: <String>['RFID', 'SMARTTAG', 'TNG_CARD'],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('850 m'), findsOneWidget);
    expect(find.text('E1'), findsOneWidget);
    expect(find.text('EXIT 161'), findsOneWidget);
    expect(find.text('EXPRESSWAY'), findsOneWidget);
    expect(find.text('TOLL EXPY'), findsNothing);
    expect(find.text('RFID'), findsOneWidget);
    expect(find.text('SmartTAG'), findsOneWidget);
  });

  testWidgets('KartaSpringBottomSheet transitions smoothly through collapsed -> half -> expanded',
      (WidgetTester tester) async {
    final detents = <KartaSheetDetent>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: KartaTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: KartaSpringBottomSheet(
              onDetentChanged: detents.add,
              collapsedChild: const Text('ETA 14:25 · 12 min'),
              halfChild: const Text('HALF_CONTROLS_HUB'),
              expandedChild: const Text('FULL_TURN_BY_TURN_LIST'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('ETA 14:25 · 12 min'), findsOneWidget);
    expect(find.text('HALF_CONTROLS_HUB'), findsNothing);
    expect(find.text('FULL_TURN_BY_TURN_LIST'), findsNothing);

    // Tap handle -> spring expands to Half detent
    await tester.tap(find.byKey(const ValueKey<String>('karta-sheet-handle')));
    await tester.pumpAndSettle();
    expect(detents.last, equals(KartaSheetDetent.half));
    expect(find.text('HALF_CONTROLS_HUB'), findsOneWidget);

    // Tap handle again -> spring expands to Full detent
    await tester.tap(find.byKey(const ValueKey<String>('karta-sheet-handle')));
    await tester.pumpAndSettle();
    expect(detents.last, equals(KartaSheetDetent.expanded));
    expect(find.text('FULL_TURN_BY_TURN_LIST'), findsOneWidget);

    // Tap handle again -> collapses cleanly back to ETA pill
    await tester.tap(find.byKey(const ValueKey<String>('karta-sheet-handle')));
    await tester.pumpAndSettle();
    expect(detents.last, equals(KartaSheetDetent.collapsed));
  });
}
