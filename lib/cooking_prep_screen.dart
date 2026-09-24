/// Pre-cooking "Get Ready" preparation screen.
///
/// Displays the recipe's ingredient names (no quantities) and tool list so the
/// user can gather everything before cooking starts.  Reads both lists aloud
/// via TTS on arrival.
///
/// When **Hands-Free Mode** is enabled the screen asks "Are you ready to begin
/// cooking?" after the introduction and navigates automatically on an
/// affirmative response.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_speech.dart';
import 'app_tts.dart';
import 'cooking_mode_screen.dart';
import 'grocery_ui.dart';
import 'recipe_data.dart';

// ─────────────────────────────────────────────────────────────────────────────

enum _PrepHFVerdict { yes, no, unclear }

// ─────────────────────────────────────────────────────────────────────────────

class CookingPrepScreen extends StatefulWidget {
  const CookingPrepScreen({super.key, required this.recipe});
  final Recipe recipe;

  @override
  State<CookingPrepScreen> createState() => _CookingPrepScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _CookingPrepScreenState extends State<CookingPrepScreen> {
  final FlutterTts _tts = FlutterTts();

  // ── Hands-Free Mode ──────────────────────────────────────────────────────
  bool _handsFree = false;
  bool _speechAvailable = false;
  bool _speaking = false;
  bool _listening = false;
  bool _waitingConfirm = false;
  bool _timedOut = false;
  String _listenTranscript = '';
  int _hfGen = 0;

  Recipe get recipe => widget.recipe;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tts.awaitSpeakCompletion(true);
    _init();
  }

  Future<void> _init() async {
    try {
      _speechAvailable = await AppSpeech.I.ensureInitialized();
    } catch (_) {
      _speechAvailable = false;
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakPrep());
  }

  @override
  void dispose() {
    _hfGen++;
    _tts.stop();
    if (AppSpeech.I.stt.isListening) {
      AppSpeech.I.stt.stop();
    }
    super.dispose();
  }

  // ── Generation guard ─────────────────────────────────────────────────────

  bool _stillActive(int gen) =>
      mounted && _handsFree && _hfGen == gen;

  // ── Cancel active voice ──────────────────────────────────────────────────

  Future<void> _cancelVoice() async {
    _hfGen++;
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

  // ── TTS ─────────────────────────────────────────────────────────────────

  String _englishList(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items[0];
    final allButLast = items.sublist(0, items.length - 1).join(', ');
    return '$allButLast, and ${items.last}';
  }

  Future<void> _speakPrep() async {
    await applyEnglishTts(_tts);

    final ingNames = recipe.ingredients.map((i) => i.name).toList();
    final tools = recipe.tools;

    final buf = StringBuffer('Before you begin, ');
    if (ingNames.isNotEmpty) {
      buf.write(
          'gather your ingredients, such as ${_englishList(ingNames)}. ');
    }
    if (tools.isNotEmpty) {
      buf.write(
          'Then gather your tools, such as ${_englishList(tools)}.');
    }
    if (mounted) setState(() => _speaking = true);
    await _tts.speak(buf.toString());
    if (mounted) setState(() => _speaking = false);

    // After the intro TTS finishes, kick off the HF cycle if enabled.
    if (mounted && _handsFree) {
      final gen = ++_hfGen;
      await _askReadyToBegin(gen);
    }
  }

  // ── Hands-Free intro cycle ───────────────────────────────────────────────

  Future<void> _askReadyToBegin(int gen) async {
    if (!_stillActive(gen)) return;

    if (mounted) setState(() => _speaking = true);
    await _tts.speak('Are you ready to begin cooking?');
    if (mounted) setState(() => _speaking = false);
    if (!_stillActive(gen)) return;

    if (mounted) setState(() => _waitingConfirm = true);

    final heard = await _listenForHFResponse(gen);
    if (!_stillActive(gen)) return;

    if (mounted) setState(() => _waitingConfirm = false);

    if (heard.isEmpty) {
      if (mounted) setState(() => _timedOut = true);
      return;
    }

    final verdict = _classifyResponse(heard);
    switch (verdict) {
      case _PrepHFVerdict.yes:
        if (!_stillActive(gen)) return;
        _onStartCooking();

      case _PrepHFVerdict.no:
        if (!_stillActive(gen)) return;
        // Re-read the prep intro then ask again.
        await _speakPrep();

      case _PrepHFVerdict.unclear:
        if (mounted) setState(() => _speaking = true);
        await _tts.speak(
          "I didn't catch that. "
          "Say yes to start cooking or no to hear the ingredients again.",
        );
        if (mounted) setState(() => _speaking = false);
        if (!_stillActive(gen)) return;
        if (mounted) setState(() => _waitingConfirm = true);
        await _askReadyToBegin(gen);
    }
  }

  // ── STT ─────────────────────────────────────────────────────────────────

  Future<String> _listenForHFResponse(int gen) async {
    if (!_speechAvailable || !mounted) return '';

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

    while (AppSpeech.I.stt.isListening) {
      if (!mounted || !_stillActive(gen)) {
        await AppSpeech.I.stt.stop();
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    await Future.delayed(Duration(milliseconds: kIsWeb ? 450 : 150));

    if (mounted) {
      setState(() {
        _listening = false;
        _listenTranscript = '';
      });
    }
    return recognized.trim();
  }

  // ── Response classification ──────────────────────────────────────────────

  _PrepHFVerdict _classifyResponse(String text) {
    final s = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s]"), '')
        .trim();
    if (s.isEmpty) return _PrepHFVerdict.unclear;

    const yesPhrases = [
      'yes', 'yeah', 'yep', 'ready', 'yes i am',
      'i am ready', 'im ready', 'go ahead', 'start',
      'lets go', 'let us go', 'begin',
    ];
    const noPhrases = [
      'no', 'nope', 'not yet', 'not ready', 'again',
      'repeat', 'go back', 'hear it again',
    ];

    final tokens =
        s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    if (tokens.contains('not') &&
        (tokens.contains('ready') || tokens.contains('yet'))) {
      return _PrepHFVerdict.no;
    }

    const yesTokens = {
      'yes', 'yeah', 'yep', 'ready', 'start', 'begin', 'go'
    };
    const noTokens = {'no', 'nope', 'repeat', 'again', 'back', 'not'};

    for (final p in yesPhrases) {
      if (s == p || s.startsWith('$p ')) return _PrepHFVerdict.yes;
    }
    for (final p in noPhrases) {
      if (s == p || s.startsWith('$p ')) return _PrepHFVerdict.no;
    }

    final hasYes = tokens.any(yesTokens.contains);
    final hasNo = tokens.any(noTokens.contains);

    if (hasYes && !hasNo) return _PrepHFVerdict.yes;
    if (hasNo) return _PrepHFVerdict.no;
    return _PrepHFVerdict.unclear;
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _onStartCooking() {
    _tts.stop();
    if (AppSpeech.I.stt.isListening) AppSpeech.I.stt.stop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CookingModeScreen(recipe: recipe, handsFreeMode: _handsFree),
      ),
    );
  }

  Future<void> _onToggleHandsFree() async {
    await _cancelVoice();
    if (!mounted) return;
    setState(() => _handsFree = !_handsFree);
    // If turned on: speak the intro + ask; if turned off: just announce.
    if (_handsFree) {
      final gen = ++_hfGen;
      if (mounted) setState(() => _speaking = true);
      await _tts.speak('Hands-Free Mode on.');
      if (mounted) setState(() => _speaking = false);
      if (!_stillActive(gen)) return;
      await _askReadyToBegin(gen);
    } else {
      if (mounted) setState(() => _speaking = true);
      await _tts.speak('Hands-Free Mode off.');
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _onListenAgain() async {
    if (!_handsFree) return;
    await _cancelVoice();
    if (!mounted) return;
    final gen = ++_hfGen;
    await _askReadyToBegin(gen);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = groceryPagePadding(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name, overflow: TextOverflow.ellipsis),
      ),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: SingleChildScrollView(
                padding: padding.add(
                  const EdgeInsets.only(top: 20, bottom: 48),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Heading ──────────────────────────────────────
                    Text(
                      'Get Ready',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gather your ingredients and tools before you begin.',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),

                    // ── Hands-Free Mode toggle ────────────────────────
                    GestureDetector(
                      onTap: (_speaking || _listening)
                          ? null
                          : _onToggleHandsFree,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _handsFree
                              ? kBrandPurpleLight.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _handsFree
                                ? kBrandPurpleLight.withValues(alpha: 0.55)
                                : Colors.white24,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.mic_none_rounded,
                              color: _handsFree
                                  ? kBrandPurpleLight
                                  : Colors.white38,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hands-Free Mode',
                                    style: TextStyle(
                                      color: _handsFree
                                          ? kBrandPurpleLight
                                          : Colors.white70,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const Text(
                                    'When on, Lumio reads each instruction aloud and listens for your response.',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _handsFree,
                              onChanged: (_speaking || _listening)
                                  ? null
                                  : (_) => _onToggleHandsFree(),
                              activeColor: kBrandPurpleLight,
                              inactiveTrackColor: Colors.white12,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── HF status bar ─────────────────────────────────
                    if (_speaking || _listening ||
                        _waitingConfirm || _timedOut) ...[
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _timedOut
                                ? Colors.amber.withValues(alpha: 0.10)
                                : kBrandPurpleLight
                                    .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _speaking
                                    ? Icons.volume_up_rounded
                                    : _listening
                                        ? Icons.mic_rounded
                                        : _timedOut
                                            ? Icons.timer_off_rounded
                                            : Icons.hourglass_top_rounded,
                                size: 16,
                                color: _listening
                                    ? const Color(0xFF3AE4C2)
                                    : _timedOut
                                        ? Colors.amber
                                        : kBrandPurpleLight,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _speaking
                                      ? 'Lumio is speaking…'
                                      : _listening
                                          ? (_listenTranscript.isEmpty
                                              ? 'Listening…'
                                              : 'Heard: "$_listenTranscript"')
                                          : _timedOut
                                              ? 'No response heard.'
                                              : 'Waiting for your response…',
                                  style: TextStyle(
                                    color: _listening
                                        ? const Color(0xFF3AE4C2)
                                        : _timedOut
                                            ? Colors.amber
                                            : kBrandPurpleLight,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Ingredients ───────────────────────────────────
                    if (recipe.ingredients.isNotEmpty) ...[
                      _SectionCard(
                        icon: Icons.egg_alt_outlined,
                        title: 'Ingredients',
                        color: kBrandPurpleLight,
                        items:
                            recipe.ingredients.map((i) => i.name).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Tools ─────────────────────────────────────────
                    if (recipe.tools.isNotEmpty) ...[
                      _SectionCard(
                        icon: Icons.kitchen_outlined,
                        title: 'Tools',
                        color: const Color(0xFF4DEBA0),
                        items: recipe.tools,
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      const SizedBox(height: 16),
                    ],

                    // ── Timeout: Try Again button ─────────────────────
                    if (_timedOut && _handsFree) ...[
                      GestureDetector(
                        onTap: _onListenAgain,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFF3AE4C2)
                                    .withValues(alpha: 0.7)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.mic_rounded,
                                  color: Color(0xFF3AE4C2)),
                              SizedBox(width: 8),
                              Text(
                                'Try Again',
                                style: TextStyle(
                                  color: Color(0xFF3AE4C2),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Start Cooking button ──────────────────────────
                    GroceryGlowButton(
                      onPressed: (_speaking || _listening)
                          ? null
                          : _onStartCooking,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_fire_department_outlined,
                              size: 24),
                          SizedBox(width: 10),
                          Text(
                            'Start Cooking',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
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

// ─── _SectionCard ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.items,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final item in items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ',
                      style: TextStyle(color: color, fontSize: 20)),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
