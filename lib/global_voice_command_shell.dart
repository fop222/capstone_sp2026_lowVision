import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_voice_policy.dart';
import 'app_speech.dart';
import 'shopping_voice_host.dart';

/// Wraps the app navigator and pins a single voice-command control (top-right).
class GlobalVoiceCommandShell extends StatefulWidget {
  const GlobalVoiceCommandShell({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<GlobalVoiceCommandShell> createState() => _GlobalVoiceCommandShellState();
}

class _GlobalVoiceCommandShellState extends State<GlobalVoiceCommandShell> {
  final FlutterTts _confirmTts = FlutterTts();
  bool _listening = false;
  String? _statusBanner;

  @override
  void initState() {
    super.initState();
    _confirmTts.awaitSpeakCompletion(true);
    unawaited(AppSpeech.I.ensureInitialized());
  }

  @override
  void dispose() {
    _confirmTts.stop();
    super.dispose();
  }

  Future<void> _speakConfirm(String text) async {
    if (!mounted) return;
    if (!AppVoicePolicy.ttsMuted) {
      await _confirmTts.stop();
      await _confirmTts.speak(text);
    }
  }

  Future<void> _runMuteCommand() async {
    final wasMuted = AppVoicePolicy.ttsMuted;
    if (wasMuted) {
      AppVoicePolicy.setMuted(false);
      setState(() => _statusBanner = 'Sound on');
      await _speakConfirm('Sound on');
    } else {
      await _speakConfirm('Muted');
      AppVoicePolicy.setMuted(true);
      setState(() => _statusBanner = 'Muted');
    }
    if (mounted) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _statusBanner = null);
    }
  }

  Future<void> _handleHeardPhrase(String raw) async {
    final phrase = raw.toLowerCase().trim();
    if (phrase.isEmpty) return;

    final messenger = ScaffoldMessenger.maybeOf(context);

    void snack(String msg) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 18)),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    Future<void> feedback(String visual, String spoken) async {
      if (!mounted) return;
      setState(() => _statusBanner = visual);
      snack(visual);
      await _speakConfirm(spoken);
      if (mounted) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _statusBanner = null);
      }
    }

    final host = ShoppingVoiceHost.current;

    if (phrase.contains('mute')) {
      await _runMuteCommand();
      return;
    }

    if (phrase.contains('end') && phrase.contains('shopping')) {
      if (host?.onEndShopping != null) {
        await feedback('Ending shopping', 'Ending shopping');
        await host!.onEndShopping!();
      } else {
        final nav = widget.navigatorKey.currentState;
        if (nav?.canPop() ?? false) {
          nav!.pop();
          await feedback('Closed screen', 'Closed screen');
        } else {
          await feedback('End shopping', 'You are not in a shopping trip.');
        }
      }
      return;
    }

    if (phrase.contains('add') && phrase.contains('item')) {
      if (host?.onOpenAddItem != null) {
        await feedback('Add item', 'Add item');
        await host!.onOpenAddItem!();
      } else {
        await feedback('Add item', 'Open a grocery list, then add an item.');
      }
      return;
    }

    if (phrase.contains('scan') && phrase.contains('aisle')) {
      if (host?.onScanAisleSign != null) {
        await feedback('Scan aisle', 'Scan aisle');
        await host!.onScanAisleSign!();
      } else {
        await feedback('Scan aisle', 'Start shopping from a list first.');
      }
      return;
    }

    if (phrase.contains('scan') && phrase.contains('shelf')) {
      if (host?.onScanShelf != null) {
        await feedback('Scan shelf', 'Scan shelf');
        await host!.onScanShelf!();
      } else {
        await feedback('Scan shelf', 'Start shopping from a list first.');
      }
      return;
    }

    if (phrase.contains('open') && phrase.contains('list')) {
      if (host?.onOpenShoppingList != null) {
        await feedback('Open list', 'Open list');
        await host!.onOpenShoppingList!();
      } else {
        await feedback('Open list', 'Open your grocery lists from the home screen.');
      }
      return;
    }

    await feedback('Command not recognized', 'Say end shopping, add item, scan aisle, scan shelf, open list, or mute.');
  }

  Future<void> _onMicPressed() async {
    if (_listening) return;
    final ok = await AppSpeech.I.ensureInitialized();
    if (!ok || !mounted) {
      setState(() => _statusBanner = 'Voice unavailable');
      return;
    }

    if (AppSpeech.I.stt.isListening) {
      await AppSpeech.I.stt.stop();
    }

    setState(() {
      _listening = true;
      _statusBanner = 'Listening for command…';
    });

    final completer = Completer<String>();
    var best = '';

    try {
      await AppSpeech.I.stt.listen(
        onResult: (result) {
          best = result.recognizedWords;
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
        partialResults: true,
      );

      final heard = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          unawaited(AppSpeech.I.stt.stop());
          return best;
        },
      );

      await AppSpeech.I.stt.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      await _handleHeardPhrase(heard);
    } catch (_) {
      await AppSpeech.I.stt.stop();
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 72),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_statusBanner != null)
                    Material(
                      color: const Color(0xFF1A1D24),
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Text(
                            _statusBanner!,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Material(
                    color: const Color(0xFF3AE4C2),
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _listening ? null : _onMicPressed,
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(
                          _listening ? Icons.mic : Icons.mic_none,
                          color: Colors.black,
                          size: 30,
                          semanticLabel: _listening
                              ? 'Listening for voice command'
                              : 'Voice commands',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
