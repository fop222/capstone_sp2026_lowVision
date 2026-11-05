import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_voice_policy.dart';

/// English-only TTS: one stable voice for prompts and read-aloud.
///
/// On **web (especially iOS Safari)**, `speechSynthesis.getVoices()` is often
/// empty on the first call and returns voices asynchronously. The plugin’s
/// [FlutterTts.setLanguage] uses `.first` on a fuzzy match, so the chosen voice
/// can change between sessions. We wait for voices, sort candidates
/// deterministically, then [FlutterTts.setVoice] once.
Future<void> applyEnglishTts(FlutterTts tts) async {
  try {
    await tts.awaitSpeakCompletion(true);
  } catch (_) {}

  if (kIsWeb) {
    await _pinEnglishVoiceWeb(tts);
  } else {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final engines = await tts.getEngines;
        if (engines is List) {
          for (final e in engines) {
            if (e.toString().toLowerCase().contains('com.google.android.tts')) {
              await tts.setEngine(e.toString());
              break;
            }
          }
        }
      } catch (_) {}
    }

    for (final loc in ['en-US', 'en_US', 'en-GB', 'en_GB', 'en']) {
      try {
        await tts.setLanguage(loc);
        break;
      } catch (_) {}
    }
  }

  await applyAppSpeechRate(tts);
}

/// Maps the user-facing speed (`1.0` = normal) onto each platform's TTS scale.
double pluginSpeechRate(double userSpeed) {
  final speed = userSpeed.clamp(
    AppVoicePolicy.minSpeechSpeed,
    AppVoicePolicy.maxSpeechSpeed,
  );
  if (kIsWeb) {
    return speed;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      // AVSpeechUtterance: 0.5 is the default "normal" rate.
      return (0.5 * speed).clamp(0.1, 1.0);
    default:
      // Android / others: 1.0 is normal; values above 1.0 speak faster.
      return speed;
  }
}

Future<void> applyAppSpeechRate(FlutterTts tts) async {
  try {
    await tts.setSpeechRate(pluginSpeechRate(AppVoicePolicy.speechSpeed));
  } catch (_) {}
}

/// Speak [text] at the user's saved talking speed.
Future<dynamic> speakApp(FlutterTts tts, String text) async {
  await applyAppSpeechRate(tts);
  return tts.speak(text);
}

/// Wait for Safari / WebKit to populate voices, then pick one stable en voice.
Future<void> _pinEnglishVoiceWeb(FlutterTts tts) async {
  await _tryPinEnglishVoiceOnce(tts);
  // iOS Safari often fires `voiceschanged` shortly after load; pin again so we
  // don't keep using the browser default for early utterances vs later ones.
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await _tryPinEnglishVoiceOnce(tts);
}

Future<void> _tryPinEnglishVoiceOnce(FlutterTts tts) async {
  List<dynamic>? list;
  for (var i = 0; i < 12; i++) {
    try {
      final raw = await tts.getVoices;
      if (raw is List && raw.isNotEmpty) {
        list = raw;
        break;
      }
    } catch (_) {}
    await Future<void>.delayed(Duration(milliseconds: i < 4 ? 40 : 80));
  }

  final candidates = <Map<String, String>>[];
  if (list != null) {
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final name = '${m['name'] ?? ''}'.trim();
      final locale = '${m['locale'] ?? ''}'.trim();
      if (name.isEmpty || locale.isEmpty) continue;
      final low = locale.toLowerCase();
      if (low.startsWith('en')) {
        candidates.add({'name': name, 'locale': locale});
      }
    }
  }

  candidates.sort((a, b) {
    final ka = '${a['locale']}|${a['name']}';
    final kb = '${b['locale']}|${b['name']}';
    return ka.compareTo(kb);
  });

  Map<String, String>? pick;
  for (final c in candidates) {
    if ((c['locale'] ?? '').toLowerCase().startsWith('en-us')) {
      pick = c;
      break;
    }
  }
  pick ??= candidates.isNotEmpty ? candidates.first : null;

  if (pick != null) {
    try {
      await tts.setVoice({
        'name': pick['name']!,
        'locale': pick['locale']!,
      });
      try {
        await tts.setLanguage(pick['locale']!);
      } catch (_) {}
      return;
    } catch (_) {}
  }

  try {
    await tts.setLanguage('en-US');
  } catch (_) {}
}

/// Locale for [SpeechToText.listen] in English.
String? englishSpeechToTextLocaleId() {
  if (kIsWeb) return 'en-US';
  return 'en_US';
}
