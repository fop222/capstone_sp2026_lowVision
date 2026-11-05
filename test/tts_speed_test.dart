import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/app_tts.dart';
import 'package:my_low_vision_app/app_voice_policy.dart';
import 'package:my_low_vision_app/tts_speed_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppVoicePolicy.speechSpeed = AppVoicePolicy.defaultSpeechSpeed;
  });

  test('pluginSpeechRate maps 1.0 to platform-normal', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(pluginSpeechRate(1.0), closeTo(0.5, 0.001));

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(pluginSpeechRate(1.0), closeTo(1.0, 0.001));
    expect(pluginSpeechRate(1.6), closeTo(1.6, 0.001));

    debugDefaultTargetPlatformOverride = null;
  });

  test('setSpeechSpeed persists and clamps', () async {
    await AppVoicePolicy.setSpeechSpeed(1.3);
    expect(AppVoicePolicy.speechSpeed, 1.3);

    await AppVoicePolicy.setSpeechSpeed(9);
    expect(AppVoicePolicy.speechSpeed, AppVoicePolicy.maxSpeechSpeed);

    await AppVoicePolicy.load();
    expect(AppVoicePolicy.speechSpeed, AppVoicePolicy.maxSpeechSpeed);
  });

  testWidgets('profile speed chips update talking speed', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TtsSpeedSettings()),
      ),
    );

    expect(find.text('Talking speed'), findsOneWidget);
    await tester.tap(find.text('Fast'));
    await tester.pumpAndSettle();
    expect(AppVoicePolicy.speechSpeed, AppVoicePolicy.speedPresets['Fast']);
  });
}
