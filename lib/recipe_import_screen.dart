/// Import a recipe from a public URL.
///
/// Fetches the page via a CORS proxy, looks for schema.org/Recipe JSON-LD,
/// shows a preview, and—on confirmation—adds the recipe to the session-only
/// [importedRecipesNotifier].
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'grocery_ui.dart';
import 'imported_recipes_state.dart';
import 'ocr_config.dart';
import 'recipe_data.dart';

// ─── Public entry-point ───────────────────────────────────────────────────────

class RecipeImportScreen extends StatefulWidget {
  const RecipeImportScreen({super.key});

  @override
  State<RecipeImportScreen> createState() => _RecipeImportScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _RecipeImportScreenState extends State<RecipeImportScreen> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String _loadingMessage = 'Fetching recipe…';
  String? _error;
  Recipe? _preview;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ── Fetch + parse ──────────────────────────────────────────────────────────

  Future<void> _parse() async {
    if (!_formKey.currentState!.validate()) return;
    final url = _urlController.text.trim();

    setState(() {
      _loading = true;
      _loadingMessage = 'Fetching recipe…';
      _error = null;
      _preview = null;
    });

    try {
      final html = await _fetchWithFallback(url);

      final recipe = _parseSchemaOrgRecipe(html, url);
      if (recipe == null) {
        setState(() {
          _error =
              'No recipe data found on that page. Make sure the URL points '
              'directly to a recipe (e.g. allrecipes.com, foodnetwork.com).';
          _loading = false;
        });
        return;
      }

      // Extract tools from steps using the VLM server.
      List<String> tools = [];
      if (recipe.steps.isNotEmpty) {
        setState(() => _loadingMessage = 'Extracting tools…');
        tools = await _extractTools(recipe.steps);
      }

      // Rebuild the recipe with the extracted tools.
      final recipeWithTools = Recipe(
        id: recipe.id,
        name: recipe.name,
        category: recipe.category,
        estimatedTimeMinutes: recipe.estimatedTimeMinutes,
        difficulty: recipe.difficulty,
        dietaryPreferences: recipe.dietaryPreferences,
        allergens: recipe.allergens,
        ingredients: recipe.ingredients,
        tools: tools,
        steps: recipe.steps,
        servings: recipe.servings,
        isImported: true,
      );

      setState(() {
        _preview = recipeWithTools;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load the page. Please check the URL and try again.';
        _loading = false;
      });
    }
  }

  /// Fetches the HTML of [url] via the app's own Flask backend,
  /// which has no CORS restrictions.
  Future<String> _fetchWithFallback(String url) async {
    final uri = recipeFetchUri(url);
    final resp = await http.get(uri).timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) {
      throw Exception('Backend returned ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body.containsKey('error')) {
      throw Exception(body['error']);
    }
    final html = body['html'] as String? ?? '';
    if (html.isEmpty) throw Exception('Empty response from server');
    return html;
  }

  /// Calls /extract-tools on the backend VLM to get a list of kitchen tools
  /// inferred from the recipe's step text.  Falls back to rule-based extraction
  /// if the server is unavailable or returns an empty list.
  Future<List<String>> _extractTools(List<String> steps) async {
    final stepsText = steps.join('\n');

    // Try VLM server first.
    try {
      final uri = toolsExtractUri();
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'steps': stepsText}),
          )
          .timeout(const Duration(seconds: 40));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final raw = body['tools'];
        if (raw is List) {
          final vlmTools = raw
              .map((e) => (e as String).trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (vlmTools.isNotEmpty) return vlmTools;
        }
      }
    } catch (_) {
      // VLM unavailable — fall through to rule-based.
    }

    // Rule-based fallback: scan steps text for known kitchen tool keywords.
    return _inferToolsFromText(stepsText);
  }

  void _confirm() {
    if (_preview == null) return;
    addImportedRecipe(_preview!);
    Navigator.of(context).pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = groceryPagePadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Import Recipe from Link')),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: SingleChildScrollView(
                padding: padding.add(
                  const EdgeInsets.only(top: 28, bottom: 48),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Instructions ──────────────────────────────────
                      Text(
                        'Paste a recipe URL below.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Works best with popular recipe sites that include '
                        'structured data (AllRecipes, Food Network, BBC Good '
                        'Food, Serious Eats, etc.).',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── URL field ──────────────────────────────────────
                      TextFormField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Recipe URL',
                          labelStyle:
                              const TextStyle(color: Colors.white60),
                          hintText: 'https://www.allrecipes.com/recipe/...',
                          hintStyle:
                              const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: kBrandPurpleLight,
                              width: 2,
                            ),
                          ),
                          errorStyle:
                              const TextStyle(color: Color(0xFFFF8A80)),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'Please enter a URL.';
                          if (!s.startsWith('http')) {
                            return 'URL must start with http:// or https://';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // ── Parse button ───────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: GroceryGlowButton(
                            onPressed: _loading ? null : _parse,
                            child: const Text('Parse Recipe'),
                          ),
                        ),

                      // ── Loading ────────────────────────────────────────
                      if (_loading) ...[
                        const SizedBox(height: 28),
                        const Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(
                                color: kBrandPurpleLight,
                              ),
                              SizedBox(height: 12),
                              Text(
                                _loadingMessage,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ── Error ──────────────────────────────────────────
                      if (_error != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A1A1A),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFFF8A80),
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFFFF8A80),
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ── Preview ────────────────────────────────────────
                      if (_preview != null) ...[
                        const SizedBox(height: 32),
                        _PreviewCard(recipe: _preview!),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: GroceryGlowButton(
                            onPressed: _confirm,
                            child: const Text('Add to My Recipes'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _preview = null),
                            child: const Text(
                              'Try a different URL',
                              style: TextStyle(color: Colors.white60),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Preview card ─────────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF252344).withValues(alpha: 0.97),
            const Color(0xFF1A1D2E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBrandPurpleLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: kBrandPurpleLight, size: 20),
              const SizedBox(width: 8),
              Text(
                'Recipe found!',
                style: TextStyle(
                  color: kBrandPurpleLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            recipe.name,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 16, color: kBrandPurpleLight),
              const SizedBox(width: 5),
              Text(
                recipe.estimatedTimeMinutes > 0
                    ? '~${recipe.estimatedTimeMinutes} min'
                    : 'Time unknown',
                style: TextStyle(color: kBrandPurpleLight, fontSize: 14),
              ),
              const SizedBox(width: 16),
              Icon(Icons.restaurant_menu_rounded,
                  size: 16, color: Colors.white54),
              const SizedBox(width: 5),
              Text(
                '${recipe.ingredients.length} ingredients',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
          if (recipe.ingredients.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Ingredients:',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ...recipe.ingredients.take(5).map(
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• ${i.name}${i.quantity.isNotEmpty ? " — ${i.quantity}" : ""}',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ),
            if (recipe.ingredients.length > 5)
              Text(
                '  + ${recipe.ingredients.length - 5} more',
                style:
                    const TextStyle(color: Colors.white38, fontSize: 13),
              ),
          ],
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: kBrandPurpleMid.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Category: ${recipe.category}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── schema.org / JSON-LD parser ──────────────────────────────────────────────

/// Finds and parses the first schema.org Recipe object from [html].
/// Returns null if no recipe data can be found.
Recipe? _parseSchemaOrgRecipe(String html, String sourceUrl) {
  // Find all <script type="application/ld+json"> blocks.
  final scriptRe = RegExp(
    '<script[^>]+type=["\']application/ld\\+json["\'][^>]*>(.*?)</script>',
    dotAll: true,
    caseSensitive: false,
  );

  for (final match in scriptRe.allMatches(html)) {
    final raw = match.group(1)?.trim() ?? '';
    if (raw.isEmpty) continue;

    dynamic parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      continue;
    }

    // Could be a single object or a list; unwrap @graph arrays too.
    final candidates = <dynamic>[];
    if (parsed is List) {
      candidates.addAll(parsed);
    } else if (parsed is Map) {
      final graph = parsed['@graph'];
      if (graph is List) {
        candidates.addAll(graph);
      } else {
        candidates.add(parsed);
      }
    }

    for (final obj in candidates) {
      if (obj is! Map) continue;
      final type = obj['@type'];
      final isRecipe = (type is String && type == 'Recipe') ||
          (type is List && type.contains('Recipe'));
      if (!isRecipe) continue;

      return _buildRecipeFromSchema(obj, sourceUrl);
    }
  }
  return null;
}

Recipe _buildRecipeFromSchema(Map<dynamic, dynamic> s, String sourceUrl) {
  // ── Name ──────────────────────────────────────────────────────────────
  final name = _decodeHtmlEntities(
      _str(s['name']) ?? _str(s['headline']) ?? 'Imported Recipe');

  // ── Time ──────────────────────────────────────────────────────────────
  int minutes = _parseDuration(s['totalTime']);
  if (minutes == 0) {
    minutes = _parseDuration(s['cookTime']) + _parseDuration(s['prepTime']);
  }

  // ── Servings ──────────────────────────────────────────────────────────
  final servings = _parseServings(s['recipeYield']);

  // ── Ingredients ───────────────────────────────────────────────────────
  final rawIngredients = s['recipeIngredient'];
  final ingredients = <RecipeIngredient>[];
  if (rawIngredients is List) {
    for (final item in rawIngredients) {
      final text = _decodeHtmlEntities(_str(item)?.trim() ?? '');
      if (text.isEmpty) continue;
      final parts = _splitQuantityName(text);
      final cleanedName = _cleanIngredientName(parts.$2);
      if (cleanedName.isEmpty) continue;
      ingredients.add(RecipeIngredient(cleanedName, quantity: parts.$1));
    }
  }

  // ── Steps ─────────────────────────────────────────────────────────────
  final rawSteps = s['recipeInstructions'];
  final steps = <String>[];
  if (rawSteps is List) {
    for (final step in rawSteps) {
      if (step is String) {
        final t = step.trim();
        if (t.isNotEmpty) steps.add(t);
      } else if (step is Map) {
        final t = _str(step['text'])?.trim() ?? '';
        if (t.isNotEmpty) steps.add(t);
      }
    }
  } else if (rawSteps is String) {
    steps.addAll(rawSteps
        .split(RegExp(r'\n+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty));
  }

  // ── Category ──────────────────────────────────────────────────────────
  final category = _detectCategory(s, name);

  // ── Dietary / allergen hints ───────────────────────────────────────────
  final dietaryPrefs = _parseDietaryPrefs(s);

  // ── Build id from timestamp ───────────────────────────────────────────
  final id = 'imported_${DateTime.now().millisecondsSinceEpoch}';

  return Recipe(
    id: id,
    name: name,
    category: category,
    estimatedTimeMinutes: minutes,
    difficulty: 2,
    dietaryPreferences:
        dietaryPrefs.isEmpty ? ['No Restrictions'] : dietaryPrefs,
    allergens: const [],
    ingredients: ingredients,
    tools: const [],
    steps: steps,
    servings: servings,
    isImported: true,
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String? _str(dynamic v) {
  if (v is String) return v;
  if (v is List && v.isNotEmpty) return _str(v.first);
  return null;
}

/// Parse ISO 8601 duration PT1H30M → minutes.
int _parseDuration(dynamic v) {
  final s = _str(v) ?? '';
  if (s.isEmpty) return 0;
  final m = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?', caseSensitive: false)
      .firstMatch(s.toUpperCase());
  if (m == null) return 0;
  final h = int.tryParse(m.group(1) ?? '0') ?? 0;
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  return h * 60 + min;
}

/// Decodes common HTML entities: &#39; → ', &amp; → &, etc.
String _decodeHtmlEntities(String s) {
  return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m.group(1)!) ?? 0;
        return code > 0 ? String.fromCharCode(code) : '';
      });
}

/// Very light quantity/name splitter: "2 cups all-purpose flour" →
/// ("2 cups", "all-purpose flour").  Falls back to ("", full text).
(String, String) _splitQuantityName(String text) {
  // Decode HTML entities first.
  final t = _decodeHtmlEntities(text);
  // Number pattern: digits, decimals, fractions, vulgar fractions.
  const num = r'[\d\.\/\s¼½¾⅓⅔⅛⅜⅝⅞]+';
  // Units (singular + plural).
  const units =
      r'cup|cups|tablespoon|tablespoons|tbsp|teaspoon|teaspoons|tsp|'
      r'oz|ounce|ounces|pound|pounds|lb|lbs|gram|grams|g|kg|ml|'
      r'liter|liters|l|can|cans|bunch|bunches|clove|cloves|'
      r'slice|slices|piece|pieces|package|packages|pkg|'
      r'bag|bags|box|boxes|stick|sticks|bar|bars|'
      r'sprig|sprigs|sheet|sheets|strip|strips|'
      r'to taste|as needed|pinch';
  final re = RegExp(
    '^($num(?:$units)\\b)\\s*(.*)',
    caseSensitive: false,
  );
  final m = re.firstMatch(t);
  if (m != null) {
    return (m.group(1)!.trim(), m.group(2)!.trim());
  }
  // Fallback: leading number only (e.g. "2 eggs").
  final numRe = RegExp(r'^([\d\.\/\s¼½¾⅓⅔⅛⅜⅝⅞]+)\s+(.+)');
  final nm = numRe.firstMatch(t);
  if (nm != null) {
    return (nm.group(1)!.trim(), nm.group(2)!.trim());
  }
  return ('', t);
}

/// Rule-based kitchen tool extraction — scans recipe steps for tool keywords.
/// Used as a fallback when the VLM server is unavailable.
List<String> _inferToolsFromText(String stepsText) {
  if (stepsText.isEmpty) return [];
  final s = stepsText.toLowerCase();

  final found = <String>[];
  void check(Pattern pattern, String toolName) {
    if (pattern is RegExp ? pattern.hasMatch(s) : s.contains(pattern as String)) {
      found.add(toolName);
    }
  }

  check(RegExp(r'\boven\b|preheat'), 'Oven');
  check(RegExp(r'baking sheet|sheet pan|cookie sheet'), 'Baking sheet');
  check(RegExp(r'baking dish|baking pan|casserole dish|9x13|9-by-13|13.by.9'), 'Baking dish');
  check(RegExp(r'\bskillet\b|frying pan|sauté pan|saute pan'), 'Skillet or frying pan');
  check(RegExp(r'\bsaucepan\b|small pot|medium pot'), 'Saucepan');
  check(RegExp(r'large pot|stock pot|dutch oven'), 'Large pot');
  check(RegExp(r'mixing bowl|large bowl|medium bowl|small bowl'), 'Mixing bowl');
  check(RegExp(r'\bblender\b'), 'Blender');
  check(RegExp(r'food processor'), 'Food processor');
  check(RegExp(r'\bknife\b|cutting board|chopping board'), 'Knife and cutting board');
  check(RegExp(r'\bspatula\b'), 'Spatula');
  check(RegExp(r'\bwhisk\b'), 'Whisk');
  check(RegExp(r'wooden spoon|mixing spoon|stirring spoon'), 'Wooden spoon');
  check(RegExp(r'measuring cup'), 'Measuring cups');
  check(RegExp(r'measuring spoon|tablespoon measure|teaspoon measure'), 'Measuring spoons');
  check(RegExp(r'\bcolander\b|\bstrainer\b'), 'Colander');
  check(RegExp(r'\bgrater\b'), 'Grater');
  check(RegExp(r'rolling pin'), 'Rolling pin');
  check(RegExp(r'meat mallet|tenderizer|pound.*flat|flatten.*pound'), 'Meat mallet');
  check(RegExp(r'plastic wrap|cling wrap'), 'Plastic wrap');
  check(RegExp(r'aluminum foil|tin foil'), 'Aluminum foil');
  check(RegExp(r'\btoothpick'), 'Toothpicks');
  check(RegExp(r'electric mixer|hand mixer|stand mixer'), 'Electric mixer');
  check(RegExp(r'oven mitt|oven glove'), 'Oven mitts');
  check(RegExp(r'shallow dish|shallow bowl|shallow pan'), 'Shallow dish');
  check(RegExp(r'\btongs\b'), 'Tongs');
  check(RegExp(r'\bpeeler\b'), 'Vegetable peeler');
  check(RegExp(r'can opener'), 'Can opener');
  check(RegExp(r'parchment paper|wax paper'), 'Parchment paper');
  check(RegExp(r'wire rack|cooling rack'), 'Wire rack');

  return found;
}

String _detectCategory(Map<dynamic, dynamic> s, String name) {
  final hints = [
    _str(s['recipeCategory']) ?? '',
    _str(s['keywords']) ?? '',
    name,
  ].join(' ').toLowerCase();

  if (RegExp(r'\b(breakfast|brunch|morning|pancake|waffle|omelette|omelet|cereal|granola|muffin|bagel)\b').hasMatch(hints)) {
    return 'Breakfast';
  }
  if (RegExp(r'\b(dessert|cake|cookie|pie|brownie|pudding|ice.?cream|pastry|sweet|tart|cupcake|candy|chocolate)\b').hasMatch(hints)) {
    return 'Desserts';
  }
  if (RegExp(r'\b(dinner|lunch|main|entree|entrée|soup|sandwich|burger|pasta|salad|chicken|beef|pork|fish|rice|noodle|pizza|stir.?fry|roast|grill|bake)\b').hasMatch(hints)) {
    return 'Entrées';
  }
  return kImportedCategory;
}

List<String> _parseDietaryPrefs(Map<dynamic, dynamic> s) {
  final raw = s['suitableForDiet'];
  final tags = <String>[];
  final list = raw is List ? raw : (raw is String ? [raw] : <dynamic>[]);
  for (final item in list) {
    final v = (_str(item) ?? '').toLowerCase();
    if (v.contains('vegetarian')) tags.add('Vegetarian');
    if (v.contains('vegan')) tags.add('Vegan');
    if (v.contains('glutenfree') || v.contains('gluten-free')) {
      tags.add('Gluten-Free');
    }
    if (v.contains('dairyfree') || v.contains('dairy-free')) {
      tags.add('Dairy-Free');
    }
  }
  return tags;
}

/// Removes parenthetical text and everything after the first comma from an
/// ingredient name.
/// Examples:
///   "kosher salt, plus more to taste"      → "kosher salt"
///   "breadcrumbs (or panko)"               → "breadcrumbs"
///   "ham or prosciutto"                    → "ham or prosciutto"
String _cleanIngredientName(String raw) {
  // Remove anything inside parentheses (including the parens).
  var s = raw.replaceAll(RegExp(r'\(.*?\)'), '');
  // Remove everything after the first comma.
  final commaIdx = s.indexOf(',');
  if (commaIdx >= 0) s = s.substring(0, commaIdx);
  return s.trim();
}

/// Parses recipeYield into an integer serving count.
/// Handles: "6", "6 servings", "Serves 6", ["6 servings"].
int? _parseServings(dynamic raw) {
  final s = _str(raw) ?? '';
  if (s.isEmpty) return null;
  final m = RegExp(r'(\d+)').firstMatch(s);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  return (n != null && n > 0) ? n : null;
}
