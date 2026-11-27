import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:karta_design_system/karta_design_system.dart';

import '../services/language_storage_stub.dart'
    if (dart.library.js_interop) '../services/language_storage_web.dart' as lang_store;
import 'karta_app_state.dart';

class KartaLanguageNotifier extends StateNotifier<KartaLanguage> {
  KartaLanguageNotifier(this._ref)
      : super(KartaLanguage.fromCode(lang_store.readPersistedLanguageCode()));

  final Ref _ref;

  void setLanguage(KartaLanguage language) {
    if (state == language) return;
    state = language;
    lang_store.writePersistedLanguageCode(language.code);
    _ref.read(kartaMapControllerProvider).setMapLanguage(language.code);
  }
}

final kartaLanguageProvider =
    StateNotifierProvider<KartaLanguageNotifier, KartaLanguage>(
  (ref) => KartaLanguageNotifier(ref),
);
