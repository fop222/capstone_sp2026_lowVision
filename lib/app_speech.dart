import 'package:speech_to_text/speech_to_text.dart';

/// Single [SpeechToText] instance so the global command mic and feature
/// screens do not compete with separate plugin instances.
class AppSpeech {
  AppSpeech._();
  static final AppSpeech I = AppSpeech._();

  final SpeechToText stt = SpeechToText();
  Future<bool>? _init;

  Future<bool> ensureInitialized({
    void Function(dynamic err)? onError,
    void Function(String)? onStatus,
  }) async {
    if (_init != null) {
      final ok = await _init!;
      if (ok) return true;
      _init = null;
    }
    final next = stt.initialize(
      onError: onError ?? (_) {},
      onStatus: onStatus ?? (_) {},
    );
    _init = next;
    final result = await next;
    if (!result) {
      _init = null;
    }
    return result;
  }
}
