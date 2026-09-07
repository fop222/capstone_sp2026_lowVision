import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'grocery_list_screen.dart';
import 'grocery_ui.dart';
import 'recipe_data.dart';
import 'recipe_widgets.dart';

/// Full detail view for a single recipe.
///
/// Shows all metadata (time, difficulty, dietary preferences, allergens) and
/// placeholder sections for Ingredients, Tools, and Instructions that will be
/// populated once the content is provided.
class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipe});

  final Recipe recipe;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  bool _startingShop = false;

  Recipe get recipe => widget.recipe;

  /// Creates a new grocery list named after the recipe, inserts all
  /// ingredients as items, then navigates to the main shopping screen.
  Future<void> _startShopping() async {
    setState(() => _startingShop = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in.');

      // 1. Create the grocery list.
      final listResult = await client
          .from('grocery_lists')
          .insert({'user_id': userId, 'title': recipe.name})
          .select('id')
          .single();
      final listId = listResult['id'] as String;

      // 2. Insert all ingredients as grocery items.
      if (recipe.ingredients.isNotEmpty) {
        await client.from('grocery_items').insert([
          for (final ingredient in recipe.ingredients)
            {
              'list_id': listId,
              'user_id': userId,
              'name': ingredient,
              'category': '',
              'is_checked': false,
              'quantity': 1,
            },
        ]);
      }

      // 3. Navigate to the main shopping screen. Pop everything so the user
      //    lands cleanly on the grocery list home.
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const GroceryListScreen(),
        ),
        // Keep the route below (HomeLandingScreen) so the back arrow works.
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start shopping: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _startingShop = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = groceryPagePadding(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          recipe.name,
          // Truncate long titles gracefully on small screens.
          overflow: TextOverflow.ellipsis,
        ),
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
                  const EdgeInsets.only(top: 28, bottom: 48),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Recipe name ─────────────────────────────────────────
                    Semantics(
                      header: true,
                      child: Text(
                        recipe.name,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Time + difficulty ───────────────────────────────────
                    Semantics(
                      label:
                          '${recipe.estimatedTimeMinutes} minutes. Difficulty ${recipe.difficulty} out of 5.',
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 20,
                              color: kBrandPurpleLight,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '~${recipe.estimatedTimeMinutes} min',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: kBrandPurpleLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 20),
                            RecipeDifficultyRow(difficulty: recipe.difficulty),
                          ],
                        ),
                      ),
                    ),

                    // ── Dietary preference tags ─────────────────────────────
                    if (recipe.displayDietaryPreferences.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      RecipeDetailSectionHeading(title: 'Dietary Preferences'),
                      const SizedBox(height: 10),
                      Semantics(
                        label:
                            'Dietary Preferences: ${recipe.displayDietaryPreferences.join(', ')}',
                        child: ExcludeSemantics(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final pref
                                  in recipe.displayDietaryPreferences)
                                RecipeTag.dietary(label: pref),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // ── Allergen tags ───────────────────────────────────────
                    if (recipe.allergens.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      RecipeDetailSectionHeading(
                        title: 'Allergens',
                        color: kAllergenOrange,
                      ),
                      const SizedBox(height: 10),
                      Semantics(
                        label: 'Allergens: ${recipe.allergens.join(', ')}',
                        child: ExcludeSemantics(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, right: 8),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: kAllergenOrange,
                                ),
                              ),
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final allergen in recipe.allergens)
                                      RecipeTag.allergen(label: allergen),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 28),

                    // ── Ingredients ─────────────────────────────────────────
                    _ContentSection(
                      title: 'Ingredients',
                      items: recipe.ingredients,
                    ),

                    const SizedBox(height: 28),

                    // ── Tools ───────────────────────────────────────────────
                    _ContentSection(
                      title: 'Tools',
                      items: recipe.tools,
                    ),

                    const SizedBox(height: 28),

                    // ── Instructions ────────────────────────────────────────
                    _InstructionsSection(steps: recipe.steps),

                    const SizedBox(height: 36),

                    // ── Start Shopping CTA ──────────────────────────────────
                    // Shown only when the recipe has ingredients to shop for.
                    if (recipe.ingredients.isNotEmpty) ...[
                      Semantics(
                        button: true,
                        label: 'Start shopping for ${recipe.name}',
                        child: GroceryGlowButton(
                          onPressed:
                              _startingShop ? null : _startShopping,
                          child: _startingShop
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.shopping_cart_outlined,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Start Shopping'),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ── Start Cooking CTA ───────────────────────────────────
                    // Disabled until cooking steps have been populated.
                    if (!recipe.hasDetails || recipe.steps.isEmpty) ...[
                      Center(
                        child: Text(
                          'Cooking steps coming soon.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white38,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    GroceryGlowButton(
                      // Enabled only once cooking steps are available.
                      onPressed:
                          recipe.steps.isNotEmpty ? () {} : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.local_fire_department_outlined,
                              size: 22),
                          const SizedBox(width: 10),
                          const Text('Start Cooking'),
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

// ─── _ContentSection (Ingredients / Tools) ───────────────────────────────────

/// Renders a section heading with either a bullet list or a placeholder.
class _ContentSection extends StatelessWidget {
  const _ContentSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecipeDetailSectionHeading(title: title),
        const SizedBox(height: 10),
        if (items.isEmpty)
          _PlaceholderText()
        else
          for (final item in items) _BulletItem(text: item),
      ],
    );
  }
}

// ─── _InstructionsSection ─────────────────────────────────────────────────────

/// Renders numbered steps or a placeholder when steps are not yet available.
class _InstructionsSection extends StatelessWidget {
  const _InstructionsSection({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RecipeDetailSectionHeading(title: 'Instructions'),
        const SizedBox(height: 10),
        if (steps.isEmpty)
          _PlaceholderText()
        else
          for (int i = 0; i < steps.length; i++)
            _StepItem(number: i + 1, text: steps[i]),
      ],
    );
  }
}

// ─── Shared detail-page helpers ───────────────────────────────────────────────

class _PlaceholderText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Recipe details coming soon.',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white38,
          ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 8),
            child: Text(
              '•',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 18,
                height: 1,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white70,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $number: $text',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: kBrandPurpleMid,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
