import 'package:karta_api_client/karta_api_client.dart';

/// Canonical regional currency formatting matching GEMINI.md and Phase 1 `currency.py`:
///   MY -> MYR -> `RM 14.80`
///   SG -> SGD -> `$2.00`
///   BN -> BND -> `B$3.00`
abstract final class RegionalCurrencyFormatter {
  static const Map<String, ({String code, String symbol, bool space})> _byCountry = {
    'MY': (code: 'MYR', symbol: 'RM', space: true),
    'SG': (code: 'SGD', symbol: '\$', space: false),
    'BN': (code: 'BND', symbol: 'B\$', space: false),
  };

  static const Map<String, ({String symbol, bool space})> _byCurrency = {
    'MYR': (symbol: 'RM', space: true),
    'SGD': (symbol: '\$', space: false),
    'BND': (symbol: 'B\$', space: false),
  };

  static String currencyCodeForCountry(String isoA2) {
    return _byCountry[isoA2.toUpperCase()]?.code ?? 'MYR';
  }

  static String currencySymbolForCountry(String isoA2) {
    return _byCountry[isoA2.toUpperCase()]?.symbol ?? 'RM';
  }

  static String formatMinor(String currencyCode, int amountMinor) {
    final code = currencyCode.toUpperCase().trim();
    final spec = _byCurrency[code] ?? (symbol: code, space: true);
    final major = (amountMinor / 100.0).toStringAsFixed(2);
    return '${spec.symbol}${spec.space ? ' ' : ''}$major';
  }

  static String formatMultiCurrency(List<CurrencyAmount> totals) {
    if (totals.isEmpty) return 'Free';
    return totals.map((e) => e.formatted).join(' + ');
  }

  static String formatDistance(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000.0;
      return km >= 100 ? '${km.round()} km' : '${km.toStringAsFixed(1)} km';
    }
    if (meters >= 100) {
      return '${(meters / 10).round() * 10} m';
    }
    return '${meters.round()} m';
  }

  static String formatDuration(double seconds) {
    final totalMin = (seconds / 60.0).round();
    if (totalMin < 1) return '< 1 min';
    if (totalMin < 60) return '$totalMin min';
    final hrs = totalMin ~/ 60;
    final rem = totalMin % 60;
    return rem == 0 ? '${hrs}h' : '${hrs}h ${rem}m';
  }
}
