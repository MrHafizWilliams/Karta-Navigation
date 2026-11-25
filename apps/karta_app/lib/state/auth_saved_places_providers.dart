import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_map_engine/karta_map_engine.dart';

import '../services/auth_token_storage_stub.dart'
    if (dart.library.js_interop) '../services/auth_token_storage_web.dart' as token_store;
import 'karta_app_state.dart';

@immutable
class AuthSavedPlacesState {
  const AuthSavedPlacesState({
    this.user,
    this.accessToken,
    this.savedPlaces = const <SavedPlaceItem>[],
    this.isBusy = false,
    this.isRestoring = false,
    this.errorMessage,
    this.statusMessage,
    this.selectedCategoryFilter = 'all',
  });

  final KartaUserProfile? user;
  final String? accessToken;
  final List<SavedPlaceItem> savedPlaces;
  final bool isBusy;
  final bool isRestoring;
  final String? errorMessage;
  final String? statusMessage;
  final String selectedCategoryFilter;

  bool get isAuthenticated => user != null && accessToken != null && accessToken!.isNotEmpty;

  List<SavedPlaceItem> get filteredPlaces {
    if (selectedCategoryFilter == 'all') return savedPlaces;
    return savedPlaces
        .where((p) => p.category.toLowerCase() == selectedCategoryFilter.toLowerCase())
        .toList();
  }

  bool isCoordinateSaved(Coordinate coord) {
    return savedPlaces.any(
      (p) =>
          (p.coordinate.lat - coord.lat).abs() < 0.0004 &&
          (p.coordinate.lon - coord.lon).abs() < 0.0004,
    );
  }

  AuthSavedPlacesState copyWith({
    KartaUserProfile? user,
    String? accessToken,
    List<SavedPlaceItem>? savedPlaces,
    bool? isBusy,
    bool? isRestoring,
    String? errorMessage,
    String? statusMessage,
    String? selectedCategoryFilter,
    bool clearAuth = false,
    bool clearError = false,
    bool clearStatus = false,
  }) =>
      AuthSavedPlacesState(
        user: clearAuth ? null : (user ?? this.user),
        accessToken: clearAuth ? null : (accessToken ?? this.accessToken),
        savedPlaces: clearAuth ? const <SavedPlaceItem>[] : (savedPlaces ?? this.savedPlaces),
        isBusy: isBusy ?? this.isBusy,
        isRestoring: isRestoring ?? this.isRestoring,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
        selectedCategoryFilter: selectedCategoryFilter ?? this.selectedCategoryFilter,
      );
}

class AuthSavedPlacesNotifier extends StateNotifier<AuthSavedPlacesState> {
  AuthSavedPlacesNotifier(this._ref) : super(const AuthSavedPlacesState()) {
    _restoreSession();
  }

  final Ref _ref;

  Future<void> _restoreSession() async {
    final stored = token_store.readPersistedAuthToken();
    if (stored == null || stored.isEmpty) return;
    state = state.copyWith(isRestoring: true, clearError: true);
    try {
      final api = _ref.read(kartaApiClientProvider);
      final user = await api.getCurrentUser(accessToken: stored);
      if (!mounted) return;
      final savedResp = await api.listSavedPlaces(accessToken: stored);
      if (!mounted) return;
      state = state.copyWith(
        user: user,
        accessToken: stored,
        savedPlaces: savedResp.items,
        isRestoring: false,
      );
      _syncSavedPinsToMap(savedResp.items);
    } catch (_) {
      token_store.writePersistedAuthToken(null);
      if (!mounted) return;
      state = state.copyWith(isRestoring: false, clearAuth: true);
      _syncSavedPinsToMap(const <SavedPlaceItem>[]);
    }
  }

  void setCategoryFilter(String filter) {
    state = state.copyWith(selectedCategoryFilter: filter, clearError: true);
  }

  void clearFeedback() {
    state = state.copyWith(clearError: true, clearStatus: true);
  }

  Future<bool> register({
    required String email,
    required String displayName,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true, clearStatus: true);
    try {
      final api = _ref.read(kartaApiClientProvider);
      final session = await api.registerUser(
        email: email,
        displayName: displayName,
        password: password,
      );
      if (!mounted) return false;
      token_store.writePersistedAuthToken(session.accessToken);
      state = state.copyWith(
        user: session.user,
        accessToken: session.accessToken,
        savedPlaces: const <SavedPlaceItem>[],
        isBusy: false,
        statusMessage: 'Welcome to Karta, ${session.user.displayName}!',
      );
      _syncSavedPinsToMap(const <SavedPlaceItem>[]);
      return true;
    } on KartaApiException catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isBusy: false, errorMessage: e.message);
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isBusy: false,
        errorMessage: 'Unable to reach Karta account server right now.',
      );
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true, clearStatus: true);
    try {
      final api = _ref.read(kartaApiClientProvider);
      final session = await api.loginUser(email: email, password: password);
      if (!mounted) return false;
      token_store.writePersistedAuthToken(session.accessToken);
      final savedResp = await api.listSavedPlaces(accessToken: session.accessToken);
      if (!mounted) return false;
      state = state.copyWith(
        user: session.user,
        accessToken: session.accessToken,
        savedPlaces: savedResp.items,
        isBusy: false,
        statusMessage: 'Signed in as ${session.user.displayName}.',
      );
      _syncSavedPinsToMap(savedResp.items);
      return true;
    } on KartaApiException catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isBusy: false, errorMessage: e.message);
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isBusy: false,
        errorMessage: 'Unable to reach Karta account server right now.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    final token = state.accessToken;
    token_store.writePersistedAuthToken(null);
    state = state.copyWith(
      clearAuth: true,
      clearError: true,
      statusMessage: 'Signed out cleanly.',
    );
    _syncSavedPinsToMap(const <SavedPlaceItem>[]);
    if (token != null && token.isNotEmpty) {
      try {
        await _ref.read(kartaApiClientProvider).logoutUser(accessToken: token);
      } catch (_) {}
    }
  }

  Future<bool> savePlace({
    required String name,
    required Coordinate coordinate,
    String category = 'favorite',
    String? addressSubtitle,
    String? notes,
    String? countryCode,
    int? poiId,
  }) async {
    final token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Sign in or register in the Saved tab to bookmark places & landmarks.',
      );
      return false;
    }
    state = state.copyWith(isBusy: true, clearError: true, clearStatus: true);
    try {
      final api = _ref.read(kartaApiClientProvider);
      await api.createSavedPlace(
        accessToken: token,
        request: SavedPlaceCreateRequest(
          name: name,
          coordinate: coordinate,
          category: category,
          addressSubtitle: addressSubtitle,
          notes: notes,
          countryCode: countryCode,
          poiId: poiId,
        ),
      );
      final refreshed = await api.listSavedPlaces(accessToken: token);
      if (!mounted) return false;
      state = state.copyWith(
        savedPlaces: refreshed.items,
        isBusy: false,
        statusMessage: 'Saved "$name" to your places.',
      );
      _syncSavedPinsToMap(refreshed.items);
      return true;
    } on KartaApiException catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isBusy: false, errorMessage: e.message);
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isBusy: false,
        errorMessage: 'Could not save place — check connection to Karta server.',
      );
      return false;
    }
  }

  Future<void> deleteSavedPlace(String placeId) async {
    final token = state.accessToken;
    if (token == null || token.isEmpty) return;
    final previous = state.savedPlaces;
    final optimistic = previous.where((p) => p.id != placeId).toList();
    state = state.copyWith(savedPlaces: optimistic, clearError: true);
    _syncSavedPinsToMap(optimistic);
    try {
      await _ref.read(kartaApiClientProvider).deleteSavedPlace(
            accessToken: token,
            placeId: placeId,
          );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        savedPlaces: previous,
        errorMessage: 'Could not remove saved place.',
      );
      _syncSavedPinsToMap(previous);
    }
  }

  void _syncSavedPinsToMap(List<SavedPlaceItem> places) {
    final pins = places
        .map(
          (p) => KartaMapSavedPlacePin(
            id: p.id,
            name: p.name,
            category: p.category,
            coordinate: p.coordinate,
          ),
        )
        .toList();
    _ref.read(kartaMapControllerProvider).setSavedPlaces(pins);
  }
}

final authSavedPlacesProvider =
    StateNotifierProvider<AuthSavedPlacesNotifier, AuthSavedPlacesState>(
  (ref) => AuthSavedPlacesNotifier(ref),
);
