/// Auditory Cooking Mode — displays and reads one step at a time.
///
/// Navigated to from [CookingPrepScreen].  Uses TTS to automatically read
/// each step aloud.  The user can move forward (Next), repeat the current
/// step (Repeat), or finish on the last step (Finish Cooking).
library;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_tts.dart';
import 'grocery_ui.dart';
import 'recipe_data.dart';

// ─────────────────────────────────────────────────────────────────────────────

class CookingModeScreen extends StatefulWidget {
  const CookingModeScreen({super.key, required this.recipe});
  final Recipe recipe;

  @override
  State<CookingModeScreen> createState() => _CookingModeScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _CookingModeScreenState extends State<CookingModeScreen> {
  int _step = 0; // 0-indexed
  bool _speaking = false;
  final FlutterTts _tts = FlutterTts();

  // ── Convenience getters ──────────────────────────────────────────────────

  List<String> get _steps => widget.recipe.steps;
  int get _total => _steps.length;
  bool get _isLast => _step == _total - 1;
  String get _currentText => _steps[_step];

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Initialise TTS engine and speak the first step.
    // We do this asynchronously so the screen can render first, and we add
    // a short pause so the Web Speech synthesis queue is fully settled after
    // the prep screen's TTS has stopped.
    _initTtsAndSpeakFirst();
  }

  Future<void> _initTtsAndSpeakFirst() async {
    await applyEnglishTts(_tts);
    // Give the navigation animation and the Web Speech API time to settle.
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    await _tts.stop(); // ensure no prior utterance is queued
    setState(() => _speaking = true);
    await _tts.speak(_currentText);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // ── TTS ─────────────────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    if (!mounted) return;
    await _tts.stop(); // cancel any in-progress utterance first
    setState(() => _speaking = true);
    await _tts.speak(text);
    if (mounted) setState(() => _speaking = false);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _onNext() {
    if (_isLast) {
      _onFinish();
      return;
    }
    setState(() => _step++);
    _speak(_currentText);
  }

  void _onRepeat() => _speak(_currentText);

  Future<void> _onFinish() async {
    await _speak('Recipe complete. Enjoy your meal!');
    if (!mounted) return;
    // Pop back past both CookingModeScreen AND CookingPrepScreen → RecipeDetail.
    int count = 0;
    Navigator.of(context).popUntil((_) => count++ >= 2);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recipe.name,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Progress chip in app bar
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    // ── Progress bar ─────────────────────────────────────
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
                    const SizedBox(height: 20),

                    // ── Step label ───────────────────────────────────────
                    Text(
                      'Step ${_step + 1} of $_total',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: kBrandPurpleLight,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Step instruction (main content) ──────────────────
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: kBrandPurpleLight
                                    .withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              _currentText,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: Colors.white,
                                fontSize: 22,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Speaking indicator ───────────────────────────────
                    if (_speaking) ...[
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kBrandPurpleLight
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Reading aloud…',
                              style: TextStyle(
                                color: kBrandPurpleLight
                                    .withValues(alpha: 0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Action buttons ────────────────────────────────────
                    Row(
                      children: [
                        // Repeat button
                        Expanded(
                          child: _CookingButton(
                            label: 'Repeat',
                            icon: Icons.replay_rounded,
                            onTap: _speaking ? null : _onRepeat,
                            outlined: true,
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Next / Finish button
                        Expanded(
                          flex: 2,
                          child: _CookingButton(
                            label:
                                _isLast ? 'Finish Cooking' : 'Next',
                            icon: _isLast
                                ? Icons.check_circle_outline_rounded
                                : Icons.arrow_forward_rounded,
                            onTap: _speaking ? null : _onNext,
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

// ─── _CookingButton ───────────────────────────────────────────────────────────

class _CookingButton extends StatelessWidget {
  const _CookingButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.outlined = false,
    this.filled = false,
    this.accent,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool outlined;
  final bool filled;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? kBrandPurpleLight;
    final disabled = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 60,
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
                : color.withValues(alpha: outlined ? 0.7 : 0.0),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: disabled ? Colors.white24 : Colors.white,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: disabled ? Colors.white24 : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
