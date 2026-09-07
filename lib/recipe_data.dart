/// Recipe data model and static recipe catalogue.
///
/// Ingredients, tools, and steps are intentionally empty — they will be
/// provided and populated in a later update. Do not generate content for them.

class Recipe {
  final String id;

  /// Display name shown on cards and detail pages.
  final String name;

  /// One of [kRecipeCategories]: 'Breakfast', 'Entrées', or 'Desserts'.
  final String category;

  final int estimatedTimeMinutes;

  /// Skill level 1–5 (no recipe currently exceeds 3).
  final int difficulty;

  /// e.g. ['Vegetarian', 'Gluten-Free']. Use 'No Restrictions' when no tag
  /// applies. 'No Restrictions' is purely descriptive and should not be
  /// rendered as a dietary preference chip.
  final List<String> dietaryPreferences;

  final List<String> allergens;

  // ── populated later ──────────────────────────────────────────────────────
  final List<String> ingredients;
  final List<String> tools;
  final List<String> steps;

  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.estimatedTimeMinutes,
    required this.difficulty,
    required this.dietaryPreferences,
    required this.allergens,
    this.ingredients = const [],
    this.tools = const [],
    this.steps = const [],
  });

  /// True once ingredients and/or steps have been added.
  bool get hasDetails => ingredients.isNotEmpty || steps.isNotEmpty;

  /// Dietary tags suitable for display (excludes the 'No Restrictions' marker).
  List<String> get displayDietaryPreferences =>
      dietaryPreferences.where((p) => p != 'No Restrictions').toList();
}

/// Ordered category list — controls section render order on the recipes page.
const List<String> kRecipeCategories = ['Breakfast', 'Entrées', 'Desserts'];

/// All application recipes.
const List<Recipe> kAllRecipes = [
  // ── BREAKFAST ────────────────────────────────────────────────────────────

  Recipe(
    id: 'yogurt_parfait',
    name: 'Yogurt Parfait',
    category: 'Breakfast',
    estimatedTimeMinutes: 10,
    difficulty: 1,
    dietaryPreferences: ['Vegetarian'],
    allergens: ['Dairy'],
  ),

  Recipe(
    id: 'pancakes',
    name: 'Pancakes',
    category: 'Breakfast',
    estimatedTimeMinutes: 25,
    difficulty: 3,
    dietaryPreferences: ['Vegetarian'],
    allergens: ['Wheat / Gluten', 'Dairy', 'Eggs'],
  ),

  Recipe(
    id: 'scrambled_eggs',
    name: 'Scrambled Eggs',
    category: 'Breakfast',
    estimatedTimeMinutes: 10,
    difficulty: 2,
    dietaryPreferences: ['Vegetarian', 'Gluten-Free'],
    allergens: ['Eggs'],
  ),

  // ── ENTRÉES ──────────────────────────────────────────────────────────────

  Recipe(
    id: 'grilled_cheese_soup',
    name: 'Grilled Cheese + Tomato Basil Soup',
    category: 'Entrées',
    estimatedTimeMinutes: 20,
    difficulty: 2,
    dietaryPreferences: ['Vegetarian'],
    allergens: ['Wheat / Gluten', 'Dairy'],
  ),

  Recipe(
    id: 'burger',
    name: 'Burger',
    category: 'Entrées',
    estimatedTimeMinutes: 20,
    difficulty: 2,
    dietaryPreferences: ['No Restrictions'],
    allergens: ['Wheat / Gluten'],
  ),

  Recipe(
    id: 'pizza',
    name: 'Pizza',
    category: 'Entrées',
    estimatedTimeMinutes: 25,
    difficulty: 2,
    dietaryPreferences: ['Vegetarian'],
    allergens: ['Wheat / Gluten', 'Dairy'],
  ),

  Recipe(
    id: 'veggie_fried_rice',
    name: 'Veggie Fried Rice',
    category: 'Entrées',
    estimatedTimeMinutes: 25,
    difficulty: 3,
    dietaryPreferences: ['Vegetarian', 'Dairy-Free'],
    allergens: ['Eggs', 'Soy'],
  ),

  Recipe(
    id: 'spaghetti',
    name: 'Spaghetti',
    category: 'Entrées',
    estimatedTimeMinutes: 30,
    difficulty: 3,
    dietaryPreferences: ['No Restrictions'],
    allergens: ['Wheat / Gluten', 'Dairy'],
  ),

  // ── DESSERTS ─────────────────────────────────────────────────────────────

  Recipe(
    id: 'chocolate_chip_cookies',
    name: 'Chocolate Chip Cookies',
    category: 'Desserts',
    estimatedTimeMinutes: 35,
    difficulty: 3,
    dietaryPreferences: ['Vegetarian'],
    allergens: ['Wheat / Gluten', 'Dairy', 'Eggs'],
  ),

  Recipe(
    id: 'brownies',
    name: 'Brownies',
    category: 'Desserts',
    estimatedTimeMinutes: 40,
    difficulty: 2,
    dietaryPreferences: ['Vegetarian', 'Dairy-Free'],
    allergens: ['Eggs'],
  ),
];
