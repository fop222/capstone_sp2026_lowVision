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
      _error = null;
      _preview = null;
    });

    try {
      // CORS proxy — required for Flutter web to fetch third-party pages.
      final proxyUrl =
          'https://api.allorigins.win/get?url=${Uri.encodeComponent(url)}';
      final resp = await http.get(Uri.parse(proxyUrl)).timeout(
        const Duration(seconds: 20),
      );

      if (resp.statusCode != 200) {
        throw Exception('Server returned ${resp.statusCode}');
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final html = body['contents'] as String? ?? '';

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

      setState(() {
        _preview = recipe;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load the page: $e';
        _loading = false;
      });
    }
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
                                'Fetching recipe…',
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
  final name = _str(s['name']) ?? _str(s['headline']) ?? 'Imported Recipe';

  // ── Time ──────────────────────────────────────────────────────────────
  int minutes = _parseDuration(s['totalTime']);
  if (minutes == 0) {
    minutes = _parseDuration(s['cookTime']) + _parseDuration(s['prepTime']);
  }

  // ── Ingredients ───────────────────────────────────────────────────────
  final rawIngredients = s['recipeIngredient'];
  final ingredients = <RecipeIngredient>[];
  if (rawIngredients is List) {
    for (final item in rawIngredients) {
      final text = _str(item)?.trim() ?? '';
      if (text.isEmpty) continue;
      // Try to split "2 cups flour" into quantity "2 cups" + name "flour"
      final parts = _splitQuantityName(text);
      ingredients.add(RecipeIngredient(parts.$2, quantity: parts.$1));
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
    steps.addAll(
        rawSteps.split(RegExp(r'\n+')).map((l) => l.trim()).where((l) => l.isNotEmpty));
  }

  // ── Category ──────────────────────────────────────────────────────────
  final category = _detectCategory(s, name);

  // ── Dietary / allergen hints ───────────────────────────────────────────
  final dietaryPrefs = _parseDietaryPrefs(s);

  // ── Build id from URL ─────────────────────────────────────────────────
  final id = 'imported_${DateTime.now().millisecondsSinceEpoch}';

  return Recipe(
    id: id,
    name: name,
    category: category,
    estimatedTimeMinutes: minutes,
    difficulty: 2, // unknown; default to mid-range
    dietaryPreferences: dietaryPrefs.isEmpty ? ['No Restrictions'] : dietaryPrefs,
    allergens: const [],
    ingredients: ingredients,
    tools: const [],
    steps: steps,
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

/// Very light quantity/name splitter: "2 cups all-purpose flour" →
/// ("2 cups", "all-purpose flour").  Falls back to ("", full text).
(String, String) _splitQuantityName(String text) {
  // Pattern: optional number + optional fraction, then a unit word, then rest.
  final re = RegExp(
    r'^(\d[\d/\s¼½¾]*(?:cup|cups|tablespoon|tablespoons|tbsp|teaspoon|teaspoons|tsp|oz|ounce|ounces|pound|pounds|lb|lbs|gram|grams|g|kg|ml|liter|liters|l|can|cans|bunch|clove|cloves|slice|slices|piece|pieces|package|packages|pkg|bag|bags|box|boxes|stick|sticks|to taste|as needed|pinch)\b)\s*(.*)',
    caseSensitive: false,
  );
  final m = re.firstMatch(text);
  if (m != null) {
    return (m.group(1)!.trim(), m.group(2)!.trim());
  }
  // Fallback: leading number only (e.g. "2 eggs")
  final numRe = RegExp(r'^(\d[\d/\s¼½¾]*)\s+(.+)');
  final nm = numRe.firstMatch(text);
  if (nm != null) {
    return (nm.group(1)!.trim(), nm.group(2)!.trim());
  }
  return ('', text);
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
