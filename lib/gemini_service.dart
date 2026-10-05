/// Gemini API integration for recipe suggestions and screenshot extraction.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ocr_config.dart';

import 'imported_recipes_state.dart' show kImportedCategory;
import 'recipe_data.dart';

/// Gemini API key — injected at build time via:
///   flutter build web --dart-define=GEMINI_API_KEY=<your_key>
///   flutter run -d chrome --dart-define=GEMINI_API_KEY=<your_key>
/// On Vercel, set GEMINI_API_KEY as an environment variable and the
/// build script (vercel_build.sh) forwards it automatically.
const String kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// Prefer high-capacity Flash models. 3.6 often returns 503 under load,
/// so it is last — we skip to the next model immediately on 503/429.
const List<String> _kGeminiModels = [
  'gemini-2.5-flash',
  'gemini-3.5-flash-lite',
  'gemini-3.5-flash',
  'gemini-3.8-flash',
  'gemini-flash-latest',
  'gemini-3.6-flash',
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
You are a cooking assistant for a low-vision app called Lumio. Based on the following ingredients found in a user's kitchen, suggest exactly 2 recipes they could make.

Detected ingredients: $ingredientList

Return ONLY a valid JSON array of exactly 2 recipe objects — no markdown, no explanation, no code fences, no extra text. Each object must use exactly these fields:

{
  "name": "Recipe Name",
  "estimatedTimeMinutes": 30,
  "difficulty": 2,
  "dietaryPreferences": [],
  "tools": ["Large skillet", "Mixing bowl", "Spatula"],
  "ingredients": [
    {"name": "eggs", "quantity": "2 large"},
    {"name": "olive oil", "quantity": "1 tablespoon"}
  ],
  "steps": [
    "Heat 1 tablespoon of olive oil in a large skillet over medium heat for 1 minute.",
    "Crack 2 large eggs into the skillet and cook for 3 minutes until the whites are set.",
    "Season with a pinch of salt and serve immediately."
  ]
}

Strict rules:
1. Generate EXACTLY 2 recipes — no more, no less.
2. difficulty is an integer 1–5 (1 = very easy, 5 = very hard).
3. dietaryPreferences is an array such as ["Vegetarian"] or [] if none apply.
4. tools lists the equipment needed (e.g. "Large skillet", "Baking pan", "Mixing bowl").
5. ingredients lists ALL ingredients needed, not just the detected ones.
6. Every quantity MUST be a string such as "2", "1 cup", or "½ teaspoon" — never a number.
7. EACH STEP must include the exact amount of any ingredient used in that step (e.g. "Add 2 cups of flour" NOT "Add the flour").
8. Include cooking times, temperatures (°F), and heat levels (low / medium / high) inside the relevant step.
9. Keep each step concise, direct, and self-contained — the user hears only one step at a time.
10. Do NOT split one simple action into several tiny sub-steps.
11. Use sensory cues when helpful for low vision users (e.g. "until a toothpick comes out clean", "until it feels dense").
12. Do NOT use vague instructions like "add ingredients" or "cook until done".
13. If multiple ingredients appear in the photo, attempt to generate a recipe that involves all the ingredients in a sensible way. If they are completely polar opposite ingredients, don't attempt to generate a recipe for things that don't go together
14. Attempt to create recipes that have more than 1 ingredient if possible



Example of correct step format:
"Pour 1 box of brownie mix into a large mixing bowl. Add 3 tablespoons of water, ½ cup of vegetable oil, and 2 large eggs. Stir for 1 minute until the batter is smooth with no dry powder."

Example of WRONG step format (never do this):
"Add the eggs." / "Mix the batter." / "Cook it."
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

  final bodyWithThinking = jsonEncode(requestBody());
  final bodyWithoutThinking = jsonEncode(requestBody(includeThinkingConfig: false));

  // Two passes: first try every model, then wait and try the list once more.
  for (int pass = 1; pass <= 2; pass++) {
    if (pass == 2) {
      print('[Gemini] All models busy; waiting 5s and retrying...');
      await Future.delayed(const Duration(seconds: 5));
    }
    for (final model in _kGeminiModels) {
      var recipes = await _requestRecipes(model: model, body: bodyWithThinking);
      if (recipes == null) {
        recipes = await _requestRecipes(model: model, body: bodyWithoutThinking);
      }
      if (recipes != null && recipes.isNotEmpty) return recipes;
    }
  }

  return [];
}

/// Returns parsed recipes, an empty list if the model responded but was
/// unusable, or null to try the same model without thinkingConfig / skip on.
Future<List<Recipe>?> _requestRecipes({
  required String model,
  required String body,
}) async {
  final uri = Uri.parse(
    '$_kGeminiBase$model:generateContent?key=$kGeminiApiKey',
  );

  try {
    print('[Gemini] Sending request to $model...');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final recipes = _parseRecipes(response.body);
      if (recipes.isEmpty) {
        print('[Gemini] $model returned 200 but no usable recipes.');
      }
      return recipes;
    }

    if (response.statusCode == 400 && body.contains('thinkingConfig')) {
      print('[Gemini] $model rejected thinkingConfig; retrying without it.');
      return null;
    }

    if (response.statusCode == 404) {
      print('[Gemini] Model $model is not available (404); trying next.');
      return [];
    }

    if (response.statusCode == 503 || response.statusCode == 429) {
      print(
        '[Gemini] $model busy (${response.statusCode}); switching models.',
      );
      return [];
    }

    print('[Gemini] HTTP ${response.statusCode}: ${response.body}');
    return [];
  } on TimeoutException {
    print('[Gemini] $model timed out; trying next model.');
    return [];
  } catch (e) {
    print('[Gemini] $model error: $e');
    return [];
  }
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

  // ── Tools ──────────────────────────────────────────────────────────────
  final rawTools = m['tools'];
  final tools = <String>[];

  if (rawTools is List) {
    for (final tool in rawTools) {
      final text = _asString(tool).trim();
      if (text.isNotEmpty) tools.add(text);
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
    tools: tools,
    steps: steps,
    isRecommended: true,
  );
}

String _asString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

// ── Screenshot → Recipe extraction ───────────────────────────────────────────
//
// Pipeline (fast, reliable):
//   1. OCR every image via the Magic server /extract-text  (~5 s each)
//   2. Combine the extracted text
//   3. Send text-only to Gemini for structured recipe parsing  (~5–10 s)
//
// This avoids sending large base64-encoded images to Gemini Vision,
// which could hang for 20+ minutes cycling through model retries.
// The Magic server does NOT need any changes — /extract-text already exists.

/// OCRs [imageBytesList] via the Flask `/extract-text` endpoint and returns
/// the combined text from all images (each separated by a blank line).
///
/// Individual image failures are silently skipped so partial results are
/// still usable when one screenshot is blurry or unsupported.
Future<String> _ocrImages(List<Uint8List> imageBytesList) async {
  final parts = <String>[];
  for (int i = 0; i < imageBytesList.length; i++) {
    try {
      final req = http.MultipartRequest('POST', ocrMultipartUri())
        ..files.add(http.MultipartFile.fromBytes(
          'image',
          imageBytesList[i],
          filename: 'screenshot_$i.jpg',
        ));
      final streamed =
          await req.send().timeout(const Duration(seconds: 20));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) {
        final map = jsonDecode(body) as Map<String, dynamic>;
        final text = (map['text'] as String? ?? '').trim();
        if (text.isNotEmpty) parts.add(text);
      }
    } catch (e) {
      debugPrint('[screenshot-ocr] image $i failed: $e');
    }
  }
  return parts.join('\n\n');
}

/// Sends [rawText] (already extracted from screenshots) to Gemini and returns
/// a structured [Recipe], or null on failure.
///
/// Uses text-only Gemini — same path as "Surprise Me!" so it is proven to work.
Future<Recipe?> _extractRecipeFromOcrText(String rawText) async {
  if (rawText.trim().isEmpty) return null;

  final prompt =
      'You are a recipe extraction assistant for a low-vision cooking app.\n'
      'The following text was extracted from one or more recipe screenshots.\n'
      'A single recipe may be split across multiple images — merge all '
      'content into ONE recipe, removing obvious duplicates.\n\n'
      'EXTRACTED TEXT:\n$rawText\n\n'
      'Rules:\n'
      '- Preserve exact quantities and measurements shown in the text.\n'
      '- Do NOT invent information not in the text.\n'
      '- Return ONLY a valid JSON object — no markdown, no explanation.\n\n'
      '{\n'
      '  "name": "Recipe Name",\n'
      '  "estimatedTimeMinutes": 30,\n'
      '  "difficulty": 2,\n'
      '  "dietaryPreferences": [],\n'
      '  "allergens": [],\n'
      '  "ingredients": [\n'
      '    {"name": "flour", "quantity": "2 cups"}\n'
      '  ],\n'
      '  "steps": [\n'
      '    "Preheat oven to 350\u00b0F.",\n'
      '    "Mix flour and butter."\n'
      '  ]\n'
      '}\n\n'
      'Field rules:\n'
      '- name: recipe title (string).\n'
      '- estimatedTimeMinutes: integer, default 30 if not found.\n'
      '- difficulty: 1–5 integer (1=easy, 5=very hard), default 2.\n'
      '- dietaryPreferences: e.g. ["Vegetarian","Gluten-Free"] or [].\n'
      '- allergens: e.g. ["Dairy","Eggs","Wheat / Gluten","Nuts","Soy"] or [].\n'
      '- ingredients: [{name, quantity}] — quantity "" when not shown.\n'
      '- steps: array of instruction strings, [] if not visible.';

  final requestBody = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': prompt},
        ],
      },
    ],
    'generationConfig': {
      'temperature': 0.2,
      'maxOutputTokens': 4096,
      'responseMimeType': 'application/json',
    },
  });

  // Try every model once with a short 30-second timeout — text requests are
  // fast, so a single pass is sufficient.
  for (final model in _kGeminiModels) {
    final uri = Uri.parse(
        '$_kGeminiBase$model:generateContent?key=$kGeminiApiKey');
    try {
      debugPrint('[screenshot-gemini] Trying $model…');
      final resp = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: requestBody)
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final recipe = _parseScreenshotRecipe(resp.body);
        if (recipe != null) return recipe;
      }
      if (resp.statusCode == 503 || resp.statusCode == 429) {
        debugPrint('[screenshot-gemini] $model busy; trying next.');
        continue;
      }
      if (resp.statusCode == 404) {
        debugPrint('[screenshot-gemini] $model not found; trying next.');
        continue;
      }
      debugPrint('[screenshot-gemini] $model HTTP ${resp.statusCode}');
    } on TimeoutException {
      debugPrint('[screenshot-gemini] $model timed out; trying next.');
      continue;
    } catch (e) {
      debugPrint('[screenshot-gemini] $model error: $e; trying next.');
      continue;
    }
  }

  // One retry pass after a short delay.
  await Future.delayed(const Duration(seconds: 4));
  for (final model in _kGeminiModels) {
    final uri = Uri.parse(
        '$_kGeminiBase$model:generateContent?key=$kGeminiApiKey');
    try {
      final resp = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: requestBody)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final recipe = _parseScreenshotRecipe(resp.body);
        if (recipe != null) return recipe;
      }
    } catch (_) {}
  }
  return null;
}

/// Entry point called by [RecipeImportScreen].
///
/// [onProgress] is called with human-readable status strings so the UI can
/// update its loading message in real time.
Future<Recipe?> extractRecipeFromScreenshots(
  List<Uint8List> imageBytesList, {
  List<String>? mimeTypes,
  void Function(String message)? onProgress,
}) async {
  if (imageBytesList.isEmpty) return null;

  if (kGeminiApiKey.isEmpty) {
    debugPrint('[screenshot] GEMINI_API_KEY missing.');
    return null;
  }

  // Step 1 — OCR via Magic server.
  final n = imageBytesList.length;
  onProgress?.call(
      'Reading $n screenshot${n == 1 ? '' : 's'} via server…');
  final ocrText = await _ocrImages(imageBytesList);

  if (ocrText.trim().isEmpty) {
    debugPrint('[screenshot] OCR returned no text — cannot extract recipe.');
    return null;
  }

  // Step 2 — Parse recipe from OCR text via Gemini (text-only).
  onProgress?.call('Extracting recipe…');
  return _extractRecipeFromOcrText(ocrText);
}

Recipe? _parseScreenshotRecipe(String responseBody) {
  try {
    final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;

    final content = (candidates.first as Map<String, dynamic>)['content']
        as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;

    var rawText = parts
        .map((p) =>
            p is Map && p['text'] is String ? p['text'] as String : '')
        .join()
        .trim();

    if (rawText.startsWith('```')) {
      rawText = rawText.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      rawText = rawText.replaceFirst(RegExp(r'\s*```$'), '');
    }

    final map = jsonDecode(rawText);
    if (map is! Map) return null;

    final id = 'screenshot_${DateTime.now().millisecondsSinceEpoch}';
    return _recipeFromScreenshotMap(Map<String, dynamic>.from(map), id: id);
  } catch (e) {
    debugPrint('[Gemini-screenshot] parse error: $e');
    return null;
  }
}

/// Maps a Gemini JSON response to a [Recipe] for screenshot-imported recipes.
/// Parses allergens (which [_recipeFromMap] does not) and sets [isImported].
Recipe _recipeFromScreenshotMap(
  Map<String, dynamic> m, {
  required String id,
}) {
  String s(String key) => _asString(m[key]).trim();
  int i(String key, int fallback) {
    final v = m[key];
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  final ingredients = <RecipeIngredient>[];
  final rawIngs = m['ingredients'];
  if (rawIngs is List) {
    for (final item in rawIngs) {
      if (item is Map) {
        final name = _asString(item['name']).trim();
        final qty = _asString(item['quantity']).trim();
        if (name.isNotEmpty) ingredients.add(RecipeIngredient(name, quantity: qty));
      } else {
        final name = _asString(item).trim();
        if (name.isNotEmpty) ingredients.add(RecipeIngredient(name));
      }
    }
  }

  final steps = <String>[];
  final rawSteps = m['steps'];
  if (rawSteps is List) {
    for (final step in rawSteps) {
      final text = _asString(step).trim();
      if (text.isNotEmpty) steps.add(text);
    }
  }

  final dietaryPrefs = <String>[];
  final rawDiet = m['dietaryPreferences'];
  if (rawDiet is List) {
    for (final pref in rawDiet) {
      final text = _asString(pref).trim();
      if (text.isNotEmpty) dietaryPrefs.add(text);
    }
  }
  if (dietaryPrefs.isEmpty) dietaryPrefs.add('No Restrictions');

  final allergens = <String>[];
  final rawAllergens = m['allergens'];
  if (rawAllergens is List) {
    for (final allergen in rawAllergens) {
      final text = _asString(allergen).trim();
      if (text.isNotEmpty) allergens.add(text);
    }
  }

  final name = s('name');
  return Recipe(
    id: id,
    name: name.isEmpty ? 'Imported Recipe' : name,
    category: kImportedCategory,
    estimatedTimeMinutes: i('estimatedTimeMinutes', 30),
    difficulty: i('difficulty', 2).clamp(1, 5),
    dietaryPreferences: dietaryPrefs,
    allergens: allergens,
    ingredients: ingredients,
    tools: const [], // caller populates from /extract-tools
    steps: steps,
    isImported: true,
  );
}
