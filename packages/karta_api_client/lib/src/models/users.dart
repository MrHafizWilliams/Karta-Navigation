import 'package:meta/meta.dart';
import 'common.dart';

@immutable
class KartaUserProfile {
  const KartaUserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.savedPlacesCount = 0,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final int savedPlacesCount;
  final DateTime createdAt;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return email.isNotEmpty ? email[0].toUpperCase() : 'K';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  factory KartaUserProfile.fromJson(Map<String, dynamic> json) => KartaUserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['display_name'] as String,
        savedPlacesCount: (json['saved_places_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

@immutable
class AuthSessionResponse {
  const AuthSessionResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final DateTime expiresAt;
  final KartaUserProfile user;

  factory AuthSessionResponse.fromJson(Map<String, dynamic> json) => AuthSessionResponse(
        accessToken: json['access_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
        expiresAt: DateTime.parse(json['expires_at'] as String),
        user: KartaUserProfile.fromJson(json['user'] as Map<String, dynamic>),
      );
}

@immutable
class SavedPlaceItem {
  const SavedPlaceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.coordinate,
    this.addressSubtitle,
    this.notes,
    this.countryCode,
    this.poiId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String category;
  final Coordinate coordinate;
  final String? addressSubtitle;
  final String? notes;
  final String? countryCode;
  final int? poiId;
  final DateTime createdAt;

  factory SavedPlaceItem.fromJson(Map<String, dynamic> json) => SavedPlaceItem(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String? ?? 'favorite',
        coordinate: Coordinate.fromJson(json['coordinate'] as Map<String, dynamic>),
        addressSubtitle: json['address_subtitle'] as String?,
        notes: json['notes'] as String?,
        countryCode: (json['country_code'] as String?)?.trim(),
        poiId: (json['poi_id'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

@immutable
class SavedPlaceCreateRequest {
  const SavedPlaceCreateRequest({
    required this.name,
    required this.coordinate,
    this.category = 'favorite',
    this.addressSubtitle,
    this.notes,
    this.countryCode,
    this.poiId,
  });

  final String name;
  final Coordinate coordinate;
  final String category;
  final String? addressSubtitle;
  final String? notes;
  final String? countryCode;
  final int? poiId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'coordinate': coordinate.toJson(),
        'category': category,
        if (addressSubtitle != null && addressSubtitle!.isNotEmpty)
          'address_subtitle': addressSubtitle,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (countryCode != null && countryCode!.isNotEmpty) 'country_code': countryCode,
        if (poiId != null) 'poi_id': poiId,
      };
}

@immutable
class SavedPlacesListResponse {
  const SavedPlacesListResponse({
    required this.count,
    required this.items,
  });

  final int count;
  final List<SavedPlaceItem> items;

  factory SavedPlacesListResponse.fromJson(Map<String, dynamic> json) => SavedPlacesListResponse(
        count: (json['count'] as num?)?.toInt() ?? 0,
        items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => SavedPlaceItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
