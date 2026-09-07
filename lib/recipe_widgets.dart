/// Shared recipe UI components.
///
/// Used by both RecipeListScreen and RecipeDetailScreen to keep visual
/// language consistent without duplicating code.
library;

import 'package:flutter/material.dart';

import 'grocery_ui.dart'; // kBrandPurpleMid, kBrandPurpleLight, kAccentMint

// ─── Constants ────────────────────────────────────────────────────────────────

/// Warning orange for allergen chips — matches the EATING button on the
/// home landing screen so it is already in-system.
const Color kAllergenOrange = Color(0xFFFF8C5A);

// ─── RecipeTag ────────────────────────────────────────────────────────────────

/// A small rounded pill chip used for dietary preference or allergen labels.
///
/// Dietary preference chips use the brand mint accent.
/// Allergen chips use the in-system warning orange.
///
/// Both variants always show a text label (color is never the sole signal).
class RecipeTag extends StatelessWidget {
  /// Dietary preference tag (mint styling).
  const RecipeTag.dietary({super.key, required this.label})
      : _isDietary = true;

  /// Allergen tag (orange warning styling).
  const RecipeTag.allergen({super.key, required this.label})
      : _isDietary = false;

  final String label;
  final bool _isDietary;

  @override
  Widget build(BuildContext context) {
    final Color textColor = _isDietary ? kAccentMint : kAllergenOrange;
    final Color bgColor = textColor.withValues(alpha: 0.14);
    final Color borderColor = textColor.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textColor,
          height: 1.2,
        ),
      ),
    );
  }
}

// ─── RecipeDifficultyRow ──────────────────────────────────────────────────────

/// Displays a star rating alongside a numeric label, e.g. "★★★☆☆  3 / 5".
///
/// Uses [Icons.star_rounded] / [Icons.star_outline_rounded] from the
/// existing Material icon set — no new icon libraries required.
class RecipeDifficultyRow extends StatelessWidget {
  const RecipeDifficultyRow({super.key, required this.difficulty});

  final int difficulty;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Difficulty $difficulty out of 5',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Difficulty: ',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            for (int i = 1; i <= 5; i++)
              Icon(
                i <= difficulty
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 17,
                color: i <= difficulty
                    ? const Color(0xFFFFD700)
                    : Colors.white24,
              ),
            const SizedBox(width: 5),
            Text(
              '$difficulty / 5',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── RecipeSectionHeader ──────────────────────────────────────────────────────

/// Bold section heading for Breakfast, Entrées, Desserts.
/// Marked as a semantic header for screen readers.
class RecipeSectionHeader extends StatelessWidget {
  const RecipeSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 36, bottom: 18),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            // Left accent bar — mirrors the style of other section dividers
            // in the app's grocery UI.
            Container(
              width: 4,
              height: 30,
              decoration: BoxDecoration(
                color: kBrandPurpleMid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── RecipeDetailSectionHeading ───────────────────────────────────────────────

/// Section heading used on the recipe detail page (Ingredients, Tools, etc.).
class RecipeDetailSectionHeading extends StatelessWidget {
  const RecipeDetailSectionHeading({
    super.key,
    required this.title,
    this.color,
  });

  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          color: color ?? Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
