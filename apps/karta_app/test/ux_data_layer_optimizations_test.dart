import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_app/features/routing/route_comparison_panel.dart';
import 'package:karta_app/state/karta_app_state.dart';
import 'package:karta_design_system/karta_design_system.dart';

RouteResponse _buildSampleDifferentiatedResponse() {
  const plusBadge = TollBadge(
    badgeId: 'MY-PLUS-SKUDAI:1015',
    label: 'PLUS Highway',
    paymentLabel: "Touch 'n Go RFID",
    badgeKind: 'plus_highway',
    countryCode: 'MY',
    gantryName: 'Plaza Tol Skudai',
    entryGantryName: 'Plaza Tol Sungai Besi',
    charge: CurrencyAmount(currencyCode: 'MYR', amountMinor: 3444, formatted: 'RM 34.44'),
    acceptedPayments: <PaymentMethod>[PaymentMethod.rfid, PaymentMethod.tngCard],
    crossingTimeLocal: '10:15 MYT',
  );
  const erpBadge = TollBadge(
    badgeId: 'SG-ERP-31:0835',
    label: 'Singapore ERP',
    paymentLabel: 'Singapore ERP 2.0',
    badgeKind: 'sg_erp',
    countryCode: 'SG',
    gantryName: 'CTE Southbound before Braddell',
    charge: CurrencyAmount(currencyCode: 'SGD', amountMinor: 300, formatted: '\$3.00'),
    acceptedPayments: <PaymentMethod>[PaymentMethod.erp2Obu],
    crossingTimeLocal: '08:35 SGT',
  );

  return RouteResponse(
    departureTime: DateTime(2026, 11, 23, 7, 45),
    routes: const <CandidateRoute>[
      CandidateRoute(
        routeIndex: 0,
        profileUsed: 'drive_fastest',
        summaryLabel: 'Fastest • 38 min',
        uxPrimaryTag: 'Fastest • 38 min',
        uxBadgeKind: 'fastest',
        turnCount: 12,
        primaryCorridorName: 'via PLUS E2',
        distanceKm: 42.0,
        durationSeconds: 38 * 60.0,
        hasTollRoads: true,
        hasHighways: true,
        countriesCrossed: <String>['MY', 'SG'],
        legs: <RouteLeg>[],
        tolls: TollSummary(
          hasTolls: true,
          gantryBadges: <TollBadge>[plusBadge, erpBadge],
          totalsByCurrency: <CurrencyAmount>[
            CurrencyAmount(currencyCode: 'MYR', amountMinor: 3444, formatted: 'RM 34.44'),
            CurrencyAmount(currencyCode: 'SGD', amountMinor: 300, formatted: '\$3.00'),
          ],
          displayTotal: 'RM 34.44 + \$3.00',
        ),
      ),
      CandidateRoute(
        routeIndex: 1,
        profileUsed: 'drive_avoid_tolls',
        summaryLabel: 'Cheapest Toll • Save RM 4.20',
        uxPrimaryTag: 'Cheapest Toll • Save RM 4.20',
        uxBadgeKind: 'cheapest_toll',
        turnCount: 8,
        primaryCorridorName: 'via Federal Route 1',
        distanceKm: 45.2,
        durationSeconds: 44 * 60.0,
        hasTollRoads: false,
        hasHighways: false,
        countriesCrossed: <String>['MY'],
        legs: <RouteLeg>[],
        tolls: TollSummary(hasTolls: false, displayTotal: 'Free'),
      ),
    ],
  );
}

class _SeededRoutePlannerNotifier extends RoutePlannerNotifier {
  _SeededRoutePlannerNotifier(super.ref, RouteResponse seeded) {
    state = state.copyWith(routeResponse: seeded, selectedRouteIndex: 0);
  }
}

void main() {
  testWidgets('KartaOfflineStatusPill renders subtle Offline Routing Active & collapses when online', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KartaTheme.dark(),
        home: const Scaffold(
          body: Column(
            children: <Widget>[
              KartaLogoMark(size: 32),
              KartaOfflineStatusPill(
                mode: KartaConnectivityVisualMode.offlineRoutingActive,
                regionLabel: 'Malaysia',
                pendingSyncCount: 2,
              ),
              KartaOfflineStatusPill(
                mode: KartaConnectivityVisualMode.syncingQuietly,
              ),
              KartaOfflineStatusPill(
                mode: KartaConnectivityVisualMode.online,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Offline Routing Active'), findsOneWidget);
    expect(find.text('Syncing Quietly…'), findsOneWidget);
    expect(find.textContaining('No Internet'), findsNothing);
    expect(find.byType(KartaLogoMark), findsOneWidget);
  });

  testWidgets('RouteComparisonDeck displays scannable single-destination UX labels with zero toll badges', (tester) async {
    final seeded = _buildSampleDifferentiatedResponse();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          routePlannerProvider.overrideWith((ref) => _SeededRoutePlannerNotifier(ref, seeded)),
        ],
        child: MaterialApp(
          theme: KartaTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: RouteComparisonDeck(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('ROUTE OPTIONS (2)'), findsOneWidget);
    expect(find.text('Fastest • 38 min'), findsOneWidget);
    expect(find.text('via PLUS E2'), findsOneWidget);
    expect(find.text('via Federal Route 1'), findsOneWidget);
    // Toll-worded backend tags are sanitized and itemized toll fees/badges are completely omitted
    expect(find.textContaining('Cheapest Toll'), findsNothing);
    expect(find.text('PLUS Highway'), findsNothing);
    expect(find.text('Singapore ERP'), findsNothing);
    expect(find.textContaining("Touch 'n Go RFID"), findsNothing);
    expect(find.text('Lane & Receipt'), findsNothing);
    expect(find.textContaining('RM 34.44'), findsNothing);
  });
}
