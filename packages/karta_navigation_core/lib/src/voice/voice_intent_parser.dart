import 'package:karta_api_client/karta_api_client.dart';

/// Deterministic, sub-15ms on-device Speech-to-Intent parser supporting
/// English, Bahasa Melayu, Manglish, and Singlish road terms for hands-free
/// hazard reporting & navigation control without touching the screen.
class RegionalVoiceIntentParser {
  static final RegExp _wakePrefixRe = RegExp(
    r'^(?:hey\s+karta|ok\s+karta|hi\s+karta|karta\s+report|lapor\s+karta|karta)[,\s:]+',
    caseSensitive: false,
  );

  static final RegExp _highwayRefRe = RegExp(
    r'\b(PLUS|NKVE|LDP|DUKE|AKLEH|KESAS|SPRINT|ELITE|MEX|SUKE|SPE|LPT|NPE|BESRAYA|LEKAS|SKVE|WCE|PIE|AYE|CTE|ECP|BKE|SLE|TPE|KPE|MCE|NSC|E\d{1,2})\b',
    caseSensitive: false,
  );

  static const List<({HazardCategory cat, String subtype, double conf, List<String> terms})> _lexicon =
      <({HazardCategory cat, String subtype, double conf, List<String> terms})>[
    (
      cat: HazardCategory.roadClosure,
      subtype: 'flash_flood',
      conf: 0.96,
      terms: <String>['banjir kilat', 'flash flood', 'banjir', 'flooded', 'flooding', 'air naik', 'water ponding'],
    ),
    (
      cat: HazardCategory.roadClosure,
      subtype: 'closure',
      conf: 0.95,
      terms: <String>[
        'road closed',
        'road closure',
        'jalan tutup',
        'jalan ditutup',
        'lane closed',
        'lorong tutup',
        'tanah runtuh',
        'landslide',
        'sinkhole',
        'kerja jalan',
        'roadworks',
        'blocked road',
      ],
    ),
    (
      cat: HazardCategory.accident,
      subtype: 'collision',
      conf: 0.95,
      terms: <String>[
        'accident',
        'eksiden',
        'kemalangan',
        'car crash',
        'crash',
        'pileup',
        'pile up',
        'collision',
        'langgar',
        'terbalik',
        'overturned',
        'lorry overturn',
      ],
    ),
    (
      cat: HazardCategory.police,
      subtype: 'roadblock',
      conf: 0.95,
      terms: <String>['roadblock', 'road block', 'sekatan jalan', 'operasi', 'ops', 'jpj'],
    ),
    (
      cat: HazardCategory.police,
      subtype: 'speed_trap',
      conf: 0.94,
      terms: <String>[
        'speed trap',
        'perangkap laju',
        'traffic police',
        'tp ahead',
        'police',
        'polis',
        'abang polis',
        'mata-mata',
        'mata mata',
        'awas camera',
        'speed camera',
      ],
    ),
    (
      cat: HazardCategory.hiddenVehicle,
      subtype: 'stalled_vehicle',
      conf: 0.92,
      terms: <String>[
        'hidden vehicle',
        'stalled car',
        'stalled vehicle',
        'broken down',
        'breakdown',
        'kereta rosak',
        'lori rosak',
        'stopped car',
        'vehicle on shoulder',
        'car on shoulder',
        'motor rosak',
      ],
    ),
    (
      cat: HazardCategory.roadDebris,
      subtype: 'debris',
      conf: 0.92,
      terms: <String>[
        'road debris',
        'debris',
        'object on road',
        'objek atas jalan',
        'pokok tumbang',
        'fallen tree',
        'tree branch',
        'tayar pecah',
        'tire on road',
        'tyre on road',
        'oil spill',
        'minyak tumpah',
        'obstruction',
      ],
    ),
    (
      cat: HazardCategory.pothole,
      subtype: 'pothole',
      conf: 0.93,
      terms: <String>[
        'pothole',
        'pot hole',
        'lubang jalan',
        'jalan berlubang',
        'lubang besar',
        'lubang',
        'road hole',
        'deep hole',
        'uneven road',
      ],
    ),
  ];

  static const List<String> _cancelTerms = <String>[
    'cancel',
    'batal',
    'batalkan',
    'nevermind',
    'never mind',
    'tak jadi',
  ];
  static const List<String> _confirmTerms = <String>[
    'still there',
    'masih ada',
    'yes still',
    'confirm hazard',
    'ada lagi',
  ];
  static const List<String> _clearTerms = <String>[
    'cleared',
    'already cleared',
    'dah clear',
    'gone',
    'no longer there',
    'tak ada',
    'all clear',
  ];
  static const List<String> _rerouteTerms = <String>[
    'accept reroute',
    'take faster route',
    'reroute now',
    'tukar laluan',
    'ikut jalan baru',
    'yes reroute',
  ];

  static const List<String> _oppositeTerms = <String>[
    'opposite side',
    'opposite direction',
    'other side',
    'arah bertentangan',
    'sebelah sana',
    'bertentangan',
  ];
  static const List<String> _highSevTerms = <String>[
    'major',
    'teruk',
    'bad',
    'heavy',
    'severe',
    'huge',
    'besar',
    'jam teruk',
    'massive',
    'pileup',
  ];
  static const List<String> _lowSevTerms = <String>['minor', 'small', 'sikit', 'kecil', 'light'];

  static VoiceIntentResult parse(String transcript, {String locale = 'en-MY'}) {
    final cleaned = transcript.trim().replaceFirst(_wakePrefixRe, '').trim();
    final low = ' ${cleaned.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';

    final isBm = locale.toLowerCase().startsWith('ms') ||
        const <String>[' ada ', ' jalan ', ' lorong ', ' kereta ', ' polis ', ' kemalangan ', ' banjir ', ' lubang ', ' batal ', ' dah ']
            .any(low.contains);

    for (final t in _cancelTerms) {
      if (low.contains(' $t ')) {
        return VoiceIntentResult(
          intent: 'cancel',
          confidence: 0.96,
          confirmationSpeech: isBm ? 'Laporan dibatalkan.' : 'Report cancelled.',
          matchedTerms: <String>[t],
          normalizedTranscript: cleaned,
        );
      }
    }

    for (final t in _rerouteTerms) {
      if (low.contains(' $t ')) {
        return VoiceIntentResult(
          intent: 'accept_reroute',
          confidence: 0.95,
          confirmationSpeech:
              isBm ? 'Menukar ke laluan lebih pantas.' : 'Switching to the faster route now.',
          matchedTerms: <String>[t],
          normalizedTranscript: cleaned,
        );
      }
    }

    for (final entry in _lexicon) {
      for (final kw in entry.terms) {
        if (low.contains(' $kw ')) {
          final direction = _oppositeTerms.any(low.contains) ? 'opposite' : 'ahead';
          var severity = HazardSeverity.medium;
          if (entry.cat == HazardCategory.roadClosure || _highSevTerms.any(low.contains)) {
            severity = HazardSeverity.high;
          } else if (_lowSevTerms.any(low.contains)) {
            severity = HazardSeverity.low;
          }

          String? laneHint;
          if (const <String>['fast lane', 'right lane', 'lorong kanan', 'lorong laju'].any(low.contains)) {
            laneHint = 'right_lane';
          } else if (const <String>['left lane', 'slow lane', 'lorong kiri', 'lorong perlahan'].any(low.contains)) {
            laneHint = 'left_lane';
          } else if (const <String>['middle lane', 'center lane', 'lorong tengah'].any(low.contains)) {
            laneHint = 'middle_lane';
          } else if (const <String>['emergency lane', 'shoulder', 'lorong kecemasan', 'bahu jalan'].any(low.contains)) {
            laneHint = 'emergency_lane';
          }

          final roadMatch = _highwayRefRe.firstMatch(cleaned);
          final roadHint = roadMatch?.group(1)?.toUpperCase();

          final speech = isBm
              ? '${_bmLabel(entry.cat)} dilaporkan ${direction == 'opposite' ? 'di arah bertentangan' : 'di hadapan'}. Terima kasih!'
              : '${entry.cat.label} reported ${direction == 'opposite' ? 'on the opposite side' : 'ahead'}${roadHint != null ? ' on $roadHint' : ''}. Thank you.';

          return VoiceIntentResult(
            intent: 'report_hazard',
            confidence: entry.conf,
            hazardCategory: entry.cat,
            subtype: entry.subtype,
            severity: severity,
            direction: direction,
            laneHint: laneHint,
            roadHint: roadHint,
            confirmationSpeech: speech,
            matchedTerms: <String>[kw],
            normalizedTranscript: cleaned,
          );
        }
      }
    }

    for (final t in _confirmTerms) {
      if (low.contains(' $t ')) {
        return VoiceIntentResult(
          intent: 'confirm_hazard',
          confidence: 0.92,
          confirmationSpeech: isBm ? 'Disahkan masih ada.' : 'Confirmed hazard is still there.',
          matchedTerms: <String>[t],
          normalizedTranscript: cleaned,
        );
      }
    }

    for (final t in _clearTerms) {
      if (low.contains(' $t ')) {
        return VoiceIntentResult(
          intent: 'clear_hazard',
          confidence: 0.92,
          confirmationSpeech: isBm ? 'Terima kasih, tanda bahaya dikemas kini.' : 'Marked hazard as cleared.',
          matchedTerms: <String>[t],
          normalizedTranscript: cleaned,
        );
      }
    }

    return VoiceIntentResult(
      intent: 'unknown',
      confidence: 0.0,
      confirmationSpeech: isBm
          ? 'Cuba sebut polis, kemalangan, lubang jalan, kereta rosak, objek atas jalan, atau jalan tutup.'
          : 'Try saying police, accident, pothole, stalled car, debris, or road closed.',
      normalizedTranscript: cleaned,
    );
  }

  static String _bmLabel(HazardCategory cat) {
    return switch (cat) {
      HazardCategory.police => 'Kehadiran polis',
      HazardCategory.accident => 'Kemalangan',
      HazardCategory.pothole => 'Lubang jalan',
      HazardCategory.hiddenVehicle => 'Kenderaan rosak',
      HazardCategory.roadDebris => 'Objek di atas jalan',
      HazardCategory.roadClosure => 'Penutupan jalan',
    };
  }
}
