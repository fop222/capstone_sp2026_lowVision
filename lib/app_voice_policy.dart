/// Global text-to-speech mute for voice commands and shopping flows.
class AppVoicePolicy {
  AppVoicePolicy._();

  static bool ttsMuted = false;

  static void setMuted(bool value) => ttsMuted = value;

  static void toggleMute() => ttsMuted = !ttsMuted;
}
