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
    steps: [
      'Rinse 1/4 cup of strawberries and 1/4 cup of blueberries under cool running water and pat dry.',
      'On a cutting board, use a knife to remove the green tops from the strawberries, then slice them into bite-sized pieces.',
      'Scoop 1 cup of yogurt into a bowl or glass and spread it evenly across the bottom.',
      'Sprinkle 1/2 cup of granola evenly over the yogurt.',
      'Scatter the sliced strawberries and 1/4 cup of blueberries on top of the granola.',
      'Drizzle 1 tablespoon of honey over the fruit and serve immediately.',
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
    steps: [
      'In a large mixing bowl, whisk together 1 cup of all-purpose flour, 2 teaspoons of baking powder, 2 tablespoons of sugar, and 1/4 teaspoon of salt.',
      'Melt 2 tablespoons of butter. Add it to the dry ingredients along with 1 cup of milk and 1 egg. Stir until just combined — a few small lumps are fine. Do not over-mix.',
      'Heat a frying pan or griddle over medium heat until a drop of water flicked onto it sizzles immediately.',
      'Pour about 1/4 cup of batter per pancake onto the pan. Cook for 2 to 3 minutes until bubbles form across the surface and the edges look set.',
      'Flip each pancake with the spatula and cook for 1 to 2 more minutes until the bottom is golden-brown.',
      'Repeat with the remaining batter. Serve warm with maple syrup.',
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
    steps: [
      'Crack 3 eggs into a bowl. Add 2 tablespoons of milk or water, a pinch of salt, and a pinch of pepper. Beat with a fork or whisk until the yolks and whites are fully combined.',
      'Place a frying pan over low-to-medium heat. Add 1 tablespoon of butter or oil and let it melt, tilting the pan to coat the bottom.',
      'Pour the egg mixture into the pan. Let it sit for about 20 seconds until the edges just begin to set.',
      'Using the spatula, gently push the eggs from the edges toward the center. Continue folding every 20 to 30 seconds, keeping the heat low.',
      'Remove the pan from heat when the eggs are just barely set — they will finish cooking from the residual heat. Serve immediately.',
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
    steps: [
      'Pour 1 can of condensed tomato soup and 1 1/2 cups of water into a medium saucepan. Stir to combine and place over medium heat.',
      'Heat the soup, stirring occasionally, for about 5 minutes until hot and steaming. Reduce to low heat to keep warm.',
      'Spread 1 tablespoon of butter evenly on one side of each bread slice.',
      'Heat a medium frying pan over medium heat. Place one bread slice butter-side down in the pan. Lay 2 slices of cheese on top, then place the second bread slice on top with the butter-side facing up.',
      'Cook for 2 to 3 minutes until the bottom is golden-brown. Flip with the spatula and cook the other side for 2 to 3 more minutes until golden-brown and the cheese is melted.',
      'Transfer the grilled cheese to a plate. Ladle the hot soup into a bowl. Serve together.',
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
    steps: [
      'Heat a heavy skillet or grill over medium-high heat. If needed, add 1 teaspoon of cooking oil and let it heat for 1 minute.',
      'Place 1 frozen burger patty directly on the hot surface. Season the top with salt and pepper if desired.',
      'Cook for 4 to 5 minutes without pressing down, until the edges turn gray and the underside is browned. Flip with the spatula.',
      'Cook the second side for 4 to 5 minutes until the patty is fully cooked through with no pink in the center. In the final minute, place 1 slice of cheese on top and cover with a lid or foil to melt.',
      'Remove the patty from heat and let it rest on a plate for 1 minute.',
      'Place the patty on the bottom half of the hamburger bun. Add any toppings you like and condiments as desired. Place the top bun on and serve.',
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
    steps: [
      'Preheat the oven to 450°F.',
      'In a small mixing bowl, whisk together 1 can (6 ounces) of tomato paste, 1 1/2 cups of water, 4 chopped garlic cloves, 1/4 cup of olive oil, 1/4 teaspoon of salt, and 1/4 teaspoon of black pepper until smooth.',
      'On a baking sheet or pizza pan, stretch or roll out 1 pound (16 ounces) of pizza dough to your desired thickness.',
      'Spread the sauce evenly over the dough, leaving a 1/2-inch border around the edge.',
      'Tear 1/2 pound of fresh mozzarella into pieces and scatter over the sauce. Sprinkle 1 teaspoon of sesame seeds along the crust edge.',
      'Bake for 12 to 15 minutes until the crust is golden-brown and the cheese is bubbling. Use oven mitts to remove from the oven.',
      'Scatter 1/2 cup of fresh basil leaves over the hot pizza, slice, and serve.',
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
      'Heat a large skillet or wok over high heat. Add 2 tablespoons of cooking oil and let it heat for 1 minute until shimmering.',
      'Add 1 cup of frozen peas and carrots to the hot oil. Stir-fry for 2 minutes until thawed and starting to brown at the edges.',
      'Push the vegetables to one side of the pan. Crack 2 eggs into the empty side and scramble with the spatula for about 1 minute until just set, then mix into the vegetables.',
      'Add 3 cups of cold cooked rice. Press it against the hot surface and cook undisturbed for 1 minute to lightly toast the bottom, then stir everything together.',
      'Drizzle 1 to 2 tablespoons of soy sauce over the rice. Stir-fry for 1 to 2 more minutes until evenly coated and heated through. Serve immediately.',
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
    steps: [
      'Bring a small pot of salted water to a boil over high heat. Add 3/4 cup of dry spaghetti and cook for 8 to 10 minutes, or until al dente. Drain in a colander and set aside.',
      'While the pasta cooks, heat 1/2 tablespoon of olive oil in a small skillet over medium-high heat. Add 1/3 cup of lean ground meat and cook, breaking it up with a wooden spoon, for 4 to 5 minutes until browned.',
      'Add 2 tablespoons plus 1 teaspoon of chopped onion to the skillet. Cook for 3 minutes until softened, then add 1/2 teaspoon of minced garlic and cook for 1 more minute.',
      'Stir in 1 tablespoon of tomato paste, 1/4 teaspoon of dried oregano, and a tiny pinch of crushed red pepper flakes. Add 2 1/2 tablespoons of water, broth, or red wine and stir to combine.',
      'Add 2/3 cup of crushed tomatoes, 1/4 teaspoon of salt, and black pepper to taste. Stir well and simmer on low heat for 5 minutes, stirring occasionally.',
      'Add the drained spaghetti to the sauce and toss until evenly coated. Serve topped with 2 torn fresh basil leaves and grated Parmesan cheese.',
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
    steps: [
      'Preheat the oven to 375°F.',
      'Let 1 cup (2 sticks) of butter soften to room temperature. In a large mixing bowl, beat the butter with 3/4 cup of granulated sugar and 3/4 cup of packed brown sugar until light and fluffy, about 2 minutes.',
      'Add 2 large eggs and 1 teaspoon of vanilla extract. Mix until smooth.',
      'Stir in 2 1/4 cups of all-purpose flour, 1 teaspoon of baking soda, and 1 teaspoon of salt until just combined — do not over-mix.',
      'Fold in 2 cups of semi-sweet chocolate chips.',
      'Drop rounded tablespoons of dough about 2 inches apart on an ungreased baking sheet.',
      'Bake for 9 to 11 minutes until the edges are golden-brown but the centers still look slightly soft.',
      'Use oven mitts to remove the baking sheet. Let the cookies cool on the sheet for 5 minutes, then transfer to a plate.',
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
    steps: [
      'Preheat the oven to 350°F.',
      'Pour 1 box of brownie mix into a large mixing bowl.',
      'Add 3 tablespoons of water, 1/2 cup of vegetable oil, and 2 eggs. Stir with a spoon for about 1 minute until the batter is thick and smooth with no dry powder remaining.',
      'Pour the batter into a 13-by-9-inch baking pan and spread it evenly with the spoon.',
      'Bake for 28 to 31 minutes. Insert a toothpick into the center — it is done when the toothpick comes out with a few moist crumbs, not wet batter.',
      'Use oven mitts to remove the pan from the oven. Set it on a heat-safe surface and let it cool for at least 15 minutes.',
      'Use a knife to cut the brownies into squares and serve.',
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
