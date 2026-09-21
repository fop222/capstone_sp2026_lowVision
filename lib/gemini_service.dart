/// Gemini API integration for the "Surprise Me!" recipe suggestion feature.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'imported_recipes_state.dart' show kImportedCategory;
import 'recipe_data.dart';

/// Gemini API key — injected at build time via:
///   flutter build web --dart-define=GEMINI_API_KEY=<your_key>
/// On Vercel, set GEMINI_API_KEY as an environment variable and the
/// build script (vercel_build.sh) forwards it automatically.
const String kGeminiApiKey =
    String.fromEnvironment('GEMINI_API_KEY');

const _kGeminiEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/models/'
    'gemini-3.6-flash:generateContent';

/// Generates up to 2 recipe suggestions based on [detectedIngredients].
/// Returns an empty list on any error so the caller can show a graceful message.
Future<List<Recipe>> generateRecipeSuggestions(
  List<String> detectedIngredients,
) async {
  if (kGeminiApiKey.isEmpty || detectedIngredients.isEmpty) return [];

  final ingredientList = detectedIngredients.join(', ');

  final prompt = '''
You are a helpful cooking assistant. Based on the following ingredients found in someone's kitchen, suggest exactly 2 recipes they could make.

Detected ingredients: $ingredientList

Return ONLY a valid JSON array of exactly 2 recipe objects — no markdown, no explanation, no extra text. Each object must have exactly these fields:
{
  "name": "Recipe Name",
  "estimatedTimeMinutes": 30,
  "difficulty": 2,
  "dietaryPreferences": [],
  "ingredients": [
    {"name": "eggs", "quantity": "2"},
    {"name": "flour", "quantity": "1 cup"}
  ],
  "steps": [
    "Step 1: ...",
    "Step 2: ..."
  ]
}

Rules:
- difficulty is an integer 1–5 (1 = very easy, 5 = very hard)
- dietaryPreferences is an array of strings such as "Vegetarian", "Vegan", "Gluten-Free", "Dairy-Free" (empty array if none apply)
- ingredients must list ALL ingredients needed, not just the detected ones
- steps must be complete, numbered step-by-step cooking instructions
''';

  final uri = Uri.parse('$_kGeminiEndpoint?key=$kGeminiApiKey');

  // Try up to 3 times if Gemini times out or temporarily returns 503.
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'maxOutputTokens': 2048,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 90));

      // Successful response
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;

        final candidates = decoded['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          print('[Gemini] No candidates returned.');
          return [];
        }

        final candidate = candidates.first as Map<String, dynamic>;
        final content = candidate['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;

        if (parts == null || parts.isEmpty) {
          print('[Gemini] No content returned.');
          return [];
        }

        final rawText = parts.first['text'] as String? ?? '';

        if (rawText.isEmpty) {
          print('[Gemini] Empty response.');
          return [];
        }

        // Parse JSON output directly
        final list = jsonDecode(rawText) as List<dynamic>;

        if (list.length != 2) {
          print('[Gemini] Expected 2 recipes but received ${list.length}.');
          return [];
        }

        final ts = DateTime.now().millisecondsSinceEpoch;

        return list
            .asMap()
            .entries
            .map(
              (e) => _recipeFromMap(
                e.value as Map<String, dynamic>,
                id: 'gemini_${ts}_${e.key}',
              ),
            )
            .toList();
      }

      // Handle 503 retries
      if (response.statusCode == 503) {
        print('[Gemini] Service unavailable (503). Attempt $attempt of 3.');
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }
      }

      print('[Gemini] HTTP ${response.statusCode}: ${response.body}');
      return [];
    } on TimeoutException {
      print('[Gemini] Request timed out on attempt $attempt of 3.');
      if (attempt < 3) {
        await Future.delayed(Duration(seconds: attempt * 2));
        continue;
      }
      print('[Gemini] All retry attempts timed out.');
      return [];
    } catch (e) {
      print('[Gemini] Error: $e');
      return [];
    }
  }

  return [];
}

// ── Parser ────────────────────────────────────────────────────────────────────

Recipe _recipeFromMap(Map<String, dynamic> m, {required String id}) {
  String s(String key) => (m[key] as String? ?? '').trim();

  int i(String key, int fallback) {
    final v = m[key];

    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;

    return fallback;
  }

  // Ingredients
  final rawIngs = m['ingredients'];
  final ingredients = <RecipeIngredient>[];

  if (rawIngs is List) {
    for (final item in rawIngs) {
      if (item is Map) {
        final name = (item['name'] as String? ?? '').trim();
        final qty = (item['quantity'] as String? ?? '').trim();

        if (name.isNotEmpty) {
          ingredients.add(
            RecipeIngredient(
              name,
              quantity: qty,
            ),
          );
        }
      }
    }
  }

  // Steps
  final rawSteps = m['steps'];
  final steps = <String>[];

  if (rawSteps is List) {
    for (final step in rawSteps) {
      final text = (step as String? ?? '').trim();

      if (text.isNotEmpty) {
        steps.add(text);
      }
    }
  }

  // Dietary preferences
  final rawDiet = m['dietaryPreferences'];
  final dietaryPrefs = <String>[];

  if (rawDiet is List) {
    for (final pref in rawDiet) {
      final text = (pref as String? ?? '').trim();

      if (text.isNotEmpty) {
        dietaryPrefs.add(text);
      }
    }
  }

  if (dietaryPrefs.isEmpty) {
    dietaryPrefs.add('No Restrictions');
  }

  return Recipe(
    id: id,
    name: s('name').isEmpty ? 'Suggested Recipe' : s('name'),
    category: kImportedCategory,
    estimatedTimeMinutes: i('estimatedTimeMinutes', 30),
    difficulty: i('difficulty', 2).clamp(1, 5),
    dietaryPreferences: dietaryPrefs,
    allergens: const [],
    ingredients: ingredients,
    steps: steps,
    isRecommended: true,
  );
}