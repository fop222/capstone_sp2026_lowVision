/// Auditory Cooking Mode — one step at a time, with optional Hands-Free Mode.
///
/// Navigated to from [CookingPrepScreen].  Uses TTS to automatically read each
/// step aloud.  When Hands-Free Mode is enabled Lumio reads the step, asks
/// "Are you ready to move on?", and advances only on an affirmative spoken
/// response.  Manual controls are always available.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_speech.dart';
import 'app_tts.dart';
import 'grocery_ui.dart';
import 'recipe_data.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// Classification of a spoken response in Hands-Free Mode.
enum _HFVerdict { yes, no, unclear }

// ─────────────────────────────────────────────────────────────────────────────

class CookingModeScreen extends StatefulWidget {
  const CookingModeScreen({
    super.key,
    required this.recipe,
    this.handsFreeMode = false,
  });

  final Recipe recipe;

  /// When true the screen starts in Hands-Free Mode.
  final bool handsFreeMode;

  @override
  State<CookingModeScreen> createState() => _CookingModeScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _CookingModeScreenState extends State<CookingModeScreen> {
  // ── Navigation ──────────────────────────────────────────────────────────
  int _step = 0;

  // ── TTS ─────────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  // ── Hands-Free Mode ──────────────────────────────────────────────────────
  late bool _handsFree;
  bool _speechAvailable = false;

  // HF phase indicators (all false when HF is off or idle)
  bool _listening = false;
  bool _waitingConfirm = false;
  bool _timedOut = false; // last listen attempt timed out with no speech
  String _listenTranscript = ''; // live partial transcript shown on screen

  /// Incremented on every new HF cycle or manual navigation. Async callbacks
  /// check this before acting to avoid stale results advancing the recipe.
  int _hfGen = 0;

  // ── Convenience ─────────────────────────────────────────────────────────
  List<String> get _steps => widget.recipe.steps;
  int get _total => _steps.length;
  bool get _isLast => _step == _total - 1;
  String get _currentText => _steps[_step];

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _handsFree = widget.handsFreeMode;
    _initAndStart();
  }

  Future<void> _initAndStart() async {
    await applyEnglishTts(_tts);
    // Let the navigation animation settle and the Web Speech queue clear.
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    await _tts.stop();

    // Initialise speech recognition (shared singleton — safe to call many times).
    try {
      _speechAvailable = await AppSpeech.I.ensureInitialized();
    } catch (_) {
      _speechAvailable = false;
    }
    if (!mounted) return;

    if (_handsFree) {
      _runHandsFreeStep();
    } else {
      setState(() => _speaking = true);
      await _tts.speak(_currentText);
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  void dispose() {
    _hfGen++; // invalidate any in-flight HF cycle
    _tts.stop();
    if (AppSpeech.I.stt.isListening) {
      AppSpeech.I.stt.stop();
    }
    super.dispose();
  }

  // ── Generation guard ─────────────────────────────────────────────────────

  /// Returns true only when the widget is still mounted, HF is still on, and
  /// the async work belongs to the current generation (not stale).
  bool _stillActive(int gen) =>
      mounted && _handsFree && _hfGen == gen;

  // ── Cancel all active voice work ─────────────────────────────────────────

  /// Stops TTS and STT and invalidates the current HF generation.
  /// Must be called before every manual navigation action.
  Future<void> _cancelVoice() async {
    _hfGen++; // invalidate in-flight cycle
    if (mounted) {
      setState(() {
        _speaking = false;
        _listening = false;
        _waitingConfirm = false;
        _timedOut = false;
        _listenTranscript = '';
      });
    }
    await _tts.stop();
    if (AppSpeech.I.stt.isListening) {
      await AppSpeech.I.stt.stop();
    }
  }

  // ── TTS helpers ─────────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    if (!mounted) return;
    await _tts.stop();
    setState(() => _speaking = true);
    await _tts.speak(text);
    if (mounted) setState(() => _speaking = false);
  }

  // ── STT (Hands-Free only) ────────────────────────────────────────────────

  /// Listens for a spoken yes/no response, updating [_listenTranscript] as
  /// words are recognised.  Returns the final recognised text, or an empty
  /// string on timeout / unavailable.
  Future<String> _listenForHFResponse(int gen) async {
    if (!_speechAvailable || !mounted) return '';

    // Stop any leftover session from the shopping scanner or prior call.
    if (AppSpeech.I.stt.isListening) {
      await AppSpeech.I.stt.stop();
      await Future.delayed(
          Duration(milliseconds: kIsWeb ? 700 : 300));
    }
    if (!_stillActive(gen)) return '';

    var recognized = '';
    if (mounted) {
      setState(() {
        _listening = true;
        _listenTranscript = '';
      });
    }

    try {
      await AppSpeech.I.stt.listen(
        onResult: (result) {
          if (!mounted) return;
          recognized = result.recognizedWords;
          setState(() => _listenTranscript = recognized);
        },
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 4),
        localeId: englishSpeechToTextLocaleId(),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.confirmation,
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _listenTranscript = '';
        });
      }
      return '';
    }

    // Poll until speech_to_text finishes (pauseFor / listenFor / stop()).
    while (AppSpeech.I.stt.isListening) {
      if (!mounted || !_stillActive(gen)) {
        await AppSpeech.I.stt.stop();
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Small settle delay so the UI reflects the final state.
    await Future.delayed(
        Duration(milliseconds: kIsWeb ? 450 : 150));

    if (mounted) {
      setState(() {
        _listening = false;
        _listenTranscript = '';
      });
    }

    return recognized.trim();
  }

  // ── Response classification ──────────────────────────────────────────────

  /// Classifies a spoken response as yes, no, or unclear.
  /// Uses exact phrase matching first, then token matching, to avoid loose
  /// substring false-positives (e.g. "yes not yet" → no, not yes).
  _HFVerdict _classifyResponse(String text) {
    final s = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s]"), '')
        .trim();
    if (s.isEmpty) return _HFVerdict.unclear;

    // Multi-word phrase shortcuts
    const yesPhrases = [
      'move on', 'yes please', 'go ahead', 'yes i am',
      'i am ready', 'im ready', 'yes im', 'yes i',
    ];
    const noPhrases = [
      'not yet', 'say that again', 'go back', 'hear it again',
      'hear that again', 'no not yet', 'not ready',
    ];
    for (final p in yesPhrases) {
      if (s.contains(p)) return _HFVerdict.yes;
    }
    for (final p in noPhrases) {
      if (s.contains(p)) return _HFVerdict.no;
    }

    final tokens =
        s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    const yesSet = {'yes', 'yeah', 'yep', 'ready', 'next', 'continue'};
    const noSet  = {'no', 'nope', 'repeat', 'again', 'back'};

    final hasYes = tokens.any(yesSet.contains);
    final hasNo  = tokens.any(noSet.contains);

    // "not ready" / "not yet" — negation overrides
    if (tokens.contains('not') &&
        (tokens.contains('ready') || tokens.contains('yet'))) {
      return _HFVerdict.no;
    }

    if (hasYes && !hasNo) return _HFVerdict.yes;
    if (hasNo) return _HFVerdict.no;
    return _HFVerdict.unclear;
  }

  // ── Hands-Free orchestration ─────────────────────────────────────────────

  /// Entry point for a Hands-Free cycle.  Increments [_hfGen] so any previous
  /// in-flight cycle is invalidated before the new one starts.
  Future<void> _runHandsFreeStep() async {
    if (!mounted || !_handsFree) return;

    final gen = ++_hfGen;
    if (mounted) {
      setState(() {
        _timedOut = false;
        _waitingConfirm = false;
        _listenTranscript = '';
      });
    }

    // Cancel any lingering TTS from a prior call.
    await _tts.stop();
    if (!_stillActive(gen)) return;

    // 1 ── Speak the current step.
    if (mounted) setState(() => _speaking = true);
    await _tts.speak(_currentText);
    if (mounted) setState(() => _speaking = false);
    if (!_stillActive(gen)) return;

    // 2 ── On the last step announce completion and exit cooking.
    if (_isLast) {
      if (mounted) setState(() => _speaking = true);
      await _tts.speak('Recipe complete. Enjoy your meal!');
      if (mounted) setState(() => _speaking = false);
      if (!mounted) return;
      int count = 0;
      Navigator.of(context).popUntil((_) => count++ >= 2);
      return;
    }

    // 3 ── Ask to move on.
    if (mounted) setState(() => _speaking = true);
    await _tts.speak('Are you ready to move on?');
    if (mounted) setState(() => _speaking = false);
    if (!_stillActive(gen)) return;

    // 4 ── Begin the listen/classify cycle.
    if (mounted) setState(() => _waitingConfirm = true);
    await _runListenCycle(gen);
  }

  /// Listens for a response and handles yes / no / unclear / timeout.
  /// Calls itself recursively on "unclear" (same [gen], no extra step
  /// increment).
  Future<void> _runListenCycle(int gen) async {
    if (!_stillActive(gen)) return;

    final heard = await _listenForHFResponse(gen);
    if (!_stillActive(gen)) return;

    if (mounted) setState(() => _waitingConfirm = false);

    if (heard.isEmpty) {
      // Timeout — no speech detected.  Show manual buttons without speaking
      // again (the silence is obvious to sighted users; a message would be
      // distracting for users who are still cooking).
      if (mounted) setState(() => _timedOut = true);
      return;
    }

    final verdict = _classifyResponse(heard);
    switch (verdict) {
      case _HFVerdict.yes:
        if (!mounted || !_handsFree || _hfGen != gen) return;
        setState(() {
          _step++;
          _timedOut = false;
        });
        // Fire-and-forget so _runListenCycle can return cleanly.
        _runHandsFreeStep();

      case _HFVerdict.no:
        if (!mounted || !_handsFree || _hfGen != gen) return;
        setState(() => _timedOut = false);
        _runHandsFreeStep(); // repeats the same step

      case _HFVerdict.unclear:
        if (mounted) setState(() => _speaking = true);
        await _tts.speak(
          "I didn't catch that. "
          "Say yes to continue or no to hear the step again.",
        );
        if (mounted) setState(() => _speaking = false);
        if (!_stillActive(gen)) return;
        if (mounted) setState(() => _waitingConfirm = true);
        await _runListenCycle(gen); // retry same step, same gen
    }
  }

  // ── Manual actions ───────────────────────────────────────────────────────

  Future<void> _onPrev() async {
    if (_step == 0) return;
    await _cancelVoice();
    if (!mounted) return;
    setState(() {
      _step--;
      _timedOut = false;
    });
    if (_handsFree) {
      _runHandsFreeStep();
    } else {
      _speak(_currentText);
    }
  }

  Future<void> _onNext() async {
    if (_isLast) {
      _onFinish();
      return;
    }
    await _cancelVoice();
    if (!mounted) return;
    setState(() {
      _step++;
      _timedOut = false;
    });
    if (_handsFree) {
      _runHandsFreeStep();
    } else {
      _speak(_currentText);
    }
  }

  Future<void> _onRepeat() async {
    await _cancelVoice();
    if (!mounted) return;
    setState(() => _timedOut = false);
    if (_handsFree) {
      _runHandsFreeStep();
    } else {
      _speak(_currentText);
    }
  }

  Future<void> _onFinish() async {
    await _cancelVoice();
    if (!mounted) return;
    await _speak('Recipe complete. Enjoy your meal!');
    if (!mounted) return;
    int count = 0;
    Navigator.of(context).popUntil((_) => count++ >= 2);
  }

  Future<void> _onToggleHandsFree() async {
    await _cancelVoice();
    if (!mounted) return;
    final turningOn = !_handsFree;
    setState(() => _handsFree = turningOn);
    if (turningOn) {
      await _speak('Hands-Free Mode on.');
      if (mounted && _handsFree) _runHandsFreeStep();
    } else {
      await _speak('Hands-Free Mode off.');
    }
  }

  /// Restart voice listening after a timeout, without re-reading the step.
  Future<void> _onListenAgain() async {
    if (!_handsFree) return;
    await _cancelVoice();
    if (!mounted) return;

    final gen = ++_hfGen;
    setState(() {
      _timedOut = false;
      _waitingConfirm = true;
    });

    if (mounted) setState(() => _speaking = true);
    await _tts.speak('Are you ready to move on?');
    if (mounted) setState(() => _speaking = false);
    if (!_stillActive(gen)) return;

    await _runListenCycle(gen);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isIdle =
        !_speaking && !_listening && !_waitingConfirm && !_timedOut;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recipe.name,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kBrandPurpleMid.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Step ${_step + 1} of $_total',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Progress bar ───────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / _total,
                        minHeight: 6,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kBrandPurpleLight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Step label ────────────────────────────────────
                    Text(
                      'Step ${_step + 1} of $_total',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: kBrandPurpleLight,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Hands-Free Mode toggle ────────────────────────
                    _HandsFreeToggle(
                      value: _handsFree,
                      onToggle: (_speaking || _listening)
                          ? null
                          : _onToggleHandsFree,
                    ),
                    const SizedBox(height: 12),

                    // ── Status indicator ──────────────────────────────
                    _HFStatusBar(
                      speaking: _speaking,
                      listening: _listening,
                      waitingConfirm: _waitingConfirm,
                      timedOut: _timedOut,
                      transcript: _listenTranscript,
                      handsFree: _handsFree,
                      speechAvailable: _speechAvailable,
                    ),

                    // ── Step instruction (main content) ───────────────
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: SingleChildScrollView(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white
                                    .withValues(alpha: 0.07),
                                borderRadius:
                                    BorderRadius.circular(20),
                                border: Border.all(
                                  color: kBrandPurpleLight
                                      .withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _currentText,
                                  style: theme.textTheme.bodyLarge
                                      ?.copyWith(
                                    color: Colors.white,
                                    fontSize: 22,
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Timeout prompt: extra CTA row ─────────────────
                    if (_timedOut && _handsFree) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'No response heard. Tap "Try Again" or use the buttons below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.amber,
                              fontSize: 16,
                              height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _CookingButton(
                              label: 'Repeat Step',
                              icon: Icons.replay_rounded,
                              onTap: _onRepeat,
                              outlined: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CookingButton(
                              label: 'Try Again',
                              icon: Icons.mic_rounded,
                              onTap: _onListenAgain,
                              outlined: true,
                              accent: const Color(0xFF3AE4C2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CookingButton(
                              label: 'Continue',
                              icon: Icons.arrow_forward_rounded,
                              onTap: _isLast ? _onFinish : _onNext,
                              filled: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Primary action buttons ────────────────────────
                    Row(
                      children: [
                        // Previous (only if not on first step)
                        if (_step > 0) ...[
                          _CookingButton(
                            label: '←',
                            icon: Icons.arrow_back_rounded,
                            onTap: (_speaking || _listening)
                                ? null
                                : _onPrev,
                            outlined: true,
                            fixedWidth: 56,
                          ),
                          const SizedBox(width: 10),
                        ],
                        // Repeat
                        Expanded(
                          child: _CookingButton(
                            label: 'Repeat',
                            icon: Icons.replay_rounded,
                            onTap: (isIdle || _timedOut)
                                ? _onRepeat
                                : null,
                            outlined: true,
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Next / Finish
                        Expanded(
                          flex: 2,
                          child: _CookingButton(
                            label: _isLast
                                ? 'Finish Cooking'
                                : 'Next',
                            icon: _isLast
                                ? Icons.check_circle_outline_rounded
                                : Icons.arrow_forward_rounded,
                            onTap: (isIdle || _timedOut)
                                ? _onNext
                                : null,
                            filled: true,
                            accent: _isLast
                                ? const Color(0xFF4DEBA0)
                                : kBrandPurpleLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── _HandsFreeToggle ─────────────────────────────────────────────────────────

class _HandsFreeToggle extends StatelessWidget {
  const _HandsFreeToggle({
    required this.value,
    required this.onToggle,
  });

  final bool value;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hands-Free Mode, ${value ? 'on' : 'off'}',
      button: true,
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: value
                ? kBrandPurpleLight.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: value
                  ? kBrandPurpleLight.withValues(alpha: 0.55)
                  : Colors.white24,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.mic_none_rounded,
                color: value ? kBrandPurpleLight : Colors.white38,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hands-Free Mode',
                      style: TextStyle(
                        color:
                            value ? kBrandPurpleLight : Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      value
                          ? 'On — Lumio listens for your response after each step.'
                          : 'Off — use the buttons to navigate.',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onToggle == null ? null : (_) => onToggle!(),
                activeColor: kBrandPurpleLight,
                inactiveTrackColor: Colors.white12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── _HFStatusBar ─────────────────────────────────────────────────────────────

/// Shows a contextual status message while Lumio is speaking or listening.
class _HFStatusBar extends StatelessWidget {
  const _HFStatusBar({
    required this.speaking,
    required this.listening,
    required this.waitingConfirm,
    required this.timedOut,
    required this.transcript,
    required this.handsFree,
    required this.speechAvailable,
  });

  final bool speaking;
  final bool listening;
  final bool waitingConfirm;
  final bool timedOut;
  final String transcript;
  final bool handsFree;
  final bool speechAvailable;

  @override
  Widget build(BuildContext context) {
    // Build the appropriate message; return nothing if fully idle.
    IconData? icon;
    String? text;
    Color color = Colors.white60;

    if (speaking) {
      icon = Icons.volume_up_rounded;
      text = 'Lumio is speaking…';
      color = kBrandPurpleLight.withValues(alpha: 0.85);
    } else if (listening) {
      icon = Icons.mic_rounded;
      text = transcript.isEmpty
          ? 'Listening for yes or no…'
          : 'Heard: "$transcript"';
      color = const Color(0xFF3AE4C2);
    } else if (waitingConfirm && !timedOut) {
      icon = Icons.hourglass_top_rounded;
      text = 'Waiting for your response…';
      color = Colors.white54;
    } else if (handsFree && !speechAvailable) {
      icon = Icons.mic_off_rounded;
      text =
          'Microphone unavailable — use the buttons to navigate.';
      color = Colors.orange;
    } else {
      // Idle — no bar needed.
      return const SizedBox.shrink();
    }

    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 14, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _CookingButton ───────────────────────────────────────────────────────────

class _CookingButton extends StatelessWidget {
  const _CookingButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.outlined = false,
    this.filled = false,
    this.accent,
    this.fixedWidth,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool outlined;
  final bool filled;
  final Color? accent;
  final double? fixedWidth;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? kBrandPurpleLight;
    final disabled = onTap == null;

    final child = GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: label,
        enabled: !disabled,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 60,
          width: fixedWidth,
          decoration: BoxDecoration(
            color: filled
                ? (disabled
                    ? color.withValues(alpha: 0.2)
                    : color.withValues(alpha: 0.85))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: disabled
                  ? Colors.white12
                  : color.withValues(
                      alpha: outlined ? 0.7 : 0.0),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color:
                    disabled ? Colors.white24 : Colors.white,
                size: 22,
              ),
              if (fixedWidth == null) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: disabled
                        ? Colors.white24
                        : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return fixedWidth != null ? child : child;
  }
}
