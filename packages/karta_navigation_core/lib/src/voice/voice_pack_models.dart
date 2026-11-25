import 'package:karta_api_client/karta_api_client.dart';
import 'package:meta/meta.dart';

@immutable
class NavigationVoiceCueSlot {
  const NavigationVoiceCueSlot({
    required this.key,
    required this.label,
    required this.samplePrompt,
    required this.category,
  });

  final String key;
  final String label;
  final String samplePrompt;
  final String category; // 'maneuver' | 'safety'
}

@immutable
class NavigationVoicePack {
  const NavigationVoicePack({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.localeTag,
    required this.speechRate,
    required this.speechPitch,
    this.isCustom = false,
    this.minimalMode = false,
    this.recordedClipKeys = const <String>[],
  });

  final String id;
  final String name;
  final String subtitle;
  final String localeTag;
  final double speechRate;
  final double speechPitch;
  final bool isCustom;
  final bool minimalMode;
  final List<String> recordedClipKeys;
}

abstract final class KartaVoicePackCatalog {
  static const List<NavigationVoiceCueSlot> customCueSlots = <NavigationVoiceCueSlot>[
    NavigationVoiceCueSlot(
      key: 'turn_left',
      label: 'Turn Left',
      samplePrompt: 'Turn left ahead',
      category: 'maneuver',
    ),
    NavigationVoiceCueSlot(
      key: 'turn_right',
      label: 'Turn Right',
      samplePrompt: 'Turn right ahead',
      category: 'maneuver',
    ),
    NavigationVoiceCueSlot(
      key: 'keep_left',
      label: 'Keep Left / Exit',
      samplePrompt: 'Keep left to take the exit',
      category: 'maneuver',
    ),
    NavigationVoiceCueSlot(
      key: 'keep_right',
      label: 'Keep Right',
      samplePrompt: 'Keep right on the expressway',
      category: 'maneuver',
    ),
    NavigationVoiceCueSlot(
      key: 'straight',
      label: 'Continue Straight',
      samplePrompt: 'Continue straight ahead',
      category: 'maneuver',
    ),
    NavigationVoiceCueSlot(
      key: 'roundabout',
      label: 'Roundabout',
      samplePrompt: 'Enter the roundabout ahead',
      category: 'maneuver',
    ),
    NavigationVoiceCueSlot(
      key: 'arrived',
      label: 'Destination Reached',
      samplePrompt: 'You have arrived at your destination',
      category: 'maneuver',
    ),
    NavigationVoiceCueSlot(
      key: 'toll_ahead',
      label: 'Toll Plaza / ERP',
      samplePrompt: 'Toll plaza ahead — check RFID or SmartTAG lane',
      category: 'safety',
    ),
    NavigationVoiceCueSlot(
      key: 'speed_camera',
      label: 'Speed Camera (AWAS / TP)',
      samplePrompt: 'Speed camera ahead — watch your speed',
      category: 'safety',
    ),
    NavigationVoiceCueSlot(
      key: 'hazard_police',
      label: 'Police Reported',
      samplePrompt: 'Police presence reported ahead',
      category: 'safety',
    ),
    NavigationVoiceCueSlot(
      key: 'hazard_accident',
      label: 'Accident / Closure',
      samplePrompt: 'Accident reported ahead, slow down',
      category: 'safety',
    ),
    NavigationVoiceCueSlot(
      key: 'rerouting',
      label: 'Live Rerouting',
      samplePrompt: 'Faster route found around traffic ahead',
      category: 'safety',
    ),
  ];

  static const List<NavigationVoicePack> builtInPacks = <NavigationVoicePack>[
    NavigationVoicePack(
      id: 'karta_studio_en',
      name: 'Karta Studio (EN)',
      subtitle: 'Crisp automotive telemetry voice · Default English',
      localeTag: 'en-US',
      speechRate: 1.02,
      speechPitch: 1.0,
    ),
    NavigationVoicePack(
      id: 'karta_my_local',
      name: 'Kuala Lumpur Local (EN / BM)',
      subtitle: 'Malaysian English & Bahasa Melayu highway & PLUS cues',
      localeTag: 'ms-MY',
      speechRate: 1.0,
      speechPitch: 1.04,
    ),
    NavigationVoicePack(
      id: 'karta_sg_concise',
      name: 'Singapore Concise (EN-SG)',
      subtitle: 'Fast expressway, CTE/PIE exit & ERP gantry phrasing',
      localeTag: 'en-SG',
      speechRate: 1.08,
      speechPitch: 1.0,
    ),
    NavigationVoicePack(
      id: 'karta_codriver',
      name: 'Motorsport Co-Driver',
      subtitle: 'High-tempo concise pacing & hazard callouts',
      localeTag: 'en-GB',
      speechRate: 1.15,
      speechPitch: 0.94,
    ),
    NavigationVoicePack(
      id: 'karta_minimal',
      name: 'Calm Minimalist',
      subtitle: 'Critical turns, AWAS/TP cameras & major hazards only',
      localeTag: 'en-US',
      speechRate: 0.96,
      speechPitch: 0.96,
      minimalMode: true,
    ),
  ];

  /// Maps a Valhalla maneuver type code into one of the 12 custom voice cue slots.
  static String cueKeyForValhallaManeuver(int valhallaType) {
    return switch (valhallaType) {
      14 || 15 || 16 => 'turn_left',
      9 || 10 || 11 => 'turn_right',
      19 || 21 || 24 => 'keep_left',
      18 || 20 || 23 => 'keep_right',
      26 || 27 => 'roundabout',
      4 || 5 || 6 => 'arrived',
      _ => 'straight',
    };
  }

  static String cueKeyForHazard(HazardCategory category) {
    return switch (category) {
      HazardCategory.police => 'hazard_police',
      HazardCategory.accident || HazardCategory.roadClosure => 'hazard_accident',
      _ => 'hazard_accident',
    };
  }

  /// Styles a raw maneuver/hazard prompt according to the selected regional voice pack.
  static String formatPromptForPack(NavigationVoicePack pack, String rawCue, {String? cueKey}) {
    if (pack.id == 'karta_my_local') {
      return switch (cueKey) {
        'turn_left' => 'Belok kiri di hadapan. $rawCue',
        'turn_right' => 'Belok kanan di hadapan. $rawCue',
        'toll_ahead' => 'Plaza tol di hadapan, bersedia di lorong RFID atau SmartTAG.',
        'speed_camera' => 'Awas, kamera perangkap laju di hadapan.',
        'hazard_police' => 'Perhatian, kehadiran polis dilaporkan di hadapan.',
        'hazard_accident' => 'Awas, kemalangan atau halangan dilaporkan di hadapan.',
        'rerouting' => 'Laluan lebih pantas ditemui untuk mengelak kesesakan.',
        _ => rawCue,
      };
    }
    if (pack.id == 'karta_codriver') {
      return switch (cueKey) {
        'turn_left' => 'Left ahead — $rawCue',
        'turn_right' => 'Right ahead — $rawCue',
        'hazard_accident' => 'Caution! Incident ahead, prepare to brake.',
        'rerouting' => 'Detour locked — taking faster line.',
        _ => rawCue,
      };
    }
    return rawCue;
  }
}
