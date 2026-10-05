/// Import a recipe from a public URL **or** from one or more screenshots.
///
/// URL path:       fetches HTML → parses JSON-LD → /extract-tools → preview
/// Screenshot path: Gemini Vision (multi-image) → /extract-tools → preview
///
/// Both paths produce the same preview card and navigate to [RecipeDetailScreen]
/// on confirmation.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'gemini_service.dart' show extractRecipeFromScreenshots;
import 'grocery_ui.dart';
import 'imported_recipes_state.dart';
import 'ocr_config.dart';
import 'recipe_data.dart';
import 'recipe_detail_screen.dart';

// ─── Public entry-point ───────────────────────────────────────────────────────

class RecipeImportScreen extends StatefulWidget {
  const RecipeImportScreen({super.key});

  @override
  State<RecipeImportScreen> createState() => _RecipeImportScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _RecipeImportScreenState extends State<RecipeImportScreen> {
  // ── URL import ─────────────────────────────────────────────────────────────
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _urlLoading = false;
  String _urlLoadingMessage = 'Fetching recipe…';
  String? _urlError;
  Recipe? _urlPreview;

  // ── Screenshot import ──────────────────────────────────────────────────────
  final _picker = ImagePicker();
  List<XFile> _selectedImages = [];
  /// index → bytes, pre-loaded for thumbnail display
  final Map<int, Uint8List> _thumbnailCache = {};
  bool _screenshotLoading = false;
  String _screenshotLoadingMessage = '';
  String? _screenshotError;
  Recipe? _screenshotPreview;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ── Confirm: add to session and open recipe detail ─────────────────────────

  void _confirm(Recipe recipe) {
    addImportedRecipe(recipe);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetailScreen(recipe: recipe),
      ),
    );
  }

  // ── URL import pipeline ────────────────────────────────────────────────────

  Future<void> _parseUrl() async {
    if (!_formKey.currentState!.validate()) return;
    final url = _urlController.text.trim();
    setState(() {
      _urlLoading = true;
      _urlLoadingMessage = 'Fetching recipe…';
      _urlError = null;
      _urlPreview = null;
    });

    try {
      final html = await _fetchHtml(url);
      final recipe = _parseSchemaOrgRecipe(html, url);
      if (recipe == null) {
        setState(() {
          _urlError =
              'No recipe data found on that page. Make sure the URL points '
              'directly to a recipe (e.g. AllRecipes, Food Network, BBC Good Food).';
          _urlLoading = false;
        });
        return;
      }

      List<String> tools = [];
      if (recipe.steps.isNotEmpty) {
        setState(() => _urlLoadingMessage = 'Extracting tools…');
        tools = await _extractTools(recipe.steps);
      }

      setState(() {
        _urlPreview = Recipe(
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
        _urlLoading = false;
      });
    } catch (_) {
      setState(() {
        _urlError = 'Could not load the page. Please check the URL and try again.';
        _urlLoading = false;
      });
    }
  }

  Future<String> _fetchHtml(String url) async {
    final uri = recipeFetchUri(url);
    final resp = await http.get(uri).timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) throw Exception('Backend ${resp.statusCode}');
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body.containsKey('error')) throw Exception(body['error']);
    final html = body['html'] as String? ?? '';
    if (html.isEmpty) throw Exception('Empty response');
    return html;
  }

  // ── Screenshot import pipeline ─────────────────────────────────────────────

  Future<void> _pickScreenshots() async {
    final picked = await _picker.pickMultiImage(imageQuality: 82);
    if (picked.isEmpty) return;

    // Pre-load bytes for thumbnail display.
    final newCache = <int, Uint8List>{};
    final startIndex = _selectedImages.length;
    for (int i = 0; i < picked.length; i++) {
      try {
        newCache[startIndex + i] = await picked[i].readAsBytes();
      } catch (_) {}
    }

    setState(() {
      _selectedImages = [..._selectedImages, ...picked];
      _thumbnailCache.addAll(newCache);
      _screenshotError = null;
      _screenshotPreview = null;
    });
  }

  void _removeScreenshot(int index) {
    setState(() {
      _selectedImages = [
        ..._selectedImages.sublist(0, index),
        ..._selectedImages.sublist(index + 1),
      ];
      // Rebuild cache with corrected indices.
      final rebuilt = <int, Uint8List>{};
      for (int i = 0; i < _selectedImages.length; i++) {
        final old = _thumbnailCache[i >= index ? i + 1 : i];
        if (old != null) rebuilt[i] = old;
      }
      _thumbnailCache
        ..clear()
        ..addAll(rebuilt);
      _screenshotPreview = null;
      _screenshotError = null;
    });
  }

  Future<void> _importFromScreenshots() async {
    if (_selectedImages.isEmpty) return;

    // Collect bytes — use cache when possible; re-read otherwise.
    final imageBytes = <Uint8List>[];
    final mimeTypes = <String>[];
    for (int i = 0; i < _selectedImages.length; i++) {
      final cached = _thumbnailCache[i];
      imageBytes.add(cached ?? await _selectedImages[i].readAsBytes());
      mimeTypes.add(_mimeTypeFromPath(_selectedImages[i].path));
    }

    setState(() {
      _screenshotLoading = true;
      _screenshotLoadingMessage = 'Starting…';
      _screenshotError = null;
      _screenshotPreview = null;
    });

    try {
      final recipe = await extractRecipeFromScreenshots(
        imageBytes,
        mimeTypes: mimeTypes,
        onProgress: (msg) {
          if (mounted) setState(() => _screenshotLoadingMessage = msg);
        },
      );

      if (recipe == null) {
        setState(() {
          _screenshotError =
              'Could not extract a recipe from the selected screenshots. '
              'Try selecting clearer images or add more screenshots.';
          _screenshotLoading = false;
        });
        return;
      }

      List<String> tools = recipe.tools;
      if (tools.isEmpty && recipe.steps.isNotEmpty) {
        setState(() => _screenshotLoadingMessage = 'Extracting tools…');
        tools = await _extractTools(recipe.steps);
      }

      setState(() {
        _screenshotPreview = Recipe(
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
          isImported: true,
        );
        _screenshotLoading = false;
      });
    } catch (_) {
      setState(() {
        _screenshotError =
            'Something went wrong while reading the screenshots. Please try again.';
        _screenshotLoading = false;
      });
    }
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  /// Calls /extract-tools; falls back to rule-based extraction.
  Future<List<String>> _extractTools(List<String> steps) async {
    final stepsText = steps.join('\n');
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
              .map((s) => s[0].toUpperCase() + s.substring(1))
              .toList();
          if (vlmTools.isNotEmpty) return vlmTools;
        }
      }
    } catch (_) {}
    return _inferToolsFromText(stepsText);
  }

  static String _mimeTypeFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = groceryPagePadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Import Recipe')),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── URL import section ─────────────────────────────────
                    _SectionHeading(
                      icon: Icons.link_rounded,
                      title: 'Import from URL',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Works best with popular recipe sites that include '
                      'structured data (AllRecipes, Food Network, BBC Good '
                      'Food, Serious Eats, etc.).',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: TextFormField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Recipe URL',
                          labelStyle:
                              const TextStyle(color: Colors.white60),
                          hintText:
                              'https://www.allrecipes.com/recipe/...',
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
                          errorStyle: const TextStyle(
                              color: Color(0xFFFF8A80)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
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
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: GroceryGlowButton(
                        onPressed: _urlLoading ? null : _parseUrl,
                        child: const Text('Import from URL'),
                      ),
                    ),
                    if (_urlLoading) ...[
                      const SizedBox(height: 28),
                      _LoadingIndicator(message: _urlLoadingMessage),
                    ],
                    if (_urlError != null) ...[
                      const SizedBox(height: 20),
                      _ErrorBox(message: _urlError!),
                    ],
                    if (_urlPreview != null) ...[
                      const SizedBox(height: 32),
                      _PreviewCard(recipe: _urlPreview!),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: GroceryGlowButton(
                          onPressed: () => _confirm(_urlPreview!),
                          child: const Text('Add to My Recipes'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _urlPreview = null),
                          child: const Text(
                            'Try a different URL',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      ),
                    ],

                    // ── Divider ─────────────────────────────────────────────
                    const SizedBox(height: 36),
                    const _OrDivider(),
                    const SizedBox(height: 36),

                    // ── Screenshot import section ──────────────────────────
                    _SectionHeading(
                      icon: Icons.photo_library_outlined,
                      title: 'Import from Screenshots',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select one or more screenshots from the same recipe. '
                      'A single recipe can span several images — all selected '
                      'screenshots are combined into one recipe.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: _OutlineButton(
                        onPressed: _screenshotLoading
                            ? null
                            : _pickScreenshots,
                        icon: Icons.add_photo_alternate_outlined,
                        label: _selectedImages.isEmpty
                            ? 'Select Recipe Screenshots'
                            : 'Add More Screenshots',
                      ),
                    ),

                    // Thumbnail strip + count
                    if (_selectedImages.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        label:
                            '${_selectedImages.length} screenshot${_selectedImages.length == 1 ? '' : 's'} selected.',
                        child: Text(
                          '${_selectedImages.length} screenshot${_selectedImages.length == 1 ? '' : 's'} selected',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: kBrandPurpleLight,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0;
                                i < _selectedImages.length;
                                i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              _ThumbnailChip(
                                bytes: _thumbnailCache[i],
                                index: i,
                                onRemove: _screenshotLoading
                                    ? null
                                    : () => _removeScreenshot(i),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: GroceryGlowButton(
                          onPressed:
                              _screenshotLoading ? null : _importFromScreenshots,
                          child: const Text('Import Recipe'),
                        ),
                      ),
                    ],

                    if (_screenshotLoading) ...[
                      const SizedBox(height: 28),
                      _LoadingIndicator(message: _screenshotLoadingMessage),
                    ],
                    if (_screenshotError != null) ...[
                      const SizedBox(height: 20),
                      _ErrorBox(message: _screenshotError!),
                    ],
                    if (_screenshotPreview != null) ...[
                      const SizedBox(height: 32),
                      _PreviewCard(recipe: _screenshotPreview!),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: GroceryGlowButton(
                          onPressed: () => _confirm(_screenshotPreview!),
                          child: const Text('Add to My Recipes'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _screenshotPreview = null;
                            _selectedImages = [];
                            _thumbnailCache.clear();
                          }),
                          child: const Text(
                            'Try different screenshots',
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
    );
  }
}

// ─── Shared UI components ─────────────────────────────────────────────────────

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: kBrandPurpleLight, size: 22),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
          ),
        ),
        const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
      ],
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const CircularProgressIndicator(color: kBrandPurpleLight),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4A1A1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF8A80), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: Color(0xFFFF8A80), fontSize: 15, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Outline (non-filled) button — used for "Select screenshots" to visually
/// distinguish it from the primary import action.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 16)),
      style: OutlinedButton.styleFrom(
        foregroundColor: kBrandPurpleLight,
        side: BorderSide(
          color: onPressed == null
              ? Colors.white24
              : kBrandPurpleLight.withValues(alpha: 0.7),
          width: 2,
        ),
        padding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

/// A screenshot thumbnail with an "×" remove button overlaid in the corner.
class _ThumbnailChip extends StatelessWidget {
  const _ThumbnailChip({
    required this.bytes,
    required this.index,
    required this.onRemove,
  });
  final Uint8List? bytes;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Screenshot ${index + 1}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 90,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFF1E2130),
              border: Border.all(
                color: kBrandPurpleLight.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: bytes != null
                ? Image.memory(bytes!, fit: BoxFit.cover)
                : const Center(
                    child: Icon(Icons.image_outlined,
                        color: Colors.white38, size: 32),
                  ),
          ),
          // Remove button
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: onRemove,
              child: Semantics(
                button: true,
                label: 'Remove screenshot ${index + 1}',
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCC3333),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF0E0F1A), width: 2),
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 12),
                ),
              ),
            ),
          ),
        ],
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
        color: const Color(0xFF1E2130),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: kBrandPurpleLight.withValues(alpha: 0.4)),
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
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.access_time_rounded,
                    size: 16, color: kBrandPurpleLight),
                const SizedBox(width: 5),
                Text(
                  recipe.estimatedTimeMinutes > 0
                      ? '~${recipe.estimatedTimeMinutes} min'
                      : 'Time unknown',
                  style:
                      TextStyle(color: kBrandPurpleLight, fontSize: 14),
                ),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.restaurant_menu_rounded,
                    size: 16, color: Colors.white54),
                const SizedBox(width: 5),
                Text(
                  '${recipe.ingredients.length} ingredient${recipe.ingredients.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 14),
                ),
              ]),
              if (recipe.steps.isNotEmpty)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.format_list_numbered_rounded,
                      size: 16, color: Colors.white54),
                  const SizedBox(width: 5),
                  Text(
                    '${recipe.steps.length} steps',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 14),
                  ),
                ]),
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
                      '• ${i.name}${i.quantity.isNotEmpty ? ' — ${i.quantity}' : ''}',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ),
            if (recipe.ingredients.length > 5)
              Text(
                '  + ${recipe.ingredients.length - 5} more',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 13),
              ),
          ],
          if (recipe.allergens.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: Color(0xFFFFAA44)),
                for (final a in recipe.allergens)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A2800),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      a,
                      style: const TextStyle(
                          color: Color(0xFFFFAA44), fontSize: 12),
                    ),
                  ),
              ],
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

// ─── schema.org / JSON-LD parser (URL import only) ────────────────────────────

Recipe? _parseSchemaOrgRecipe(String html, String sourceUrl) {
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
  final name = _decodeHtmlEntities(
      _str(s['name']) ?? _str(s['headline']) ?? 'Imported Recipe');

  int minutes = _parseDuration(s['totalTime']);
  if (minutes == 0) {
    minutes =
        _parseDuration(s['cookTime']) + _parseDuration(s['prepTime']);
  }

  final servings = _parseServings(s['recipeYield']);

  final rawIngredients = s['recipeIngredient'];
  final ingredients = <RecipeIngredient>[];
  if (rawIngredients is List) {
    for (final item in rawIngredients) {
      final text =
          _decodeHtmlEntities(_str(item)?.trim() ?? '');
      if (text.isEmpty) continue;
      final parts = _splitQuantityName(text);
      final cleanedName = _cleanIngredientName(parts.$2);
      if (cleanedName.isEmpty) continue;
      ingredients
          .add(RecipeIngredient(cleanedName, quantity: parts.$1));
    }
  }

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

  final category = _detectCategory(s, name);
  final dietaryPrefs = _parseDietaryPrefs(s);
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

(String, String) _splitQuantityName(String text) {
  final t = _decodeHtmlEntities(text);
  const num = r'[\d\.\/\s¼½¾⅓⅔⅛⅜⅝⅞]+';
  const units =
      r'cup|cups|tablespoon|tablespoons|tbsp|teaspoon|teaspoons|tsp|'
      r'oz|ounce|ounces|pound|pounds|lb|lbs|gram|grams|g|kg|ml|'
      r'liter|liters|l|can|cans|bunch|bunches|clove|cloves|'
      r'slice|slices|piece|pieces|package|packages|pkg|'
      r'bag|bags|box|boxes|stick|sticks|bar|bars|'
      r'sprig|sprigs|sheet|sheets|strip|strips|'
      r'to taste|as needed|pinch';
  final re = RegExp('^($num(?:$units)\\b)\\s*(.*)', caseSensitive: false);
  final m = re.firstMatch(t);
  if (m != null) return (m.group(1)!.trim(), m.group(2)!.trim());
  final numRe = RegExp(r'^([\d\.\/\s¼½¾⅓⅔⅛⅜⅝⅞]+)\s+(.+)');
  final nm = numRe.firstMatch(t);
  if (nm != null) return (nm.group(1)!.trim(), nm.group(2)!.trim());
  return ('', t);
}

List<String> _inferToolsFromText(String stepsText) {
  if (stepsText.isEmpty) return [];
  final s = stepsText.toLowerCase();
  final found = <String>[];
  void check(Pattern p, String name) {
    if (p is RegExp ? p.hasMatch(s) : s.contains(p as String)) {
      found.add(name);
    }
  }

  check(RegExp(r'\boven\b|preheat'), 'Oven');
  check(RegExp(r'baking sheet|sheet pan|cookie sheet'), 'Baking sheet');
  check(RegExp(r'baking dish|casserole dish|9x13'), 'Baking dish');
  check(RegExp(r'\bskillet\b|frying pan|sauté pan|saute pan'),
      'Skillet or frying pan');
  check(RegExp(r'\bsaucepan\b|small pot|medium pot'), 'Saucepan');
  check(RegExp(r'large pot|stock pot|dutch oven'), 'Large pot');
  check(RegExp(r'mixing bowl|large bowl|medium bowl|small bowl'),
      'Mixing bowl');
  check(RegExp(r'\bblender\b'), 'Blender');
  check(RegExp(r'food processor'), 'Food processor');
  check(RegExp(r'\bknife\b|cutting board|chopping board'),
      'Knife and cutting board');
  check(RegExp(r'\bspatula\b'), 'Spatula');
  check(RegExp(r'\bwhisk\b'), 'Whisk');
  check(RegExp(r'wooden spoon|mixing spoon'), 'Wooden spoon');
  check(RegExp(r'measuring cup'), 'Measuring cups');
  check(RegExp(r'measuring spoon'), 'Measuring spoons');
  check(RegExp(r'\bcolander\b|\bstrainer\b'), 'Colander');
  check(RegExp(r'\bgrater\b'), 'Grater');
  check(RegExp(r'rolling pin'), 'Rolling pin');
  check(RegExp(r'meat mallet|tenderizer'), 'Meat mallet');
  check(RegExp(r'plastic wrap|cling wrap'), 'Plastic wrap');
  check(RegExp(r'aluminum foil|tin foil'), 'Aluminum foil');
  check(RegExp(r'electric mixer|hand mixer|stand mixer'), 'Electric mixer');
  check(RegExp(r'oven mitt|oven glove'), 'Oven mitts');
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

  if (RegExp(
          r'\b(breakfast|brunch|morning|pancake|waffle|omelette|omelet|cereal|granola|muffin|bagel)\b')
      .hasMatch(hints)) return 'Breakfast';
  if (RegExp(
          r'\b(dessert|cake|cookie|pie|brownie|pudding|ice.?cream|pastry|sweet|tart|cupcake|candy|chocolate)\b')
      .hasMatch(hints)) return 'Desserts';
  if (RegExp(
          r'\b(dinner|lunch|main|entree|soup|sandwich|burger|pasta|salad|chicken|beef|pork|fish|rice|noodle|pizza|stir.?fry|roast|grill|bake)\b')
      .hasMatch(hints)) return 'Entrées';
  return kImportedCategory;
}

List<String> _parseDietaryPrefs(Map<dynamic, dynamic> s) {
  final raw = s['suitableForDiet'];
  final tags = <String>[];
  final list =
      raw is List ? raw : (raw is String ? [raw] : <dynamic>[]);
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

String _cleanIngredientName(String raw) {
  var s = raw.replaceAll(RegExp(r'\(.*?\)'), '');
  final commaIdx = s.indexOf(',');
  if (commaIdx >= 0) s = s.substring(0, commaIdx);
  return s.trim();
}

int? _parseServings(dynamic raw) {
  final s = _str(raw) ?? '';
  if (s.isEmpty) return null;
  final m = RegExp(r'(\d+)').firstMatch(s);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  return (n != null && n > 0) ? n : null;
}
