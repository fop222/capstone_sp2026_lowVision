/// Canonicalizes general food names before pantry-list comparison.
String normalizePantryFoodName(String value) {
  var normalized = value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  const packagingWords = {
    'bag', 'bags', 'box', 'boxes', 'bottle', 'bottles', 'carton', 'cartons',
    'container', 'containers', 'package', 'packages', 'pack', 'packs',
    'plastic', 'pouch', 'pouches', 'wrapper', 'wrappers',
  };
  normalized = normalized
      .split(' ')
      .where((word) => !packagingWords.contains(word))
      .join(' ');

  normalized = normalized
      .replaceAll(RegExp(r'\bbell peppers?\b'), 'pepper')
      .replaceAll(RegExp(r'\bbok choy\b'), 'bok choy')
      .replaceAll(RegExp(r'\bpak choi\b'), 'bok choy')
      .replaceAll(RegExp(r'\bromaine lettuce\b'), 'lettuce')
      .replaceAll(RegExp(r'\bcelery stalks?\b'), 'celery');

  normalized = normalized
      .split(' ')
      .map((word) {
        if (word == 'potatoes') return 'potato';
        if (word.endsWith('ies') && word.length > 3) {
          return '${word.substring(0, word.length - 3)}y';
        }
        if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
          return word.substring(0, word.length - 1);
        }
        return word;
      })
      .join(' ')
      .trim();

  return normalized;
}

/// Returns a match only when exactly one list name has the same canonical name.
List<String> matchPantryFoodName(String detected, Iterable<String> listNames) {
  final normalizedDetected = normalizePantryFoodName(detected);
  final matches = listNames
      .where((name) => normalizePantryFoodName(name) == normalizedDetected)
      .toSet()
      .toList();
  return matches.length == 1 ? matches : const [];
}