import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/gemini_service.dart';
import 'package:my_low_vision_app/imported_recipes_state.dart';
import 'package:my_low_vision_app/recipe_data.dart';
import 'package:my_low_vision_app/recipe_detail_screen.dart';

void main() {
  test('OCR without a heading still keeps ingredients and steps', () {
    final recipe = debugParseOcrRecipe('''
Smoothie Bowl
1 cup yogurt
1/2 cup granola
1/2 cup berries
1 tablespoon honey
1. Add the yogurt to a bowl.
2. Top with granola and berries.
3. Drizzle honey over the top and serve.
''');

    expect(recipe, isNotNull);
    expect(recipe!.name, 'Smoothie Bowl');
    expect(
      recipe.ingredients.map((i) => i.name.toLowerCase()),
      containsAll(['yogurt', 'granola', 'berries', 'honey']),
    );
    expect(recipe.steps, isNotEmpty);
    expect(
      recipe.steps.any((s) => s.toLowerCase().contains('yogurt')),
      isTrue,
    );
    expect(
      recipe.steps.any((s) => _looksLikeQty(s)),
      isFalse,
    );
  });

  test('imported recipe keeps steps in the session and hides them on the page',
      () {
    final recipe = Recipe(
      id: 'smoothie_test',
      name: 'Smoothie Bowl',
      category: kImportedCategory,
      estimatedTimeMinutes: 10,
      difficulty: 2,
      dietaryPreferences: const ['No Restrictions'],
      allergens: const ['Dairy'],
      ingredients: const [
        RecipeIngredient('Yogurt', quantity: '1 cup'),
        RecipeIngredient('Granola', quantity: '1/2 cup'),
        RecipeIngredient('Berries', quantity: '1/2 cup'),
        RecipeIngredient('Honey', quantity: '1 tablespoon'),
      ],
      tools: const ['Blender', 'Spoon', 'Measuring cup', 'Bowl'],
      steps: const [
        'Add the yogurt to a bowl.',
        'Top with granola and berries.',
        'Drizzle honey over the top and serve.',
      ],
      isImported: true,
    );

    importedRecipesNotifier.value = [];
    addImportedRecipe(recipe);
    final saved = importedRecipesNotifier.value.single;
    expect(saved.steps, recipe.steps);
    expect(saved.ingredients, isNotEmpty);
  });

  testWidgets('detail page lists ingredients above tools and offers shopping',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const steps = [
      'Add the yogurt to a bowl.',
      'Top with granola and berries.',
    ];
    final recipe = Recipe(
      id: 'smoothie_test',
      name: 'Smoothie Bowl',
      category: kImportedCategory,
      estimatedTimeMinutes: 10,
      difficulty: 2,
      dietaryPreferences: const ['No Restrictions'],
      allergens: const ['Dairy'],
      ingredients: const [
        RecipeIngredient('Yogurt', quantity: '1 cup'),
        RecipeIngredient('Honey', quantity: '1 tablespoon'),
      ],
      tools: const ['Blender', 'Spoon'],
      steps: steps,
      isImported: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: RecipeDetailScreen(recipe: recipe)),
    );

    expect(find.text('Start Shopping'), findsOneWidget);
    expect(find.text('Yogurt'), findsOneWidget);
    expect(find.text('1 cup'), findsOneWidget);
    expect(find.text('Blender'), findsOneWidget);
    expect(find.text('Recipe details coming soon.'), findsNothing);
    for (final step in steps) {
      expect(find.text(step), findsNothing);
    }

    final ingredientsY = tester.getTopLeft(find.text('Ingredients')).dy;
    final toolsY = tester.getTopLeft(find.text('Tools')).dy;
    final shoppingY = tester.getTopLeft(find.text('Start Shopping')).dy;
    expect(ingredientsY, lessThan(toolsY));
    expect(toolsY, lessThan(shoppingY));
  });
}

bool _looksLikeQty(String line) => RegExp(
      r'^\d+(?:/\d+)?\s+(?:cup|tablespoon)',
      caseSensitive: false,
    ).hasMatch(line);
