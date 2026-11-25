import 'package:meta/meta.dart';

@immutable
class Coordinate {
  const Coordinate({required this.lat, required this.lon});

  final double lat;
  final double lon;

  factory Coordinate.fromJson(Map<String, dynamic> json) => Coordinate(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lat': lat,
        'lon': lon,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coordinate &&
          (lat - other.lat).abs() < 1e-7 &&
          (lon - other.lon).abs() < 1e-7;

  @override
  int get hashCode => Object.hash(lat.toStringAsFixed(6), lon.toStringAsFixed(6));

  @override
  String toString() => 'Coordinate(${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)})';
}

@immutable
class BoundingBox {
  const BoundingBox({
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  });

  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
        minLon: (json['min_lon'] as num).toDouble(),
        minLat: (json['min_lat'] as num).toDouble(),
        maxLon: (json['max_lon'] as num).toDouble(),
        maxLat: (json['max_lat'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'min_lon': minLon,
        'min_lat': minLat,
        'max_lon': maxLon,
        'max_lat': maxLat,
      };
}

@immutable
class CurrencyAmount {
  const CurrencyAmount({
    required this.currencyCode,
    required this.amountMinor,
    required this.formatted,
  });

  final String currencyCode;
  final int amountMinor;
  final String formatted;

  factory CurrencyAmount.fromJson(Map<String, dynamic> json) => CurrencyAmount(
        currencyCode: json['currency_code'] as String,
        amountMinor: (json['amount_minor'] as num).toInt(),
        formatted: json['formatted'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'currency_code': currencyCode,
        'amount_minor': amountMinor,
        'formatted': formatted,
      };
}

@immutable
class CountryContext {
  const CountryContext({
    required this.isoA2,
    required this.name,
    required this.currencyCode,
    required this.currencySymbol,
    this.drivingSide = 'left',
    this.speedUnit = 'kmh',
    required this.timezoneIana,
  });

  final String isoA2;
  final String name;
  final String currencyCode;
  final String currencySymbol;
  final String drivingSide;
  final String speedUnit;
  final String timezoneIana;

  factory CountryContext.fromJson(Map<String, dynamic> json) => CountryContext(
        isoA2: (json['iso_a2'] as String).trim(),
        name: json['name'] as String,
        currencyCode: (json['currency_code'] as String).trim(),
        currencySymbol: json['currency_symbol'] as String,
        drivingSide: (json['driving_side'] as String?) ?? 'left',
        speedUnit: (json['speed_unit'] as String?) ?? 'kmh',
        timezoneIana: json['timezone_iana'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'iso_a2': isoA2,
        'name': name,
        'currency_code': currencyCode,
        'currency_symbol': currencySymbol,
        'driving_side': drivingSide,
        'speed_unit': speedUnit,
        'timezone_iana': timezoneIana,
      };
}
