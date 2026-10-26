import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_tts.dart';
import 'dining_food.dart';
import 'grocery_ui.dart';
import 'recipe_widgets.dart';

/// Lists every food from one scan, in image order, then opens details.
class DiningResultsScreen extends StatefulWidget {
  const DiningResultsScreen({super.key, required this.foods, this.photoBytes});

  final List<DiningFood> foods;
  final Uint8List? photoBytes;

  @override
  State<DiningResultsScreen> createState() => _DiningResultsScreenState();
}

class _DiningResultsScreenState extends State<DiningResultsScreen> {
  final FlutterTts _tts = FlutterTts();
  late final List<DiningFood> _foods = sortDiningFoods(widget.foods);

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await applyEnglishTts(_tts);
      await _tts.speak(text);
    } catch (error) {
      debugPrint('Dining TTS unavailable: $error');
    }
  }

  void _openFood(DiningFood food) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiningFoodDetailScreen(food: food),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _foods.length == 1
        ? '1 food found'
        : '${_foods.length} foods found';
    return Scaffold(
      appBar: AppBar(title: const Text('Detected foods')),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: ListView(
                padding: groceryPagePadding(
                  context,
                ).add(const EdgeInsets.only(top: 20, bottom: 32)),
                children: [
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      count,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When distance is clear, the closest items are listed first. Tap an item for allergens and dietary details.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.4,
                    ),
                  ),
                  if (widget.photoBytes != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      label: 'Photo you scanned',
                      image: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          widget.photoBytes!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Semantics(
                    button: true,
                    label: 'Hear all foods',
                    excludeSemantics: true,
                    child: GroceryGlowButton(
                      onPressed: () => _speak(spokenDiningFoods(_foods)),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.volume_up_rounded, size: 28),
                          SizedBox(width: 10),
                          Text('Hear all foods'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (var i = 0; i < _foods.length; i++) ...[
                    _DiningFoodCard(
                      index: i + 1,
                      total: _foods.length,
                      food: _foods[i],
                      onTap: () => _openFood(_foods[i]),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: 'Scan another photo',
                    excludeSemantics: true,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: kBrandPurpleLight.withValues(alpha: 0.8),
                          width: 2,
                        ),
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Scan another photo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DiningFoodDetailScreen extends StatefulWidget {
  const DiningFoodDetailScreen({super.key, required this.food});

  final DiningFood food;

  @override
  State<DiningFoodDetailScreen> createState() => _DiningFoodDetailScreenState();
}

class _DiningFoodDetailScreenState extends State<DiningFoodDetailScreen> {
  final FlutterTts _tts = FlutterTts();

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak() async {
    try {
      await _tts.stop();
      await applyEnglishTts(_tts);
      await _tts.speak(spokenDiningFood(widget.food));
    } catch (error) {
      debugPrint('Dining TTS unavailable: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final food = widget.food;
    return Scaffold(
      appBar: AppBar(title: Text(food.dishName)),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: ListView(
                padding: groceryPagePadding(
                  context,
                ).add(const EdgeInsets.only(top: 20, bottom: 32)),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      food.dishName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DiningFoodFacts(food: food),
                  const SizedBox(height: 20),
                  Semantics(
                    button: true,
                    label: 'Hear this food',
                    excludeSemantics: true,
                    child: GroceryGlowButton(
                      onPressed: _speak,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.volume_up_rounded, size: 28),
                          SizedBox(width: 10),
                          Text('Hear this food'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiningFoodCard extends StatelessWidget {
  const _DiningFoodCard({
    required this.index,
    required this.total,
    required this.food,
    required this.onTap,
  });

  final int index;
  final int total;
  final DiningFood food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: 'Food $index of $total. ${spokenDiningFoodBrief(food)}',
        hint: 'Opens allergens and dietary details',
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: GroceryListCardShell(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '$index. ${food.dishName}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ],
                    ),
                    if (food.location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _FactLine(label: 'Location', value: food.locationLabel),
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

class DiningFoodFacts extends StatelessWidget {
  const DiningFoodFacts({super.key, required this.food});

  final DiningFood food;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FactLine(label: 'Location', value: food.locationLabel),
        const SizedBox(height: 12),
        _ClaimSection(
          title: 'Dietary preferences',
          claims: food.dietaryPreferences,
          dietary: true,
        ),
        const SizedBox(height: 12),
        _ClaimSection(
          title: 'Allergens',
          claims: food.allergens,
          dietary: false,
        ),
        const SizedBox(height: 12),
        _FactLine(
          label: 'Confidence',
          value: '${food.confidenceLabel} · ${food.sourceLabel}',
        ),
        if (food.signText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Sign says: ${food.signText}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          kPleaseConfirmWithStaff,
          style: TextStyle(
            color: Color(0xFFFFE2D6),
            fontSize: 20,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimSection extends StatelessWidget {
  const _ClaimSection({
    required this.title,
    required this.claims,
    required this.dietary,
  });

  final String title;
  final List<DiningClaim> claims;
  final bool dietary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFE0E0E0),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (claims.isEmpty)
          const Text(
            'Unknown',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final claim in claims)
                dietary
                    ? RecipeTag.dietary(label: claim.chipLabel)
                    : RecipeTag.allergen(label: claim.chipLabel),
            ],
          ),
      ],
    );
  }
}
