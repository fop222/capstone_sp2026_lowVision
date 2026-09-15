/// Session-only in-memory store for Gemini-recommended recipes.
///
/// Populated by [SurpriseMeScanScreen] after the user finishes scanning
/// and Gemini returns suggestions.  Cleared on page refresh / restart.
library;

import 'package:flutter/foundation.dart';
import 'recipe_data.dart';

/// The single source of truth for recommended recipes this session.
final recommendedRecipesNotifier = ValueNotifier<List<Recipe>>([]);

/// Replace the current recommendation list.
void setRecommendedRecipes(List<Recipe> recipes) {
  recommendedRecipesNotifier.value = recipes;
}

/// Clear all recommendations.
void clearRecommendedRecipes() {
  recommendedRecipesNotifier.value = [];
}

const String kRecommendedCategory = 'Recommended Recipes';

/// Returns true if [listTitle] matches any recommended recipe name.
bool isRecommendedRecipeList(String listTitle) =>
    recommendedRecipesNotifier.value.any((r) => r.name == listTitle);
