/// Recipe data model and static recipe catalogue.
///
/// Ingredients, tools, and steps are intentionally empty for most recipes —
/// they will be provided and populated in a later update. Do not generate
/// content for them.

// ─── RecipeIngredient ─────────────────────────────────────────────────────────

/// A single ingredient with an optional preparation quantity.
///
/// [quantity] is for display on the recipe detail page only (e.g. "1 cup",
/// "3", "1/4 teaspoon"). The shopping-list item is always created with
/// quantity = 1 regardless of this field.
class RecipeIngredient {
  final String name;

  /// Human-readable amount (e.g. "1 cup", "2 tablespoons", "to taste").
  /// Empty string means the quantity has not been specified yet.
  final String quantity;

  const RecipeIngredient(this.name, {this.quantity = ''});
}

// ─── Recipe ───────────────────────────────────────────────────────────────────

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

  // ── populated as data becomes available ───────────────────────────────────
  final List<RecipeIngredient> ingredients;
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
    ingredients: [
      RecipeIngredient('Yogurt', quantity: '1 cup'),
      RecipeIngredient('Granola', quantity: '1/2 cup'),
      RecipeIngredient('Strawberries', quantity: '1/4 cup'),
      RecipeIngredient('Blueberries', quantity: '1/4 cup'),
      RecipeIngredient('Honey', quantity: '1 tablespoon'),
    ],
    tools: [
      'Bowl or glass',
      'Spoon',
      'Measuring cup',
      'Knife',
      'Cutting board',
    ],
  ),

  Recipe(
    id: 'pancakes',
    name: 'Pancakes',
    category: 'Breakfast',
    estimatedTimeMinutes: 25,
    difficulty: 3,
    dietaryPreferences: ['Vegetarian'],
    allergens: ['Wheat / Gluten', 'Dairy', 'Eggs'],
    ingredients: [
      RecipeIngredient('All-purpose flour', quantity: '1 cup'),
      RecipeIngredient('Baking powder', quantity: '2 teaspoons'),
      RecipeIngredient('Sugar', quantity: '2 tablespoons'),
      RecipeIngredient('Salt', quantity: '1/4 teaspoon'),
      RecipeIngredient('Milk', quantity: '1 cup'),
      RecipeIngredient('Egg', quantity: '1'),
      RecipeIngredient('Butter', quantity: '2 tablespoons'),
      RecipeIngredient('Maple syrup', quantity: 'to taste'),
    ],
    tools: [
      'Large mixing bowl',
      'Measuring cups',
      'Measuring spoons',
      'Whisk',
      'Frying pan or griddle',
      'Spatula',
      'Ladle or measuring cup for pouring batter',
    ],
  ),

  Recipe(
    id: 'scrambled_eggs',
    name: 'Scrambled Eggs',
    category: 'Breakfast',
    estimatedTimeMinutes: 10,
    difficulty: 2,
    dietaryPreferences: ['Vegetarian', 'Gluten-Free'],
    allergens: ['Eggs'],
    ingredients: [
      RecipeIngredient('Eggs', quantity: '3'),
      RecipeIngredient('Salt', quantity: 'to taste'),
      RecipeIngredient('Pepper', quantity: 'to taste'),
      RecipeIngredient('Milk or water', quantity: '2 tablespoons'),
      RecipeIngredient('Butter or oil', quantity: '1 tablespoon'),
    ],
    tools: [
      'Bowl',
      'Fork or whisk',
      'Frying pan',
      'Spatula',
      'Measuring spoon',
    ],
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
    ingredients: [
      RecipeIngredient('Brownie mix', quantity: '1 box'),
      RecipeIngredient('Water', quantity: '3 tablespoons'),
      RecipeIngredient('Vegetable oil', quantity: '1/2 cup'),
      RecipeIngredient('Eggs', quantity: '2'),
    ],
    tools: [
      'Large mixing bowl',
      'Measuring spoons',
      'Measuring cup',
      '13-by-9-inch baking pan',
      'Oven',
      'Oven mitts',
      'Toothpick',
      'Heat-safe surface',
      'Knife',
    ],
  ),
];

// ─── Recipe-list detection ────────────────────────────────────────────────────

/// Exact names of all 10 predefined recipe-generated grocery lists.
///
/// A grocery list is considered a "recipe list" if and only if its title
/// exactly matches one of these names. Do NOT duplicate this check elsewhere —
/// always call [isRecipeList] instead.
const Set<String> kRecipeNames = {
  'Yogurt Parfait',
  'Pancakes',
  'Scrambled Eggs',
  'Grilled Cheese + Tomato Basil Soup',
  'Burger',
  'Pizza',
  'Veggie Fried Rice',
  'Spaghetti',
  'Chocolate Chip Cookies',
  'Brownies',
};

/// Returns `true` if [listTitle] exactly matches one of the 10 predefined
/// recipe names, meaning the list was generated from a recipe.
bool isRecipeList(String listTitle) => kRecipeNames.contains(listTitle);
