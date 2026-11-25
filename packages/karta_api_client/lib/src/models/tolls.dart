import 'package:meta/meta.dart';
import 'common.dart';

enum PaymentMethod {
  tngCard('TNG_CARD', 'Touch \'n Go'),
  smartTag('SMARTTAG', 'SmartTAG'),
  rfid('RFID', 'MyRFID'),
  openPaymentCard('OPEN_PAYMENT_CARD', 'Debit / Credit'),
  anprJustGo('ANPR_JUSTGO', 'ANPR JustGo'),
  erpIu('ERP_IU', 'SG ERP IU'),
  erp2Obu('ERP2_OBU', 'SG ERP 2.0 OBU'),
  cash('CASH', 'Cash'),
  bruneiTollCard('BRUNEI_TOLL_CARD', 'Brunei Toll Card');

  const PaymentMethod(this.wireValue, this.displayName);

  final String wireValue;
  final String displayName;

  static PaymentMethod fromWire(String raw) {
    for (final m in PaymentMethod.values) {
      if (m.wireValue == raw) return m;
    }
    return PaymentMethod.tngCard;
  }
}

enum VehicleProfile {
  car('car', 'Car / SUV (Class 1)'),
  motorcycle('motorcycle', 'Motorcycle'),
  taxi('taxi', 'Taxi'),
  van2Axle('van_2axle', 'Van / 2-Axle'),
  truck3Axle('truck_3axle', 'Heavy Truck 3+ Axle'),
  bus('bus', 'Bus / Coach');

  const VehicleProfile(this.wireValue, this.displayName);

  final String wireValue;
  final String displayName;

  static VehicleProfile fromWire(String raw) {
    for (final v in VehicleProfile.values) {
      if (v.wireValue == raw) return v;
    }
    return VehicleProfile.car;
  }
}

@immutable
class TollLaneGuidance {
  const TollLaneGuidance({required this.lane, required this.methods});

  final int lane;
  final List<PaymentMethod> methods;

  factory TollLaneGuidance.fromJson(Map<String, dynamic> json) => TollLaneGuidance(
        lane: (json['lane'] as num).toInt(),
        methods: (json['methods'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => PaymentMethod.fromWire(e as String))
            .toList(),
      );
}

@immutable
class TollBadge {
  const TollBadge({
    required this.badgeId,
    required this.label,
    required this.paymentLabel,
    required this.badgeKind,
    required this.countryCode,
    required this.gantryName,
    this.entryGantryName,
    required this.charge,
    this.acceptedPayments = const <PaymentMethod>[],
    this.crossingTimeLocal,
  });

  final String badgeId;
  final String label;
  final String paymentLabel;
  final String badgeKind;
  final String countryCode;
  final String gantryName;
  final String? entryGantryName;
  final CurrencyAmount charge;
  final List<PaymentMethod> acceptedPayments;
  final String? crossingTimeLocal;

  factory TollBadge.fromJson(Map<String, dynamic> json) => TollBadge(
        badgeId: (json['badge_id'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        paymentLabel: (json['payment_label'] as String?) ?? '',
        badgeKind: (json['badge_kind'] as String?) ?? 'urban_expressway',
        countryCode: ((json['country_code'] as String?) ?? 'MY').trim(),
        gantryName: (json['gantry_name'] as String?) ?? '',
        entryGantryName: json['entry_gantry_name'] as String?,
        charge: CurrencyAmount.fromJson(json['charge'] as Map<String, dynamic>),
        acceptedPayments: (json['accepted_payments'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => PaymentMethod.fromWire(e as String))
            .toList(),
        crossingTimeLocal: json['crossing_time_local'] as String?,
      );
}

@immutable
class TollChargeItem {
  const TollChargeItem({
    required this.gantryId,
    required this.corridorId,
    required this.corridorName,
    required this.systemType,
    required this.countryCode,
    required this.gantryName,
    this.entryGantryId,
    this.entryGantryName,
    required this.estimatedCrossingTime,
    required this.coordinate,
    required this.charge,
    required this.acceptedPayments,
    this.laneLayout = const <TollLaneGuidance>[],
    this.paymentCompatible = true,
    this.warnings = const <String>[],
    this.isEstimated = false,
    this.badge,
  });

  final String gantryId;
  final String corridorId;
  final String corridorName;
  final String systemType;
  final String countryCode;
  final String gantryName;
  final String? entryGantryId;
  final String? entryGantryName;
  final DateTime estimatedCrossingTime;
  final Coordinate coordinate;
  final CurrencyAmount charge;
  final List<PaymentMethod> acceptedPayments;
  final List<TollLaneGuidance> laneLayout;
  final bool paymentCompatible;
  final List<String> warnings;
  final bool isEstimated;
  final TollBadge? badge;

  factory TollChargeItem.fromJson(Map<String, dynamic> json) => TollChargeItem(
        gantryId: json['gantry_id'] as String,
        corridorId: json['corridor_id'] as String,
        corridorName: json['corridor_name'] as String,
        systemType: json['system_type'] as String,
        countryCode: (json['country_code'] as String).trim(),
        gantryName: json['gantry_name'] as String,
        entryGantryId: json['entry_gantry_id'] as String?,
        entryGantryName: json['entry_gantry_name'] as String?,
        estimatedCrossingTime: DateTime.parse(json['estimated_crossing_time'] as String),
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
        charge: CurrencyAmount.fromJson(json['charge'] as Map<String, dynamic>),
        acceptedPayments: (json['accepted_payments'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => PaymentMethod.fromWire(e as String))
            .toList(),
        laneLayout: (json['lane_layout'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => TollLaneGuidance.fromJson(e as Map<String, dynamic>))
            .toList(),
        paymentCompatible: (json['payment_compatible'] as bool?) ?? true,
        warnings: (json['warnings'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e as String)
            .toList(),
        isEstimated: (json['is_estimated'] as bool?) ?? false,
        badge: json['badge'] != null
            ? TollBadge.fromJson(json['badge'] as Map<String, dynamic>)
            : null,
      );
}

@immutable
class TollSummary {
  const TollSummary({
    required this.hasTolls,
    this.items = const <TollChargeItem>[],
    this.gantryBadges = const <TollBadge>[],
    this.totalsByCurrency = const <CurrencyAmount>[],
    required this.displayTotal,
    this.warnings = const <String>[],
  });

  final bool hasTolls;
  final List<TollChargeItem> items;
  final List<TollBadge> gantryBadges;
  final List<CurrencyAmount> totalsByCurrency;
  final String displayTotal;
  final List<String> warnings;

  factory TollSummary.fromJson(Map<String, dynamic> json) => TollSummary(
        hasTolls: (json['has_tolls'] as bool?) ?? false,
        items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => TollChargeItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        gantryBadges: (json['gantry_badges'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => TollBadge.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalsByCurrency: (json['totals_by_currency'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => CurrencyAmount.fromJson(e as Map<String, dynamic>))
            .toList(),
        displayTotal: (json['display_total'] as String?) ?? 'Free',
        warnings: (json['warnings'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e as String)
            .toList(),
      );
}

@immutable
class GantryInfo {
  const GantryInfo({
    required this.gantryId,
    required this.corridorId,
    required this.corridorName,
    required this.operatorName,
    required this.systemType,
    required this.countryCode,
    this.externalCode,
    required this.name,
    required this.role,
    this.directionCode,
    this.directionBearing,
    required this.acceptedPayments,
    this.laneLayout = const <TollLaneGuidance>[],
    required this.coordinate,
  });

  final String gantryId;
  final String corridorId;
  final String corridorName;
  final String operatorName;
  final String systemType;
  final String countryCode;
  final String? externalCode;
  final String name;
  final String role;
  final String? directionCode;
  final int? directionBearing;
  final List<PaymentMethod> acceptedPayments;
  final List<TollLaneGuidance> laneLayout;
  final Coordinate coordinate;

  factory GantryInfo.fromJson(Map<String, dynamic> json) => GantryInfo(
        gantryId: json['gantry_id'] as String,
        corridorId: json['corridor_id'] as String,
        corridorName: json['corridor_name'] as String,
        operatorName: json['operator_name'] as String,
        systemType: json['system_type'] as String,
        countryCode: (json['country_code'] as String).trim(),
        externalCode: json['external_code'] as String?,
        name: json['name'] as String,
        role: json['role'] as String,
        directionCode: json['direction_code'] as String?,
        directionBearing: (json['direction_bearing'] as num?)?.toInt(),
        acceptedPayments: (json['accepted_payments'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => PaymentMethod.fromWire(e as String))
            .toList(),
        laneLayout: (json['lane_layout'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => TollLaneGuidance.fromJson(e as Map<String, dynamic>))
            .toList(),
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
      );
}

@immutable
class TollEstimateRequest {
  const TollEstimateRequest({
    required this.polyline6,
    required this.durationSeconds,
    this.departureTime,
    this.vehicleProfile = VehicleProfile.car,
    this.vehicleRegistrationCountry = 'MY',
    this.paymentMethods = const <PaymentMethod>[
      PaymentMethod.rfid,
      PaymentMethod.tngCard,
      PaymentMethod.erp2Obu,
    ],
  });

  final String polyline6;
  final double durationSeconds;
  final DateTime? departureTime;
  final VehicleProfile vehicleProfile;
  final String vehicleRegistrationCountry;
  final List<PaymentMethod> paymentMethods;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'polyline6': polyline6,
        'duration_seconds': durationSeconds,
        if (departureTime != null) 'departure_time': departureTime!.toIso8601String(),
        'vehicle_profile': vehicleProfile.wireValue,
        'vehicle_registration_country': vehicleRegistrationCountry,
        'payment_methods': paymentMethods.map((m) => m.wireValue).toList(),
      };
}
