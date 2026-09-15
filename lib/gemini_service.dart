/// Gemini API integration for the "Surprise Me!" recipe suggestion feature.
///
/// Currently STUBBED — returns an empty list until the API key is provided.
/// When the key is ready, replace [_kGeminiApiKey] and implement the body of
/// [generateRecipeSuggestions].
library;

import 'recipe_data.dart';

/// TODO: paste Gemini API key here when available.
const String kGeminiApiKey = '';

/// Generates up to 5 recipe suggestions based on [detectedIngredients].
///
/// Returns an empty list while [kGeminiApiKey] is empty (stub mode).
/// The caller ([SurpriseMeScanScreen]) gracefully handles the empty result.
Future<List<Recipe>> generateRecipeSuggestions(
  List<String> detectedIngredients,
) async {
  if (kGeminiApiKey.isEmpty) {
    // ── Stub ──────────────────────────────────────────────────────────────
    // API key not yet configured.  Return empty so the screen shows the
    // "coming soon" message without crashing.
    return [];
  }

  // ── TODO: Real Gemini implementation ──────────────────────────────────────
  // 1. Build a prompt:
  //      "Given these ingredients: [egg, milk, flour, ...], suggest 5 simple
  //       recipes. For each recipe, provide: name, estimated cook time in
  //       minutes (integer), difficulty 1-5, ingredients list with quantities,
  //       and brief step-by-step instructions."
  // 2. POST to https://generativelanguage.googleapis.com/v1beta/models/
  //    gemini-pro:generateContent with the API key in a query param.
  // 3. Parse the JSON response into List<Recipe> objects, each with
  //    isRecommended: true.
  return [];
}
