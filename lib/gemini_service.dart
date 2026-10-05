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

/// Parses a recipe from raw OCR text using heuristic rules.
/// Runs entirely client-side — no Gemini or any other network call.
Recipe? _parseOcrRecipe(String rawText) {
  if (rawText.trim().isEmpty) return null;

  final lines = rawText
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.isEmpty) return null;

  // ── Identify section boundaries ──────────────────────────────────────────
  final _ingHeaders = RegExp(
      r'^(ingredients?|what you.?ll need|you.?ll need)\s*:?\s*$',
      caseSensitive: false);
  final _stepHeaders = RegExp(
      r'^(instructions?|directions?|method|steps?|preparation|how to make'
      r'|how to prepare|how to cook)\s*:?\s*$',
      caseSensitive: false);
  final _toolHeaders = RegExp(
      r'^(tools?|equipment|utensils?|you will need|what you need)\s*:?\s*$',
      caseSensitive: false);
  final _stopHeaders = RegExp(
      r'^(notes?|tips?|nutrition|serving|storage|faqs?|related|comments?'
      r'|similar recipes?)\s*:?\s*$',
      caseSensitive: false);

  final ingLines = <String>[];
  final stepLines = <String>[];
  final toolLines = <String>[];
  String? section;

  for (final line in lines) {
    if (_ingHeaders.hasMatch(line)) { section = 'ing'; continue; }
    if (_stepHeaders.hasMatch(line)) { section = 'step'; continue; }
    if (_toolHeaders.hasMatch(line)) { section = 'tool'; continue; }
    if (_stopHeaders.hasMatch(line)) { section = null; continue; }
    switch (section) {
      case 'ing':  ingLines.add(line);  break;
      case 'step': stepLines.add(line); break;
      case 'tool': toolLines.add(line); break;
    }
  }

  // ── Recipe name ──────────────────────────────────────────────────────────
  final skipLine = RegExp(
      r'^(http|www\.|©|copyright|\d+\s*(serving|yield|calorie|min|hour|star))',
      caseSensitive: false);
  String name = '';
  for (final l in lines.take(12)) {
    final ll = l.toLowerCase();
    if (skipLine.hasMatch(ll)) continue;
    if (_ingHeaders.hasMatch(l) || _stepHeaders.hasMatch(l)) continue;
    if (l.length < 3) continue;
    if (RegExp(r'^[\d\s\.\-\|:]+$').hasMatch(l)) continue; // pure numbers/symbols
    name = l;
    break;
  }

  // ── Time ────────────────────────────────────────────────────────────────
  int timeMinutes = 0;
  final fullText = rawText.toLowerCase();

  // Try "total time: 1 hr 30 min" first
  final totalRe = RegExp(
      r'total\s+time[:\s]+(?:(\d+)\s*(?:hours?|hrs?|h)[\s,]*)?'
      r'(?:(\d+)\s*(?:minutes?|mins?|m))?',
      caseSensitive: false);
  final tm = totalRe.firstMatch(fullText);
  if (tm != null) {
    timeMinutes = (int.tryParse(tm.group(1) ?? '') ?? 0) * 60
                + (int.tryParse(tm.group(2) ?? '') ?? 0);
  }

  // Sum prep + cook if no total found
  if (timeMinutes == 0) {
    final subRe = RegExp(
        r'(?:prep|cook|preparation|bake|baking|chill|rest)\s+time[:\s]+'
        r'(?:(\d+)\s*(?:hours?|hrs?|h)[\s,]*)?(?:(\d+)\s*(?:minutes?|mins?|m))?',
        caseSensitive: false);
    for (final m in subRe.allMatches(fullText)) {
      timeMinutes += (int.tryParse(m.group(1) ?? '') ?? 0) * 60
                   + (int.tryParse(m.group(2) ?? '') ?? 0);
    }
  }

  // Fallback: first standalone "X minutes"
  if (timeMinutes == 0) {
    final minRe = RegExp(r'\b(\d{1,3})\s*(?:minutes?|mins?)\b', caseSensitive: false);
    final m = minRe.firstMatch(fullText);
    if (m != null) timeMinutes = int.tryParse(m.group(1)!) ?? 0;
  }
  if (timeMinutes <= 0 || timeMinutes > 1440) timeMinutes = 30;

  // ── Ingredients ──────────────────────────────────────────────────────────
  final ingredients = <RecipeIngredient>[];
  final bulletRe = RegExp(r'^[\•\-\*\·\–\—\d]+[\.\):]?\s*');
  for (final raw in ingLines) {
    final line = raw.replaceFirst(bulletRe, '').trim();
    if (line.isEmpty) continue;
    final qty = _ocrSplitQty(line);
    final cleanName = qty.$2.isEmpty ? line : qty.$2;
    if (cleanName.length < 2) continue;
    ingredients.add(RecipeIngredient(cleanName, quantity: qty.$1));
  }

  // ── Steps ────────────────────────────────────────────────────────────────
  final steps = <String>[];
  // Lines that start with a number are likely separate steps even without a
  // section header — use them if we found no step section.
  final src = stepLines.isNotEmpty
      ? stepLines
      : lines.where((l) => RegExp(r'^\d+[\.\):]').hasMatch(l)).toList();
  final numRe = RegExp(r'^\d+[\.\):\s]+');
  for (final raw in src) {
    final s = raw.replaceFirst(numRe, '').replaceFirst(bulletRe, '').trim();
    if (s.length < 5) continue;
    steps.add(s);
  }

  // ── Tools ────────────────────────────────────────────────────────────────
  final tools = <String>[];
  for (final raw in toolLines) {
    final t = raw.replaceFirst(bulletRe, '').trim();
    if (t.isNotEmpty) tools.add(t);
  }
  // If no tool section, infer from steps using existing rule-based helper
  // (defined in recipe_import_screen.dart — keep tools empty here; the
  //  import screen calls /extract-tools after this function returns).

  // ── Dietary ──────────────────────────────────────────────────────────────
  final dietary = <String>[];
  if (RegExp(r'\bvegan\b', caseSensitive: false).hasMatch(rawText)) dietary.add('Vegan');
  else if (RegExp(r'\bvegetarian\b', caseSensitive: false).hasMatch(rawText)) dietary.add('Vegetarian');
  if (RegExp(r'\bgluten.?free\b', caseSensitive: false).hasMatch(rawText)) dietary.add('Gluten-Free');
  if (RegExp(r'\bdairy.?free\b', caseSensitive: false).hasMatch(rawText)) dietary.add('Dairy-Free');
  if (dietary.isEmpty) dietary.add('No Restrictions');

  // ── Allergens ────────────────────────────────────────────────────────────
  final allergens = <String>[];
  final ingText = ingredients.map((i) => i.name.toLowerCase()).join(' ');
  final allText = '$fullText $ingText';
  if (RegExp(r'\b(milk|cream|cheese|butter|dairy|yogurt|whey)\b').hasMatch(allText)) allergens.add('Dairy');
  if (RegExp(r'\b(egg|eggs)\b').hasMatch(allText)) allergens.add('Eggs');
  if (RegExp(r'\b(flour|wheat|bread|pasta|gluten|soy\s+sauce|spaghetti|noodle)\b').hasMatch(allText)) allergens.add('Wheat / Gluten');
  if (RegExp(r'\b(peanut|almond|walnut|cashew|pecan|hazelnut|pistachio|nut)\b').hasMatch(allText)) allergens.add('Nuts');
  if (RegExp(r'\b(soy|tofu|edamame|miso|tempeh)\b').hasMatch(allText)) allergens.add('Soy');
  if (RegExp(r'\b(shrimp|prawn|crab|lobster|shellfish|clam|oyster|mussel)\b').hasMatch(allText)) allergens.add('Shellfish');
  if (RegExp(r'\b(fish|salmon|tuna|cod|tilapia|halibut|anchov)\b').hasMatch(allText)) allergens.add('Fish');

  // ── Difficulty ───────────────────────────────────────────────────────────
  int difficulty = 2;
  if (RegExp(r'\b(very\s+easy|beginner|simple|quick)\b', caseSensitive: false).hasMatch(rawText)) difficulty = 1;
  else if (RegExp(r'\b(easy|basic)\b', caseSensitive: false).hasMatch(rawText)) difficulty = 2;
  else if (RegExp(r'\b(medium|intermediate|moderate)\b', caseSensitive: false).hasMatch(rawText)) difficulty = 3;
  else if (RegExp(r'\b(hard|difficult|advanced|challenging)\b', caseSensitive: false).hasMatch(rawText)) difficulty = 4;
  else if (RegExp(r'\b(very\s+hard|expert|professional)\b', caseSensitive: false).hasMatch(rawText)) difficulty = 5;

  return Recipe(
    id: 'screenshot_${DateTime.now().millisecondsSinceEpoch}',
    name: name.isEmpty ? 'Imported Recipe' : name,
    category: kImportedCategory,
    estimatedTimeMinutes: timeMinutes,
    difficulty: difficulty,
    dietaryPreferences: dietary,
    allergens: allergens,
    ingredients: ingredients,
    tools: const [], // caller populates via /extract-tools
    steps: steps,
    isImported: true,
  );
}

/// Light quantity/name splitter for OCR ingredient lines.
/// "2 cups flour" → ("2 cups", "flour")
/// "1/2 teaspoon salt" → ("1/2 teaspoon", "salt")
(String, String) _ocrSplitQty(String text) {
  const units =
      r'cups?|tablespoons?|tbsp|teaspoons?|tsp|ounces?|oz|pounds?|lbs?|'
      r'grams?|g|kg|ml|liters?|l|cans?|bunches?|cloves?|slices?|pieces?|'
      r'packages?|pkg|bags?|boxes?|sticks?|sprigs?|pinch|to taste|as needed';
  final re = RegExp(
      r'^([\d\.\-\u00bc\u00bd\u00be\u2153\u2154\u215b\u215c\u215d\u215e'
      r'\/\s]+(?:$units)?)\s+(.*)',
      caseSensitive: false);
  final m = re.firstMatch(text);
  if (m != null) return (m.group(1)!.trim(), m.group(2)!.trim());
  // Leading number only ("3 eggs")
  final nm = RegExp(r'^([\d\.\-\/\u00bc\u00bd\u00be]+)\s+(.+)').firstMatch(text);
  if (nm != null) return (nm.group(1)!.trim(), nm.group(2)!.trim());
  return ('', text);
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

  // Step 1 — OCR via Magic server /extract-text (same endpoint used by
  //           the shelf/pantry scanner — no changes needed on the server).
  final n = imageBytesList.length;
  onProgress?.call('Reading $n screenshot${n == 1 ? '' : 's'}…');
  final ocrText = await _ocrImages(imageBytesList);

  if (ocrText.trim().isEmpty) {
    debugPrint('[screenshot] OCR returned no text.');
    return null;
  }

  // Step 2 — Parse entirely client-side (no Gemini, no extra network call).
  onProgress?.call('Extracting recipe…');
  return _parseOcrRecipe(ocrText);
}

// (Gemini Vision / JSON-mapping helpers removed — screenshot import now uses
//  OCR + client-side heuristic parsing; no Gemini call needed for screenshots.)
