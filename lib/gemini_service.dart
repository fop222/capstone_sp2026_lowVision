/// Gemini API integration for the "Surprise Me!" recipe suggestion feature.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_keys.dart' show kGeminiApiKey;
import 'recipe_data.dart';

const _kGeminiEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/models/'
    'gemini-1.5-flash:generateContent';

/// Generates up to 5 recipe suggestions based on [detectedIngredients].
/// Returns an empty list on any error so the caller can show a graceful message.
Future<List<Recipe>> generateRecipeSuggestions(
  List<String> detectedIngredients,
) async {
  if (kGeminiApiKey.isEmpty || detectedIngredients.isEmpty) return [];

  final ingredientList = detectedIngredients.join(', ');

  final prompt = '''
You are a helpful cooking assistant. Based on the following ingredients found in someone's kitchen, suggest exactly 5 recipes they could make.

Detected ingredients: $ingredientList

Return ONLY a valid JSON array of exactly 5 recipe objects — no markdown, no explanation, no extra text. Each object must have exactly these fields:
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
- Return ONLY the JSON array, nothing else
''';

  try {
    final uri = Uri.parse('$_kGeminiEndpoint?key=$kGeminiApiKey');
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
              'temperature': 0.7,
              'maxOutputTokens': 4096,
            },
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      print('[Gemini] HTTP ${response.statusCode}: ${response.body}');
      return [];
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rawText = (decoded['candidates'] as List?)
            ?.firstOrNull
            ?['content']?['parts']
            ?[0]?['text'] as String? ??
        '';

    if (rawText.isEmpty) return [];

    // Extract the JSON array even if the model wraps it in backticks.
    final match =
        RegExp(r'\[[\s\S]*\]', dotAll: true).firstMatch(rawText);
    if (match == null) {
      print('[Gemini] Could not find JSON array in response:\n$rawText');
      return [];
    }

    final list = jsonDecode(match.group(0)!) as List<dynamic>;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return list
        .asMap()
        .entries
        .map((e) => _recipeFromMap(e.value as Map<String, dynamic>,
            id: 'gemini_${ts}_${e.key}'))
        .toList();
  } catch (e) {
    print('[Gemini] Error: $e');
    return [];
  }
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
        if (name.isNotEmpty) ingredients.add(RecipeIngredient(name, quantity: qty));
      }
    }
  }

  // Steps
  final rawSteps = m['steps'];
  final steps = <String>[];
  if (rawSteps is List) {
    for (final step in rawSteps) {
      final text = (step as String? ?? '').trim();
      if (text.isNotEmpty) steps.add(text);
    }
  }

  // Dietary preferences
  final rawDiet = m['dietaryPreferences'];
  final dietaryPrefs = <String>[];
  if (rawDiet is List) {
    for (final pref in rawDiet) {
      final text = (pref as String? ?? '').trim();
      if (text.isNotEmpty) dietaryPrefs.add(text);
    }
  }
  if (dietaryPrefs.isEmpty) dietaryPrefs.add('No Restrictions');

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
