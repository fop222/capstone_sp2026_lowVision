import 'package:shared_preferences/shared_preferences.dart';

/// Global text-to-speech mute and talking-speed for voice commands and flows.
class AppVoicePolicy {
  AppVoicePolicy._();

  static const _speedKey = 'tts_speech_speed';

  /// User-facing talking speed. `1.0` is normal, `0.5` is slow, `2.0` is fast.
  static const double minSpeechSpeed = 0.5;
  static const double maxSpeechSpeed = 2.0;
  static const double defaultSpeechSpeed = 1.0;

  static const Map<String, double> speedPresets = {
    'Slow': 0.7,
    'Normal': 1.0,
    'Fast': 1.3,
    'Very fast': 1.6,
  };

  static bool ttsMuted = false;

  static double speechSpeed = defaultSpeechSpeed;

  static void setMuted(bool value) => ttsMuted = value;

  static void toggleMute() => ttsMuted = !ttsMuted;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      speechSpeed = _clampSpeed(
        prefs.getDouble(_speedKey) ?? defaultSpeechSpeed,
      );
    } catch (_) {}
  }

  static Future<void> setSpeechSpeed(double value) async {
    speechSpeed = _clampSpeed(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_speedKey, speechSpeed);
    } catch (_) {}
  }

  static double _clampSpeed(double value) =>
      value.clamp(minSpeechSpeed, maxSpeechSpeed);
}
