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

  /// True for recipes suggested by Gemini via the "Surprise Me!" feature.
  /// Behaves like [isImported] (shows ingredients, hides steps).
  final bool isRecommended;

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
    this.isRecommended = false,
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
      RecipeIngredient('Granola', quantity: '½ cup'),
      RecipeIngredient('Berries', quantity: '½ cup'),
      RecipeIngredient('Honey', quantity: '1 tablespoon'),
    ],
    tools: [
      'Bowl or glass',
      'Spoon',
      'Measuring cup',
    ],
    steps: [
      'Add ½ cup yogurt to a bowl or glass.',
      'Add ¼ cup granola on top of the yogurt.',
      'Add ¼ cup berries on top of the granola.',
      'Add the remaining ½ cup yogurt.',
      'Add the remaining ¼ cup granola.',
      'Add the remaining ¼ cup berries.',
      'Drizzle 1 tablespoon honey over the top and serve.',
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
      RecipeIngredient('Sugar', quantity: '2 tablespoons'),
      RecipeIngredient('Baking powder', quantity: '2 teaspoons'),
      RecipeIngredient('Salt', quantity: '¼ teaspoon'),
      RecipeIngredient('Milk', quantity: '¾ cup'),
      RecipeIngredient('Egg', quantity: '1'),
      RecipeIngredient('Butter', quantity: '2 tablespoons'),
    ],
    tools: [
      'Large mixing bowl',
      'Measuring cups',
      'Measuring spoons',
      'Frying pan',
      'Spatula',
      '¼-cup measuring cup',
    ],
    steps: [
      'Add 1 cup flour, 2 tablespoons sugar, 2 teaspoons baking powder, and ¼ teaspoon salt to a large mixing bowl.',
      'Stir the dry ingredients together for 30 seconds.',
      'Add ¾ cup milk and 1 egg to the bowl.',
      'Put 2 tablespoons butter in a microwave-safe container and microwave for 20 seconds, then another 10 seconds if needed until melted.',
      'Pour the melted butter into the bowl and mix for about 1 minute until the batter is thick but pourable; small lumps are okay.',
      'Place a frying pan on the stove over medium heat and let it warm for 2 minutes.',
      'Fill a ¼-cup measuring cup with batter and pour it into the center of the pan.',
      'Cook for 2–3 minutes until the edges feel firm and the top changes from wet and shiny to mostly dry.',
      'Slide a spatula underneath the pancake and carefully flip it over.',
      'Cook the second side for 1–2 minutes until the pancake feels firm when gently pressed with the spatula.',
      'Use the spatula to move the finished pancake onto a plate.',
    ],
  ),

  Recipe(
    id: 'scrambled_eggs',
    name: 'Scrambled Eggs',
    category: 'Breakfast',
    estimatedTimeMinutes: 10,
    difficulty: 2,
    dietaryPreferences: ['Vegetarian', 'Gluten-Free'],
    allergens: ['Eggs', 'Dairy'],
    ingredients: [
      RecipeIngredient('Eggs', quantity: '3 large'),
      RecipeIngredient('Milk, plant milk, or water', quantity: '1 teaspoon'),
      RecipeIngredient('Olive oil or butter', quantity: '1–2 teaspoons or 1 pat'),
      RecipeIngredient('Sea salt', quantity: '⅛ teaspoon'),
      RecipeIngredient('Black pepper', quantity: '⅛ teaspoon'),
      RecipeIngredient('Fresh chives, chopped', quantity: '1 teaspoon (optional)'),
    ],
    tools: [
      'Small mixing bowl',
      'Fork or whisk',
      'Non-stick skillet',
      'Spatula',
      'Measuring spoons',
      'Knife and cutting board',
    ],
    steps: [
      'Crack 3 eggs into a small mixing bowl, then add 1 teaspoon milk, ⅛ teaspoon salt, and ⅛ teaspoon pepper.',
      'Whisk the eggs vigorously for 30 seconds until frothy.',
      'Place a non-stick skillet on the stove over medium-low heat.',
      'Add 1–2 teaspoons oil or 1 pat of butter to the skillet and swirl to coat the pan.',
      'Pour the eggs into the skillet and let them sit for 20 seconds until the edges begin to set.',
      'Gently stir the eggs with a spatula, pushing cooked egg toward the center and tilting the pan so uncooked egg flows underneath.',
      'Continue cooking for 1–2 minutes until the eggs are softly set and creamy, then remove them from the pan while slightly underdone.',
      'Turn off the stove and remove the pan from the heat.',
      'Optional: Chop 1 teaspoon chives, sprinkle them over the eggs, and serve warm.',
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
      RecipeIngredient('Water', quantity: '1⅓ cups'),
      RecipeIngredient('Bread', quantity: '2 slices'),
      RecipeIngredient('Butter', quantity: '1 tablespoon'),
      RecipeIngredient('Cheese', quantity: '2 slices'),
    ],
    tools: [
      'Medium saucepan',
      'Frying pan',
      'Measuring cup',
      'Measuring spoon',
      'Spatula',
      'Plate',
      'Bowl',
    ],
    steps: [
      'Open 1 can of Campbell\'s Condensed Tomato Soup and pour it into a medium saucepan.',
      'Add 1⅓ cups water to the saucepan and stir it together with the soup.',
      'Place the saucepan on the stove over medium heat and cook for 5–7 minutes, stirring every 1–2 minutes.',
      'When the soup is hot and steaming, turn off the heat and leave it in the saucepan while you make the sandwich.',
      'Spread 1 tablespoon butter over one side of each of 2 slices of bread.',
      'Place a frying pan on the stove over medium-low heat and warm it for 2 minutes.',
      'Place one bread slice in the pan with the buttered side facing down.',
      'Place 2 slices of cheese on the bread and add the second bread slice with its buttered side facing up.',
      'Cook the sandwich for 3–4 minutes until you hear a gentle sizzling sound.',
      'Slide a spatula underneath the sandwich and carefully flip it over.',
      'Cook the second side for another 3–4 minutes until the bread feels firm and crisp and the cheese is melted.',
      'Turn off the stove and use the spatula to move the sandwich onto a plate.',
      'Carefully pour the hot tomato soup into a bowl and serve it with the sandwich.',
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
      RecipeIngredient('Frozen beef patty', quantity: '1'),
      RecipeIngredient('Hamburger bun', quantity: '1'),
      RecipeIngredient('Cooking oil', quantity: '1 teaspoon (if patty is lean)'),
      RecipeIngredient('Salt and pepper', quantity: 'to taste'),
      RecipeIngredient('Cheese', quantity: '1 slice (optional)'),
      RecipeIngredient('Lettuce, tomato, onion, pickles', quantity: 'for toppings'),
      RecipeIngredient('Ketchup, mustard, or mayo', quantity: 'as desired'),
    ],
    tools: [
      'Heavy skillet or grill',
      'Spatula',
      'Plate',
      'Knife and cutting board',
      'Lid or foil',
    ],
    steps: [
      'Place a skillet on the stove over medium-high heat and warm it for 2 minutes.',
      'Season both sides of the frozen patty with salt and pepper if needed.',
      'If using a lean patty, add 1 teaspoon of oil to the skillet.',
      'Place the frozen patty in the hot skillet and cook without moving it for 4–5 minutes until a brown crust forms.',
      'Slide a spatula under the patty and flip it over.',
      'Cook for 4–5 minutes for medium or 6–7 minutes for well-done.',
      'If using cheese, place 1 slice on top of the patty, cover the skillet with a lid or foil, and cook for 1 more minute until melted.',
      'Turn off the stove, remove the patty from the skillet, place it on a plate, and let it rest for 2 minutes.',
      'Place the bun halves face-down in the warm skillet and toast for 30 seconds until lightly golden.',
      'Spread ketchup, mustard, or mayonnaise on the bun.',
      'Add lettuce, tomato, onion, and pickles to the bottom bun.',
      'Place the patty on top, add the top bun, and serve immediately.',
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
      RecipeIngredient('Fresh mozzarella', quantity: '½ pound'),
      RecipeIngredient('Fresh basil leaves', quantity: '⅛ cup (about 6 small leaves)'),
      RecipeIngredient('Tomato paste', quantity: '1 can (6 ounces)'),
      RecipeIngredient('Water', quantity: '1½ cups'),
      RecipeIngredient('Garlic', quantity: '4 cloves, chopped'),
      RecipeIngredient('Olive oil', quantity: '¼ cup'),
      RecipeIngredient('Kosher salt', quantity: '¼ teaspoon'),
      RecipeIngredient('Black pepper', quantity: '⅛ teaspoon'),
      RecipeIngredient('Sesame seeds', quantity: '1 teaspoon'),
    ],
    tools: [
      'Baking sheet or pizza pan',
      'Small mixing bowl',
      'Whisk or fork',
      'Measuring cups and spoons',
      'Knife and cutting board',
      'Rolling pin (optional)',
      'Oven mitts',
    ],
    steps: [
      'Preheat the oven to 425–475 degrees Fahrenheit, following the dough package for the exact temperature.',
      'Add 1 can tomato paste, 1½ cups water, 4 chopped garlic cloves, ¼ cup olive oil, ¼ teaspoon salt, and ⅛ teaspoon pepper to a small bowl, then whisk until smooth and set aside.',
      'Lightly flour the work surface and stretch or roll the pizza dough into a 12–14 inch circle.',
      'Lightly oil a baking sheet and transfer the dough onto it.',
      'Spread the sauce over the dough, leaving a ½-inch border around the edge for the crust.',
      'Tear the mozzarella into small chunks and scatter them over the sauce.',
      'Sprinkle 1 teaspoon sesame seeds over the crust edges.',
      'Bake the pizza for 12–18 minutes until the crust is golden and the cheese is bubbly.',
      'Put on oven mitts and remove the baking sheet from the oven.',
      'Tear the basil leaves and scatter them over the hot pizza, then slice and serve.',
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
    steps: [
      'Break up any clumps in the cold rice with your fingers and set it aside.',
      'Place a large skillet or wok on the stove over medium-high heat, add 2 tablespoons of oil, and swirl to coat the pan.',
      'Add 1 cup frozen peas and carrots and stir-fry for 2–3 minutes until heated through.',
      'Push the vegetables to one side of the pan, crack 2 eggs into the empty side, and scramble them with a spatula for about 1 minute until fully cooked.',
      'Add the cold rice and stir everything together.',
      'Cook for 2–3 minutes, tossing frequently, until the rice is hot and slightly toasted.',
      'Drizzle 1 tablespoon soy sauce over the rice and toss to coat evenly.',
      'Taste the rice and add more soy sauce if needed, up to 2 tablespoons total.',
      'Turn off the stove and serve hot.',
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
      RecipeIngredient('Dry spaghetti, broken in half', quantity: '⅓ cup'),
      RecipeIngredient('Lean ground meat', quantity: '⅓ cup'),
      RecipeIngredient('Olive oil', quantity: '½ tablespoon'),
      RecipeIngredient('Chopped onion', quantity: '2 tablespoons plus 1 teaspoon'),
      RecipeIngredient('Minced garlic', quantity: '½ teaspoon'),
      RecipeIngredient('Tomato paste', quantity: '1 teaspoon'),
      RecipeIngredient('Dried oregano', quantity: '⅛ teaspoon'),
      RecipeIngredient('Crushed red pepper flakes', quantity: 'tiny pinch'),
      RecipeIngredient('Water, broth, or red wine', quantity: '2½ tablespoons'),
      RecipeIngredient('Crushed tomatoes', quantity: '⅔ cup'),
      RecipeIngredient('Salt', quantity: '¼ teaspoon'),
      RecipeIngredient('Black pepper', quantity: 'to taste'),
      RecipeIngredient('Fresh basil leaves', quantity: '2 small, torn'),
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
    steps: [
      'Fill a pot with water, add a pinch of salt, place it on the stove over high heat, and wait for the water to boil.',
      'Add the spaghetti and cook according to the package directions until tender, then drain it in a colander and set it aside.',
      'Place a skillet on the stove over medium heat, add ½ tablespoon olive oil, and warm it for 1 minute.',
      'Add the chopped onion and cook for 3 minutes until soft, then add ½ teaspoon minced garlic and cook for 1 minute.',
      'Add the ground meat, break it apart with a wooden spoon, and cook for 5 minutes until browned.',
      'Add 1 teaspoon tomato paste, ⅛ teaspoon oregano, a tiny pinch of red pepper flakes, ¼ teaspoon salt, and black pepper to taste, then stir and cook for 1 minute.',
      'Add 2½ tablespoons water, broth, or wine and ⅔ cup crushed tomatoes, then stir everything together.',
      'Turn the heat to low and simmer for 15 minutes, stirring every few minutes.',
      'Taste the sauce and add more salt or pepper if needed.',
      'Add the cooked spaghetti to the skillet and toss it with the sauce.',
      'Tear the basil leaves and sprinkle them over the pasta, then grate Parmesan cheese over the top and serve hot.',
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
      RecipeIngredient('Granulated sugar', quantity: '¾ cup'),
      RecipeIngredient('Brown sugar', quantity: '¾ cup, packed'),
      RecipeIngredient('Eggs', quantity: '2 large'),
      RecipeIngredient('Vanilla extract', quantity: '1 teaspoon'),
      RecipeIngredient('All-purpose flour', quantity: '2¼ cups'),
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
    steps: [
      'Soften 1 cup (2 sticks) of butter and place it in a large mixing bowl.',
      'Add ¾ cup granulated sugar and ¾ cup packed brown sugar to the bowl.',
      'Mix the butter and sugars for about 2 minutes until smooth and creamy.',
      'Add 2 large eggs and 1 teaspoon vanilla extract to the bowl.',
      'Mix for about 1 minute until everything is combined.',
      'Add 2¼ cups all-purpose flour, 1 teaspoon baking soda, and 1 teaspoon salt.',
      'Mix until the dough is thick and no dry flour can be felt while stirring.',
      'Add 2 cups of semi-sweet chocolate chips and mix until they are evenly spread throughout the dough.',
      'Scoop about 1 tablespoon of dough onto a baking sheet for each cookie, leaving about 2 inches between them.',
      'Preheat the oven to 375°F.',
      'Place the baking sheet in the oven and bake for 9–11 minutes.',
      'Check that the cookie edges feel firm while the centers remain soft.',
      'Put on oven mitts, remove the baking sheet from the oven, and let the cookies cool for 2 minutes.',
      'Use a spatula to move the cookies onto a plate.',
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
      RecipeIngredient('Vegetable oil', quantity: '½ cup'),
      RecipeIngredient('Eggs', quantity: '2'),
    ],
    tools: [
      'Large mixing bowl',
      'Measuring spoons',
      'Measuring cup',
      '13-by-9-inch baking pan',
      'Spatula',
      'Oven',
      'Oven mitts',
      'Toothpick',
      'Heat-safe surface',
      'Knife',
    ],
    steps: [
      'Pour 1 box of brownie mix into a large mixing bowl.',
      'Add 3 tablespoons of water, ½ cup vegetable oil, and 2 eggs to the bowl.',
      'Mix for about 1 minute until the batter is thick and smooth with no dry powder remaining.',
      'Pour the batter into a 13-by-9-inch baking pan and spread it evenly with a spatula.',
      'Preheat the oven to 350°F.',
      'Place the pan in the oven and bake for 24–28 minutes.',
      'Insert a toothpick into the center of the brownies and check that it comes out with a few moist crumbs but no wet batter.',
      'Put on oven mitts, remove the pan from the oven, and place it on a heat-safe surface.',
      'Let the brownies cool for at least 20 minutes before cutting.',
      'Cut the brownies and serve.',
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
