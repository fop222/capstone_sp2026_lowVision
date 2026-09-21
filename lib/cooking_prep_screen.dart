/// Pre-cooking "Get Ready" preparation screen.
///
/// Displays the recipe's ingredient names (no quantities) and tool list so the
/// user can gather everything before cooking starts.  Reads both lists aloud
/// via TTS on arrival.  A large "Start Cooking" button launches
/// [CookingModeScreen].
library;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_tts.dart';
import 'cooking_mode_screen.dart';
import 'grocery_ui.dart';
import 'recipe_data.dart';

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

  Recipe get recipe => widget.recipe;

  @override
  void initState() {
    super.initState();
    _tts.awaitSpeakCompletion(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakPrep());
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // ── TTS ─────────────────────────────────────────────────────────────────────

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
      buf.write('Then gather your tools, such as ${_englishList(tools)}.');
    }

    await _tts.speak(buf.toString());
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  void _onStartCooking() {
    // Stop prep-screen TTS before handing off to CookingModeScreen,
    // so the Web Speech synthesis queue is clear when the new screen starts.
    _tts.stop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CookingModeScreen(recipe: recipe),
      ),
    );
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
                    // ── Heading ────────────────────────────────────────────
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
                    const SizedBox(height: 28),

                    // ── Ingredients ───────────────────────────────────────
                    if (recipe.ingredients.isNotEmpty) ...[
                      _SectionCard(
                        icon: Icons.egg_alt_outlined,
                        title: 'Ingredients',
                        color: kBrandPurpleLight,
                        items: recipe.ingredients
                            .map((i) => i.name)
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Tools ─────────────────────────────────────────────
                    if (recipe.tools.isNotEmpty) ...[
                      _SectionCard(
                        icon: Icons.kitchen_outlined,
                        title: 'Tools',
                        color: const Color(0xFF4DEBA0),
                        items: recipe.tools,
                      ),
                      const SizedBox(height: 32),
                    ] else ...[
                      const SizedBox(height: 16),
                    ],

                    // ── Start Cooking button ──────────────────────────────
                    GroceryGlowButton(
                      onPressed: _onStartCooking,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_fire_department_outlined, size: 24),
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
          // Section header
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
          // Items
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
