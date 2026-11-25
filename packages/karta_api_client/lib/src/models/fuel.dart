import 'package:meta/meta.dart';
import 'common.dart';

enum FuelGrade {
  ron95('RON95', 'RON95', 'MY'),
  ron97('RON97', 'RON97', 'MY'),
  dieselB10('DIESEL_B10', 'Diesel', 'MY'),
  dieselEuro5('DIESEL_EURO5', 'Euro5 Diesel', 'MY'),
  octane92('OCTANE_92', '92', 'SG'),
  octane95('OCTANE_95', '95', 'SG'),
  octane98('OCTANE_98', '98', 'SG'),
  dieselSg('DIESEL_SG', 'Diesel', 'SG'),
  ron97Bn('RON97_BN', 'RON97', 'BN'),
  ron92Bn('RON92_BN', 'RON92', 'BN'),
  dieselBn('DIESEL_BN', 'Diesel', 'BN');

  const FuelGrade(this.wireValue, this.shortLabel, this.countryCode);

  final String wireValue;
  final String shortLabel;
  final String countryCode;

  static List<FuelGrade> gradesForCountry(String isoA2) {
    final cc = isoA2.toUpperCase();
    final filtered = FuelGrade.values.where((g) => g.countryCode == cc).toList();
    return filtered.isNotEmpty
        ? filtered
        : const <FuelGrade>[FuelGrade.ron95, FuelGrade.ron97, FuelGrade.dieselB10];
  }

  static FuelGrade fromWire(String raw) {
    for (final g in FuelGrade.values) {
      if (g.wireValue == raw) return g;
    }
    return FuelGrade.ron95;
  }
}

@immutable
class FuelGradeQuote {
  const FuelGradeQuote({
    required this.fuelGrade,
    required this.priceMinor,
    required this.currencyCode,
    required this.formattedPrice,
    this.isSubsidized = false,
    this.source = 'official_baseline',
    this.confirmations = 1,
    required this.reportedAt,
  });

  final FuelGrade fuelGrade;
  final int priceMinor;
  final String currencyCode;
  final String formattedPrice;
  final bool isSubsidized;
  final String source;
  final int confirmations;
  final DateTime reportedAt;

  factory FuelGradeQuote.fromJson(Map<String, dynamic> json) => FuelGradeQuote(
        fuelGrade: FuelGrade.fromWire(json['fuel_grade'] as String),
        priceMinor: (json['price_minor'] as num).toInt(),
        currencyCode: json['currency_code'] as String,
        formattedPrice: json['formatted_price'] as String,
        isSubsidized: (json['is_subsidized'] as bool?) ?? false,
        source: (json['source'] as String?) ?? 'official_baseline',
        confirmations: (json['confirmations'] as num?)?.toInt() ?? 1,
        reportedAt: DateTime.parse(json['reported_at'] as String),
      );
}

@immutable
class FuelStationComparison {
  const FuelStationComparison({
    required this.poiId,
    required this.name,
    this.brand,
    required this.countryCode,
    required this.coordinate,
    this.openingHours,
    this.distanceAlongRouteKm,
    this.detourMeters = 0.0,
    this.detourMinutes = 0,
    required this.selectedGrade,
    required this.selectedPriceMinor,
    required this.selectedFormattedPrice,
    required this.currencyCode,
    this.isCheapest = false,
    this.prices = const <FuelGradeQuote>[],
  });

  final int poiId;
  final String name;
  final String? brand;
  final String countryCode;
  final Coordinate coordinate;
  final String? openingHours;
  final double? distanceAlongRouteKm;
  final double detourMeters;
  final int detourMinutes;
  final FuelGrade selectedGrade;
  final int selectedPriceMinor;
  final String selectedFormattedPrice;
  final String currencyCode;
  final bool isCheapest;
  final List<FuelGradeQuote> prices;

  factory FuelStationComparison.fromJson(Map<String, dynamic> json) => FuelStationComparison(
        poiId: (json['poi_id'] as num).toInt(),
        name: json['name'] as String,
        brand: json['brand'] as String?,
        countryCode: (json['country_code'] as String?) ?? 'MY',
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
        openingHours: json['opening_hours'] as String?,
        distanceAlongRouteKm: (json['distance_along_route_km'] as num?)?.toDouble(),
        detourMeters: (json['detour_meters'] as num?)?.toDouble() ?? 0.0,
        detourMinutes: (json['detour_minutes'] as num?)?.toInt() ?? 0,
        selectedGrade: FuelGrade.fromWire(json['selected_grade'] as String),
        selectedPriceMinor: (json['selected_price_minor'] as num).toInt(),
        selectedFormattedPrice: json['selected_formatted_price'] as String,
        currencyCode: json['currency_code'] as String,
        isCheapest: (json['is_cheapest'] as bool?) ?? false,
        prices: (json['prices'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => FuelGradeQuote.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class FuelComparisonResponse {
  const FuelComparisonResponse({
    required this.countryCode,
    required this.fuelGrade,
    this.cheapestPoiId,
    this.cheapestFormattedPrice,
    required this.count,
    required this.stations,
  });

  final String countryCode;
  final FuelGrade fuelGrade;
  final int? cheapestPoiId;
  final String? cheapestFormattedPrice;
  final int count;
  final List<FuelStationComparison> stations;

  factory FuelComparisonResponse.fromJson(Map<String, dynamic> json) => FuelComparisonResponse(
        countryCode: (json['country_code'] as String?) ?? 'MY',
        fuelGrade: FuelGrade.fromWire(json['fuel_grade'] as String),
        cheapestPoiId: (json['cheapest_poi_id'] as num?)?.toInt(),
        cheapestFormattedPrice: json['cheapest_formatted_price'] as String?,
        count: (json['count'] as num).toInt(),
        stations: (json['stations'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => FuelStationComparison.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
