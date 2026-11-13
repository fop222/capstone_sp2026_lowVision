/// Grocery aisle signs name food groups ("FRUITS", "DAIRY", "SNACKS"), not
/// the items on a shopping list ("berries", "milk", "chips"). Matching only by
/// spelling missed every one of those, so a list item also matches a sign
/// that names its group.
library;

/// One aisle group: the words a sign uses for it, and the list items in it.
class AisleFoodGroup {
  const AisleFoodGroup(this.label, this.signWords, this.itemWords);

  /// Spoken name, e.g. "fruit" in "You are in the fruit aisle."
  final String label;

  /// Words or phrases printed on aisle signs for this group.
  final List<String> signWords;

  /// Words or phrases in list item names that belong to this group.
  final List<String> itemWords;
}

const List<AisleFoodGroup> kAisleFoodGroups = [
  AisleFoodGroup(
    'fruit',
    ['fruit', 'produce', 'fresh produce'],
    [
      'fruit',
      'mixed fruit',
      'berry',
      'strawberry',
      'blueberry',
      'raspberry',
      'blackberry',
      'cranberry',
      'apple',
      'banana',
      'orange',
      'grape',
      'lemon',
      'lime',
      'peach',
      'pear',
      'plum',
      'cherry',
      'mango',
      'pineapple',
      'melon',
      'watermelon',
      'cantaloupe',
      'kiwi',
      'avocado',
      'grapefruit',
      'clementine',
      'tangerine',
      'apricot',
      'nectarine',
      'pomegranate',
      'papaya',
      'coconut',
      'fig',
    ],
  ),
  AisleFoodGroup(
    'vegetable',
    ['vegetable', 'veggie', 'produce', 'fresh produce', 'salad'],
    [
      'vegetable',
      'lettuce',
      'spinach',
      'kale',
      'carrot',
      'onion',
      'garlic',
      'potato',
      'sweet potato',
      'tomato',
      'broccoli',
      'cauliflower',
      'cucumber',
      'bell pepper',
      'celery',
      'cabbage',
      'bok choy',
      'zucchini',
      'squash',
      'mushroom',
      'asparagus',
      'cilantro',
      'parsley',
      'basil',
      'fresh basil',
      'ginger',
      'beet',
      'radish',
      'arugula',
      'salad',
      'green bean',
    ],
  ),
  AisleFoodGroup(
    'dairy',
    ['dairy', 'milk', 'egg', 'cheese', 'yogurt', 'refrigerated'],
    [
      'milk',
      'almond milk',
      'oat milk',
      'cheese',
      'mozzarella',
      'parmesan',
      'cheddar',
      'provolone',
      'swiss',
      'feta',
      'ricotta',
      'yogurt',
      'yoghurt',
      'butter',
      'egg',
      'cream',
      'sour cream',
      'cream cheese',
      'creamer',
      'cottage cheese',
      'half and half',
      'pizza dough',
      'guacamole',
      'hummus',
      'dip',
    ],
  ),
  AisleFoodGroup(
    'bakery',
    ['bakery', 'bread'],
    [
      'bread',
      'bagel',
      'bun',
      'roll',
      'tortilla',
      'muffin',
      'croissant',
      'pita',
      'baguette',
      'english muffin',
      'donut',
      'doughnut',
      'pizza dough',
    ],
  ),
  AisleFoodGroup(
    'meat and seafood',
    ['meat', 'seafood', 'deli', 'poultry', 'butcher', 'fish'],
    [
      'meat',
      'chicken',
      'beef',
      'ground beef',
      'pork',
      'turkey',
      'ham',
      'prosciutto',
      'bacon',
      'sausage',
      'pepperoni',
      'steak',
      'burger',
      'patty',
      'cutlet',
      'salmon',
      'shrimp',
      'fish',
      'lamb',
      'hot dog',
      'salami',
      'deli meat',
      'tilapia',
      'cod',
      'crab',
    ],
  ),
  AisleFoodGroup(
    'frozen',
    ['frozen', 'freezer'],
    ['frozen', 'ice cream', 'ice cream cake', 'popsicle', 'ice pop'],
  ),
  AisleFoodGroup(
    'drinks',
    [
      'beverage',
      'drink',
      'soda',
      'water',
      'juice',
      'coffee',
      'tea',
      'soft drink',
    ],
    [
      'water',
      'soda',
      'juice',
      'coffee',
      'tea',
      'pop',
      'cola',
      'coke',
      'pepsi',
      'sprite',
      'lemonade',
      'sparkling water',
      'energy drink',
      'red bull',
      'gatorade',
      'kombucha',
      'seltzer',
    ],
  ),
  AisleFoodGroup(
    'wine and beer',
    ['wine', 'beer', 'alcohol', 'liquor'],
    ['wine', 'white wine', 'red wine', 'beer', 'vodka', 'whiskey', 'rum'],
  ),
  AisleFoodGroup(
    'snacks',
    ['snack', 'chip', 'candy', 'cookie', 'cracker'],
    [
      'chip',
      'tortilla chip',
      'crisp',
      'cracker',
      'graham cracker',
      'cookie',
      'candy',
      'chocolate',
      'milk chocolate',
      'chocolate bar',
      'popcorn',
      'pretzel',
      'nut',
      'granola bar',
      'trail mix',
      'gum',
      'peanut',
      'almond',
      'cashew',
      'marshmallow',
    ],
  ),
  AisleFoodGroup(
    'breakfast',
    ['cereal', 'breakfast'],
    [
      'cereal',
      'oatmeal',
      'oat',
      'granola',
      'pancake mix',
      'pancake',
      'syrup',
      'maple syrup',
      'pop tart',
    ],
  ),
  AisleFoodGroup(
    'pasta and rice',
    ['pasta', 'rice', 'grain', 'noodle'],
    [
      'pasta',
      'spaghetti',
      'macaroni',
      'noodle',
      'rice',
      'quinoa',
      'couscous',
      'lasagna',
      'penne',
      'ramen',
      'pasta sauce',
      'marinara',
      'pizza sauce',
      'tomato sauce',
      'tomato paste',
    ],
  ),
  AisleFoodGroup(
    'canned goods',
    ['canned', 'canned goods', 'soup'],
    [
      'soup',
      'tomato soup',
      'broth',
      'chicken broth',
      'stock',
      'bean',
      'canned',
      'chili',
      'tuna',
      'crushed tomato',
      'diced tomato',
      'tomato paste',
      'tomato sauce',
    ],
  ),
  AisleFoodGroup(
    'baking and spices',
    ['baking', 'spice', 'seasoning', 'flour', 'sugar'],
    [
      'flour',
      'sugar',
      'brown sugar',
      'baking soda',
      'baking powder',
      'yeast',
      'vanilla',
      'vanilla extract',
      'extract',
      'salt',
      'pepper',
      'black pepper',
      'pepper flake',
      'red pepper flake',
      'cinnamon',
      'spice',
      'oregano',
      'paprika',
      'cumin',
      'thyme',
      'sesame seed',
      'seed',
      'chocolate chip',
      'cake mix',
      'brownie mix',
      'breadcrumb',
      'panko',
      'marshmallow',
      'candle',
    ],
  ),
  AisleFoodGroup(
    'condiments',
    ['condiment', 'sauce', 'oil', 'dressing', 'peanut butter', 'spread'],
    [
      'ketchup',
      'mustard',
      'mayo',
      'mayonnaise',
      'relish',
      'pickle',
      'dressing',
      'oil',
      'olive oil',
      'vegetable oil',
      'cooking oil',
      'vinegar',
      'soy sauce',
      'hot sauce',
      'bbq sauce',
      'sauce',
      'salsa',
      'honey',
      'jam',
      'jelly',
      'peanut butter',
      'nut butter',
    ],
  ),
  AisleFoodGroup(
    'household',
    ['household', 'cleaning', 'paper', 'laundry'],
    [
      'paper towel',
      'toilet paper',
      'tissue',
      'napkin',
      'paper plate',
      'plastic utensil',
      'utensil',
      'cup',
      'detergent',
      'dish soap',
      'sponge',
      'trash bag',
      'foil',
      'plastic wrap',
      'bleach',
      'cleaner',
    ],
  ),
  AisleFoodGroup(
    'party supplies',
    ['party', 'seasonal', 'celebration'],
    [
      'balloon',
      'streamer',
      'birthday candle',
      'party',
      'banner',
      'gift bag',
      'wrapping paper',
    ],
  ),
  AisleFoodGroup(
    'health and beauty',
    ['health', 'beauty', 'personal care', 'pharmacy', 'nutrition'],
    [
      'shampoo',
      'conditioner',
      'toothpaste',
      'toothbrush',
      'deodorant',
      'lotion',
      'body wash',
      'razor',
      'vitamin',
      'medicine',
      'bandage',
      'protein powder',
    ],
  ),
  AisleFoodGroup(
    'baby',
    ['baby'],
    ['diaper', 'baby wipe', 'formula', 'baby food'],
  ),
  AisleFoodGroup(
    'pet',
    ['pet'],
    ['dog food', 'cat food', 'cat litter', 'pet food', 'dog treat'],
  ),
];

/// Lowercase words with plurals made singular ("berries" -> "berry",
/// "tomatoes" -> "tomato", "fruits" -> "fruit").
List<String> _words(String text) => [
  for (final w in text.toLowerCase().split(RegExp(r'[^a-z]+')))
    if (w.isNotEmpty) _singular(w),
];

String _singular(String w) {
  if (w.length > 4 && w.endsWith('ies')) {
    return '${w.substring(0, w.length - 3)}y';
  }
  if (w.length > 4 && w.endsWith('oes')) return w.substring(0, w.length - 2);
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
    return w.substring(0, w.length - 1);
  }
  return w;
}

/// Index just past the last place [phrase] appears in [words], or -1.
/// [ocr] allows one OCR slip per long word; typed item names match exactly
/// (else "party" would match "patty").
int _phraseEnd(List<String> words, List<String> phrase, {bool ocr = false}) {
  if (phrase.isEmpty || phrase.length > words.length) return -1;
  for (var i = words.length - phrase.length; i >= 0; i--) {
    var all = true;
    for (var j = 0; j < phrase.length; j++) {
      final same = ocr
          ? _sameWord(words[i + j], phrase[j])
          : words[i + j] == phrase[j];
      if (!same) {
        all = false;
        break;
      }
    }
    if (all) return i + phrase.length;
  }
  return -1;
}

/// OCR misses a letter now and then ("FRUlTS", "DAIRV"); allow one edit on
/// longer words only, so "pear" never matches "pea".
bool _sameWord(String a, String b) {
  if (a == b) return true;
  if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) {
    return false;
  }
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

final _frozenGroup = kAisleFoodGroups.firstWhere((g) => g.label == 'frozen');

/// Groups for one item name (no "or" lists). The last food word names the
/// item: "vegetable oil" is oil, "tomato soup" is soup, "tortilla chips" are
/// chips. A longer phrase ending there wins ("peanut butter" is a spread,
/// not dairy). "Frozen" anywhere adds the frozen aisle.
List<AisleFoodGroup> _groupsForPart(
  List<String> words, {
  bool withSignWords = false,
}) {
  var bestEnd = -1, bestLength = 0;
  final best = <AisleFoodGroup>[];
  for (final group in kAisleFoodGroups) {
    final terms = withSignWords
        ? [...group.itemWords, ...group.signWords]
        : group.itemWords;
    for (final term in terms) {
      final phrase = _words(term);
      final end = _phraseEnd(words, phrase);
      if (end < 0) continue;
      if (end > bestEnd || (end == bestEnd && phrase.length > bestLength)) {
        bestEnd = end;
        bestLength = phrase.length;
        best
          ..clear()
          ..add(group);
      } else if (end == bestEnd &&
          phrase.length == bestLength &&
          !best.contains(group)) {
        best.add(group);
      }
    }
  }
  if (words.contains('frozen') && !best.contains(_frozenGroup)) {
    best.add(_frozenGroup);
  }
  return best;
}

/// Groups an item belongs to, from its name and its list section. A name
/// that lists choices ("Milk or water", "Ketchup, mustard, or mayo") belongs
/// to every choice's group.
List<AisleFoodGroup> aisleGroupsForItem(String name, String category) {
  final found = <AisleFoodGroup>[];
  void addAll(Iterable<AisleFoodGroup> groups) {
    for (final g in groups) {
      if (!found.contains(g)) found.add(g);
    }
  }

  for (final part in name.split(RegExp(r',|\bor\b', caseSensitive: false))) {
    final words = _words(part);
    if (words.isNotEmpty) addAll(_groupsForPart(words));
  }
  // The list section ("Produce", "Dairy", "Ice Cream") names a group the
  // same way: "Ice Cream" is frozen, not dairy.
  final section = _words(category);
  if (section.isNotEmpty) {
    addAll(_groupsForPart(section, withSignWords: true));
  }
  return found;
}

/// Groups an aisle sign names, in the order of [kAisleFoodGroups].
List<AisleFoodGroup> aisleGroupsOnSign(String signText) {
  final words = _words(signText);
  return [
    for (final group in kAisleFoodGroups)
      if (group.signWords.any(
        (term) => _phraseEnd(words, _words(term), ocr: true) >= 0,
      ))
        group,
  ];
}

/// True when the sign names a group the item belongs to ("FRUITS" for
/// "berries", "DAIRY" for "milk").
bool aisleSignCoversItem(String signText, String name, String category) {
  final onSign = aisleGroupsOnSign(signText);
  if (onSign.isEmpty) return false;
  return aisleGroupsForItem(name, category).any(onSign.contains);
}
