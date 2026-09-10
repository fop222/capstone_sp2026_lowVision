import 'package:flutter/material.dart';

import 'grocery_ui.dart';
import 'imported_recipes_state.dart';
import 'recipe_data.dart';
import 'recipe_detail_screen.dart';
import 'recipe_import_screen.dart';
import 'recipe_widgets.dart';

/// One vertically scrollable page showing all 10 recipes organised into
/// three clearly separated sections: Breakfast → Entrées → Desserts.
/// Imported recipes (session-only) appear beneath a 4th "Imported Recipes"
/// section when present.
///
/// Tapping any recipe card navigates to [RecipeDetailScreen].
class RecipeListScreen extends StatelessWidget {
  const RecipeListScreen({super.key});

  void _openRecipe(BuildContext context, Recipe recipe) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetailScreen(recipe: recipe),
      ),
    );
  }

  void _openImport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RecipeImportScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever imported recipes change.
    return ValueListenableBuilder<List<Recipe>>(
      valueListenable: importedRecipesNotifier,
      builder: (context, importedRecipes, _) =>
          _RecipeListBody(
            importedRecipes: importedRecipes,
            onOpenRecipe: (r) => _openRecipe(context, r),
            onOpenImport: () => _openImport(context),
          ),
    );
  }
}

// ─── Body (rebuilt when imports change) ──────────────────────────────────────

class _RecipeListBody extends StatelessWidget {
  const _RecipeListBody({
    required this.importedRecipes,
    required this.onOpenRecipe,
    required this.onOpenImport,
  });

  final List<Recipe> importedRecipes;
  final void Function(Recipe) onOpenRecipe;
  final VoidCallback onOpenImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = groceryPagePadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
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
                  const EdgeInsets.only(top: 24, bottom: 48),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Page header ──────────────────────────────────────
                    Semantics(
                      header: true,
                      child: Text(
                        'Recipes',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose a recipe to start cooking',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),

                    // ── Import button ────────────────────────────────────
                    const SizedBox(height: 20),
                    Semantics(
                      button: true,
                      label: 'Import recipe from a website link',
                      child: _ImportButton(onTap: onOpenImport),
                    ),

                    // ── Built-in category sections ───────────────────────
                    for (final category in kRecipeCategories) ...[
                      RecipeSectionHeader(title: category),
                      for (final recipe in kAllRecipes
                          .where((r) => r.category == category)) ...[
                        _RecipeCard(
                          recipe: recipe,
                          onTap: () => onOpenRecipe(recipe),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],

                    // ── Imported recipes (session-only) ──────────────────
                    if (importedRecipes.isNotEmpty) ...[
                      // Group by category
                      for (final category in [
                        ...kRecipeCategories,
                        kImportedCategory,
                      ]) ...[
                        if (importedRecipes.any((r) => r.category == category)) ...[
                          RecipeSectionHeader(
                            title: category == kImportedCategory
                                ? kImportedCategory
                                : '$category (Imported)',
                          ),
                          for (final recipe in importedRecipes
                              .where((r) => r.category == category)) ...[
                            _RecipeCard(
                              recipe: recipe,
                              onTap: () => onOpenRecipe(recipe),
                              isImported: true,
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ],
                    ],
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

// ─── _ImportButton ────────────────────────────────────────────────────────────

class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: kBrandPurpleLight.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link_rounded, color: kBrandPurpleLight, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Import Recipe from Link',
                  style: TextStyle(
                    color: kBrandPurpleLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── _RecipeCard ──────────────────────────────────────────────────────────────

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.onTap,
    this.isImported = false,
  });

  final Recipe recipe;
  final VoidCallback onTap;
  final bool isImported;

  /// Full accessible description read by screen readers.
  String _semanticLabel() {
    final parts = <String>[
      recipe.name,
      '${recipe.estimatedTimeMinutes} minutes',
      'Difficulty ${recipe.difficulty} out of 5',
    ];
    final prefs = recipe.displayDietaryPreferences;
    if (prefs.isNotEmpty) parts.add('Dietary: ${prefs.join(', ')}');
    if (recipe.allergens.isNotEmpty) {
      parts.add('Allergens: ${recipe.allergens.join(', ')}');
    }
    parts.add('Tap to view recipe');
    return parts.join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: _semanticLabel(),
      excludeSemantics: true,
      child: _CardShell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Recipe name + chevron ─────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    recipe.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isImported) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: kBrandPurpleMid.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Imported',
                      style: TextStyle(
                        fontSize: 11,
                        color: kBrandPurpleLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Colors.white38,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Time + difficulty ─────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 16,
                  color: kBrandPurpleLight,
                ),
                const SizedBox(width: 5),
                Text(
                  '~${recipe.estimatedTimeMinutes} min',
                  style: TextStyle(
                    fontSize: 15,
                    color: kBrandPurpleLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                RecipeDifficultyRow(difficulty: recipe.difficulty),
              ],
            ),

            // ── Dietary preference tags ───────────────────────────────────
            if (recipe.displayDietaryPreferences.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final pref in recipe.displayDietaryPreferences)
                    RecipeTag.dietary(label: pref),
                ],
              ),
            ],

            // ── Allergen tags ─────────────────────────────────────────────
            if (recipe.allergens.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 6),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: kAllergenOrange,
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final allergen in recipe.allergens)
                          RecipeTag.allergen(label: allergen),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── _CardShell ───────────────────────────────────────────────────────────────

/// Tappable gradient card shell that matches [GroceryListCardShell] visually
/// but supports an [onTap] handler and renders an ink-ripple on press.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Outer container provides the shadow (must live outside ClipRRect so it
    // is not clipped away).
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: kBrandPurpleMid.withValues(alpha: 0.1),
            blurRadius: 22,
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            // Ripple colour matches brand purple so it is visible on dark bg.
            splashColor: kBrandPurpleMid.withValues(alpha: 0.2),
            highlightColor: kBrandPurpleMid.withValues(alpha: 0.08),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF252344).withValues(alpha: 0.97),
                    const Color(0xFF1A1D2E),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
