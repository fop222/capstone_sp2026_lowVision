import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_tts.dart';
import 'app_voice_policy.dart';
import 'grocery_ui.dart';

/// Large, high-contrast talking-speed control for Profile / settings.
class TtsSpeedSettings extends StatefulWidget {
  const TtsSpeedSettings({super.key});

  @override
  State<TtsSpeedSettings> createState() => _TtsSpeedSettingsState();
}

class _TtsSpeedSettingsState extends State<TtsSpeedSettings> {
  FlutterTts? _previewTts;
  bool _previewing = false;

  @override
  void dispose() {
    _previewTts?.stop();
    super.dispose();
  }

  Future<void> _setSpeed(double value) async {
    await AppVoicePolicy.setSpeechSpeed(value);
    if (mounted) setState(() {});
  }

  Future<void> _preview() async {
    _previewTts ??= FlutterTts();
    final tts = _previewTts!;
    if (_previewing) {
      await tts.stop();
      if (mounted) setState(() => _previewing = false);
      return;
    }
    setState(() => _previewing = true);
    try {
      await applyEnglishTts(tts);
      await speakApp(
        tts,
        'This is how fast the app will talk. You can change the speed any time.',
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  String get _speedLabel {
    for (final entry in AppVoicePolicy.speedPresets.entries) {
      if ((AppVoicePolicy.speechSpeed - entry.value).abs() < 0.06) {
        return entry.key;
      }
    }
    return '${AppVoicePolicy.speechSpeed.toStringAsFixed(1)} times';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speed = AppVoicePolicy.speechSpeed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Talking speed', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'How fast the app speaks out loud. Currently $_speedLabel.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: AppVoicePolicy.speedPresets.entries.map((entry) {
            final selected = (speed - entry.value).abs() < 0.06;
            return FilterChip(
              label: Text(
                entry.key,
                style: TextStyle(
                  fontSize: 18,
                  color: selected ? const Color(0xFF0A2E1A) : Colors.white,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              selected: selected,
              backgroundColor: const Color(0xFF1A1D24),
              selectedColor: const Color(0xFF2ECC71),
              checkmarkColor: const Color(0xFF0A2E1A),
              side: BorderSide(
                color: selected ? const Color(0xFF2ECC71) : Colors.white24,
                width: 1.5,
              ),
              onSelected: (_) => _setSpeed(entry.value),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        Semantics(
          label: 'Talking speed slider',
          value: _speedLabel,
          slider: true,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              activeTrackColor: kBrandPurpleMid,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: kBrandPurpleMid.withValues(alpha: 0.25),
            ),
            child: Slider(
              min: AppVoicePolicy.minSpeechSpeed,
              max: AppVoicePolicy.maxSpeechSpeed,
              divisions: 15,
              value: speed,
              label: _speedLabel,
              onChanged: (v) {
                setState(() {
                  AppVoicePolicy.speechSpeed = v.clamp(
                    AppVoicePolicy.minSpeechSpeed,
                    AppVoicePolicy.maxSpeechSpeed,
                  );
                });
              },
              onChangeEnd: _setSpeed,
            ),
          ),
        ),
        Row(
          children: [
            Text(
              'Slower',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const Spacer(),
            Text(
              'Faster',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _preview,
          icon: Icon(_previewing ? Icons.stop_rounded : Icons.volume_up_rounded),
          label: Text(_previewing ? 'Stop sample' : 'Hear a sample'),
        ),
      ],
    );
  }
}
