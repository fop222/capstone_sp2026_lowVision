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

  /// Number of servings — only populated for imported recipes when the source
  /// site provides recipeYield.  Null means unknown / not displayed.
  final int? servings;

  /// True for recipes added via "Import Recipe from Link".
  /// Used to hide Tools / Instructions on the detail page.
  final bool isImported;

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
    this.servings,
    this.isImported = false,
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
    ingredients: [
      RecipeIngredient("Campbell's Condensed Tomato Soup", quantity: '1 can'),
      RecipeIngredient('Water', quantity: '1 1/2 cups'),
      RecipeIngredient('Bread', quantity: '2 slices'),
      RecipeIngredient('Butter', quantity: '1 tablespoon'),
      RecipeIngredient('Cheese', quantity: '2 slices'),
    ],
    tools: [
      'Medium saucepan',
      'Medium frying pan',
      'Measuring cup',
      'Measuring spoon',
      'Spatula',
      'Stove',
      'Plate',
      'Bowl',
    ],
  ),

  Recipe(
    id: 'burger',
    name: 'Burger',
    category: 'Entrées',
    estimatedTimeMinutes: 20,
    difficulty: 2,
    dietaryPreferences: ['No Restrictions'],
    allergens: ['Wheat / Gluten'],
    ingredients: [
      RecipeIngredient('Frozen lean burger patty', quantity: '1'),
      RecipeIngredient('Hamburger bun', quantity: '1'),
      RecipeIngredient('Cooking oil', quantity: '1 teaspoon, if patty is lean'),
      RecipeIngredient('Salt and pepper', quantity: 'to taste, if patty is unseasoned'),
      RecipeIngredient('Cheese', quantity: '1 slice, optional'),
      RecipeIngredient('Lettuce, tomato, onion, or pickles', quantity: 'optional toppings'),
      RecipeIngredient('Ketchup, mustard, or mayo', quantity: 'as desired'),
    ],
    tools: [
      'Heavy skillet or grill',
      'Spatula',
      'Plate',
      'Knife and cutting board',
      'Lid or foil',
    ],
  ),

  Recipe(
    id: 'pizza',
    name: 'Pizza',
    category: 'Entrées',
    estimatedTimeMinutes: 25,
    difficulty: 2,
    dietaryPreferences: ['Vegetarian'],
    allergens: ['Wheat / Gluten', 'Dairy'],
    ingredients: [
      RecipeIngredient('Pizza dough', quantity: '1 (16 ounces)'),
      RecipeIngredient('Fresh mozzarella', quantity: '1/2 pound'),
      RecipeIngredient('Fresh basil leaves', quantity: '1/2 cup'),
      RecipeIngredient('Tomato paste', quantity: '1 can (6 ounces)'),
      RecipeIngredient('Water', quantity: '1 1/2 cups'),
      RecipeIngredient('Garlic', quantity: '4 cloves, chopped'),
      RecipeIngredient('Olive oil', quantity: '1/4 cup'),
      RecipeIngredient('Kosher salt', quantity: '1/4 teaspoon'),
      RecipeIngredient('Black pepper', quantity: '1/4 teaspoon'),
      RecipeIngredient('Sesame seeds', quantity: '1 teaspoon'),
    ],
    tools: [
      'Baking sheet or pizza pan',
      'Small mixing bowl',
      'Whisk or fork',
      'Measuring cups and spoons',
      'Knife and cutting board',
      'Rolling pin, optional',
      'Oven mitts',
    ],
  ),

  Recipe(
    id: 'veggie_fried_rice',
    name: 'Veggie Fried Rice',
    category: 'Entrées',
    estimatedTimeMinutes: 25,
    difficulty: 3,
    dietaryPreferences: ['Vegetarian', 'Dairy-Free'],
    allergens: ['Eggs', 'Soy'],
    ingredients: [
      RecipeIngredient('Cold cooked rice', quantity: '3 cups'),
      RecipeIngredient('Frozen peas and carrots', quantity: '1 cup'),
      RecipeIngredient('Cooking oil', quantity: '2 tablespoons'),
      RecipeIngredient('Eggs', quantity: '2'),
      RecipeIngredient('Soy sauce', quantity: '1 to 2 tablespoons'),
    ],
    tools: [
      'Large skillet or wok',
      'Spatula or wooden spoon',
      'Measuring cups and spoons',
    ],
  ),

  Recipe(
    id: 'spaghetti',
    name: 'Spaghetti',
    category: 'Entrées',
    estimatedTimeMinutes: 30,
    difficulty: 3,
    dietaryPreferences: ['No Restrictions'],
    allergens: ['Wheat / Gluten', 'Dairy'],
    ingredients: [
      RecipeIngredient('Dry spaghetti', quantity: '3/4 cup'),
      RecipeIngredient('Lean ground meat', quantity: '1/3 cup'),
      RecipeIngredient('Olive oil', quantity: '1/2 tablespoon'),
      RecipeIngredient('Chopped onion', quantity: '2 tablespoons plus 1 teaspoon'),
      RecipeIngredient('Minced garlic', quantity: '1/2 teaspoon'),
      RecipeIngredient('Tomato paste', quantity: '1 tablespoon'),
      RecipeIngredient('Dried oregano', quantity: '1/4 teaspoon'),
      RecipeIngredient('Crushed red pepper flakes', quantity: 'tiny pinch'),
      RecipeIngredient('Water, broth, or red wine', quantity: '2 1/2 tablespoons'),
      RecipeIngredient('Crushed tomatoes', quantity: '2/3 cup'),
      RecipeIngredient('Salt', quantity: '1/4 teaspoon'),
      RecipeIngredient('Black pepper', quantity: 'to taste'),
      RecipeIngredient('Fresh basil leaves', quantity: '2 small leaves, torn'),
      RecipeIngredient('Parmesan cheese', quantity: 'for serving'),
    ],
    tools: [
      'Small pot',
      'Colander',
      'Small skillet',
      'Cutting board and knife',
      'Measuring cups and spoons',
      'Wooden spoon',
      'Grater',
    ],
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
    ingredients: [
      RecipeIngredient('Butter', quantity: '1 cup (2 sticks)'),
      RecipeIngredient('Granulated sugar', quantity: '3/4 cup'),
      RecipeIngredient('Brown sugar', quantity: '3/4 cup, packed'),
      RecipeIngredient('Eggs', quantity: '2 large'),
      RecipeIngredient('Vanilla extract', quantity: '1 teaspoon'),
      RecipeIngredient('All-purpose flour', quantity: '2 1/4 cups'),
      RecipeIngredient('Baking soda', quantity: '1 teaspoon'),
      RecipeIngredient('Salt', quantity: '1 teaspoon'),
      RecipeIngredient('Semi-sweet chocolate chips', quantity: '2 cups'),
    ],
    tools: [
      'Large mixing bowl',
      'Measuring cups',
      'Measuring spoons',
      'Mixing spoon or electric mixer',
      'Baking sheet',
      'Tablespoon or cookie scoop',
      'Spatula',
      'Oven mitts',
      'Plate',
    ],
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
