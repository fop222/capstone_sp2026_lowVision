/// Session-only in-memory store for user-imported recipes.
///
/// This is a plain [ValueNotifier] — its value lives only for the current
/// browser/app session and is automatically cleared on page refresh or restart.
/// Nothing is written to Supabase, localStorage, or any persistent storage.
library;

import 'package:flutter/foundation.dart';
import 'recipe_data.dart';

/// The single source of truth for imported recipes this session.
final importedRecipesNotifier = ValueNotifier<List<Recipe>>([]);

/// Append [recipe] to the session list.
void addImportedRecipe(Recipe recipe) {
  importedRecipesNotifier.value = [
    ...importedRecipesNotifier.value,
    recipe,
  ];
}

/// The extra category label used for recipes whose category cannot be
/// determined from the imported data.
const String kImportedCategory = 'Imported Recipes';

/// Returns true if [listTitle] matches any currently-imported recipe name.
/// Complements [isRecipeList] from recipe_data.dart which covers the 10
/// built-in recipes.
bool isImportedRecipeList(String listTitle) =>
    importedRecipesNotifier.value.any((r) => r.name == listTitle);
