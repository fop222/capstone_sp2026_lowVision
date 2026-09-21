/// Gemini API integration for the "Surprise Me!" recipe suggestion feature.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'imported_recipes_state.dart' show kImportedCategory;
import 'recipe_data.dart';

/// Gemini API key — injected at build time via:
///   flutter build web --dart-define=GEMINI_API_KEY=<your_key>
///   flutter run -d chrome --dart-define=GEMINI_API_KEY=<your_key>
/// On Vercel, set GEMINI_API_KEY as an environment variable and the
/// build script (vercel_build.sh) forwards it automatically.
const String kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// Current Flash models. Try newest first; fall back if a name is unavailable.
const List<String> _kGeminiModels = [
  'gemini-3.6-flash',
  'gemini-3.5-flash',
  'gemini-2.5-flash',
];

const _kGeminiBase =
    'https://generativelanguage.googleapis.com/v1beta/models/';

/// Generates up to 2 recipe suggestions based on [detectedIngredients].
/// Returns an empty list on any error so the caller can show a graceful message.
Future<List<Recipe>> generateRecipeSuggestions(
  List<String> detectedIngredients,
) async {
  if (kGeminiApiKey.isEmpty) {
    print(
      '[Gemini] GEMINI_API_KEY is missing. Pass it at build/run time with '
      '--dart-define=GEMINI_API_KEY=your_key',
    );
    return [];
  }
  if (detectedIngredients.isEmpty) {
    print('[Gemini] No ingredients provided.');
    return [];
  }

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
- every quantity MUST be a string (e.g. "2", "1 cup"), never a number
- steps must be complete, numbered step-by-step cooking instructions
''';

  Map<String, dynamic> requestBody({bool includeThinkingConfig = true}) {
    final generationConfig = <String, dynamic>{
      'temperature': 0.7,
      'maxOutputTokens': 8192,
      'responseMimeType': 'application/json',
    };
    if (includeThinkingConfig) {
      generationConfig['thinkingConfig'] = {'thinkingBudget': 0};
    }
    return {
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        }
      ],
      'generationConfig': generationConfig,
    };
  }

  for (final model in _kGeminiModels) {
    final recipes = await _requestRecipes(
      model: model,
      body: jsonEncode(requestBody()),
    );
    if (recipes.isNotEmpty) return recipes;
  }

  return [];
}

Future<List<Recipe>> _requestRecipes({
  required String model,
  required String body,
}) async {
  final uri = Uri.parse('$_kGeminiBase$model:generateContent?key=$kGeminiApiKey');

  // Try up to 3 times if Gemini times out or temporarily returns 503/429.
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      print('[Gemini] Sending request to $model (attempt $attempt)...');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final recipes = _parseRecipes(response.body);
        if (recipes.isEmpty) {
          print('[Gemini] $model returned 200 but no usable recipes.');
        }
        return recipes;
      }

      if (response.statusCode == 400 && body.contains('thinkingConfig')) {
        print('[Gemini] $model rejected thinkingConfig; retrying without it.');
        final stripped = body.replaceAll(
          '"thinkingConfig":{"thinkingBudget":0},',
          '',
        ).replaceAll(
          ',"thinkingConfig":{"thinkingBudget":0}',
          '',
        );
        if (stripped != body) {
          return _requestRecipes(model: model, body: stripped);
        }
      }

      if (response.statusCode == 404) {
        print('[Gemini] Model $model is not available (404).');
        return [];
      }

      if (response.statusCode == 503 || response.statusCode == 429) {
        print(
          '[Gemini] Server busy (${response.statusCode}). Attempt $attempt of 3.',
        );
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

List<Recipe> _parseRecipes(String responseBody) {
  try {
    final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      print('[Gemini] No candidates returned. Body: $responseBody');
      return [];
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final finishReason = candidate['finishReason'];
    print('[Gemini] finishReason=$finishReason');

    final content = candidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;

    if (parts == null || parts.isEmpty) {
      print('[Gemini] No content parts returned.');
      return [];
    }

    final rawText = parts
        .map((p) {
          if (p is Map && p['text'] is String) return p['text'] as String;
          return '';
        })
        .join()
        .trim();

    if (rawText.isEmpty) {
      print('[Gemini] Empty response text.');
      return [];
    }

    final list = _extractRecipeList(rawText);
    if (list == null || list.isEmpty) {
      print('[Gemini] Could not parse recipe JSON: $rawText');
      return [];
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    return list.take(2).toList().asMap().entries.map((e) {
      final map = e.value;
      if (map is! Map) {
        throw FormatException('Recipe entry is not an object');
      }
      return _recipeFromMap(
        Map<String, dynamic>.from(map),
        id: 'gemini_${ts}_${e.key}',
      );
    }).toList();
  } catch (e) {
    print('[Gemini] Parse error: $e');
    return [];
  }
}

/// Accepts a JSON array, a `{ "recipes": [...] }` object, or markdown fences.
List<dynamic>? _extractRecipeList(String rawText) {
  var text = rawText.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
  }

  final parsed = jsonDecode(text);
  if (parsed is List) return parsed;
  if (parsed is Map) {
    final recipes = parsed['recipes'] ?? parsed['suggestions'];
    if (recipes is List) return recipes;
  }
  return null;
}

// ── Parser ────────────────────────────────────────────────────────────────────

Recipe _recipeFromMap(Map<String, dynamic> m, {required String id}) {
  String s(String key) => _asString(m[key]).trim();

  int i(String key, int fallback) {
    final v = m[key];

    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;

    return fallback;
  }

  final rawIngs = m['ingredients'];
  final ingredients = <RecipeIngredient>[];

  if (rawIngs is List) {
    for (final item in rawIngs) {
      if (item is Map) {
        final name = _asString(item['name']).trim();
        final qty = _asString(item['quantity']).trim();

        if (name.isNotEmpty) {
          ingredients.add(
            RecipeIngredient(
              name,
              quantity: qty,
            ),
          );
        }
      } else {
        final name = _asString(item).trim();
        if (name.isNotEmpty) {
          ingredients.add(RecipeIngredient(name));
        }
      }
    }
  }

  final rawSteps = m['steps'];
  final steps = <String>[];

  if (rawSteps is List) {
    for (final step in rawSteps) {
      final text = step is Map
          ? _asString(step['text'] ?? step['instruction'] ?? step['step']).trim()
          : _asString(step).trim();

      if (text.isNotEmpty) {
        steps.add(text);
      }
    }
  }

  final rawDiet = m['dietaryPreferences'];
  final dietaryPrefs = <String>[];

  if (rawDiet is List) {
    for (final pref in rawDiet) {
      final text = _asString(pref).trim();

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

String _asString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}
