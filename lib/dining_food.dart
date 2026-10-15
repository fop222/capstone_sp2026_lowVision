/// Dining / buffet scan model, VLM prompt, and response validation.
///
/// One photo can describe many foods. Sign text is the authority for a dish
/// name, allergens, and dietary labels. Appearance-only details stay estimated
/// or unknown and always direct the user to dining staff.
library;

import 'dart:convert';

/// Sent with `/predict` so the Flask pipeline can allow a longer answer.
const String kDiningVlmTask = 'dining';

/// Multi-food JSON does not fit the server's short default token limit.
const int kDiningMaxTokens = 768;

const String kLumioCouldNotConfirm =
    'Lumio could not confidently confirm this information. Please ask dining staff for verification.';

const String kPleaseConfirmWithStaff = 'Please confirm with dining staff.';

const String kPleaseAskStaffAllergens =
    'Please ask dining staff if you need allergen confirmation.';

const String kVisualAllergenSafety =
    'Ingredients and allergens could not be confirmed visually. Please ask dining staff before eating if you have dietary restrictions or allergies.';

/// Prompt for one buffet, station, plate, tray, or mixed dining photo.
const String kDiningVlmPrompt = '''
You scan one dining photo for the low-vision app Lumio. The photo may show a long buffet line, serving pans, a dining hall station, a counter, a plate, a tray, bowls, or a crowded mix of those. Layouts vary. Use relative position only. Do not assume a fixed number of rows or columns.

Return ONLY valid JSON, no markdown and no extra text:
{"foods":[{"dish_name":"","location":"","confidence":"high","sign_text":"","allergens":[],"dietary_preferences":[],"information_source":"sign","warning":""}]}

Include every distinct food as its own object. Do not stop after the first food. Keep similar-looking foods separate when they are in different places.

location must be exactly one of: top left, top center, top right, middle left, middle center, middle right, bottom left, bottom center, bottom right.

Read a nearby sign or label before guessing. If a sign names the food, set dish_name from that sign, copy the readable sign into sign_text, set information_source to "sign", and copy only allergens and dietary words written on the sign. Sign examples: Vegetarian, Vegan, Gluten-Free, Contains Dairy, Contains Nuts. Do not replace sign facts with a visual guess. If the sign is unclear or only partly readable, put the readable part in sign_text, set confidence to "low" or "medium", and say the sign is unclear in warning.

If no readable sign exists, set information_source to "visual estimate" and estimate the dish. Use confidence "medium" or "low". Do not invent exact ingredients. Dietary tags must start with "Possibly". Allergens are only possible, never confirmed. warning must say the exact dish could not be confirmed.

If you cannot tell what a food is, set dish_name to "Unidentified food", information_source to "unknown", confidence to "low", and explain that in warning.

confidence is "high" only when a readable sign clearly names the dish. Never present visual allergens or dietary labels as confirmed fact.
''';

const List<String> kDiningLocations = [
  'top left',
  'top center',
  'top right',
  'middle left',
  'middle center',
  'middle right',
  'bottom left',
  'bottom center',
  'bottom right',
];

enum DiningCertainty { confirmed, estimated, unknown }

enum DiningInfoSource { sign, visualEstimate, unknown }

class DiningClaim {
  const DiningClaim({required this.label, required this.certainty});

  final String label;
  final DiningCertainty certainty;

  String get certaintyLabel {
    switch (certainty) {
      case DiningCertainty.confirmed:
        return 'Confirmed';
      case DiningCertainty.estimated:
        return 'Estimated';
      case DiningCertainty.unknown:
        return 'Unknown';
    }
  }

  /// Text label includes the certainty word so color is never the only signal.
  String get chipLabel {
    if (certainty == DiningCertainty.estimated) {
      final softened = label.replaceFirst(
        RegExp(r'^possibly\s+', caseSensitive: false),
        '',
      );
      return 'Possible $softened · Estimated';
    }
    return '$label · $certaintyLabel';
  }
}

class DiningFood {
  const DiningFood({
    required this.dishName,
    required this.location,
    required this.confidence,
    required this.signText,
    required this.allergens,
    required this.dietaryPreferences,
    required this.informationSource,
    required this.warning,
    required this.signPartial,
  });

  final String dishName;
  final String location;
  final String confidence;
  final String signText;
  final List<DiningClaim> allergens;
  final List<DiningClaim> dietaryPreferences;
  final DiningInfoSource informationSource;
  final String warning;
  final bool signPartial;

  String get locationLabel => diningLocationLabel(location);

  String get confidenceLabel {
    switch (confidence) {
      case 'high':
        return 'High';
      case 'low':
        return 'Low';
      default:
        return 'Medium';
    }
  }

  String get sourceLabel {
    switch (informationSource) {
      case DiningInfoSource.sign:
        return signPartial ? 'Partly readable sign' : 'Read from sign';
      case DiningInfoSource.visualEstimate:
        return 'Visual estimate';
      case DiningInfoSource.unknown:
        return 'Unknown';
    }
  }

  bool get hasEstimatedOrUnknown =>
      signPartial ||
      informationSource != DiningInfoSource.sign ||
      confidence != 'high' ||
      allergens.any((claim) => claim.certainty != DiningCertainty.confirmed) ||
      dietaryPreferences.any(
        (claim) => claim.certainty != DiningCertainty.confirmed,
      );

  /// Notices shown under the facts. Estimated and unknown results always
  /// include both the Lumio uncertainty sentence and a staff redirect.
  List<String> get notices {
    final lines = <String>[];
    if (warning.trim().isNotEmpty) lines.add(warning.trim());
    if (hasEstimatedOrUnknown) {
      lines.add(kLumioCouldNotConfirm);
      lines.add(kPleaseConfirmWithStaff);
    } else {
      lines.add(kPleaseAskStaffAllergens);
    }
    return _dedupeSentences(lines);
  }
}

class DiningParseResult {
  const DiningParseResult({required this.foods, this.error});

  final List<DiningFood> foods;
  final String? error;

  bool get isValid => error == null && foods.isNotEmpty;
}

const String kDiningParseError =
    'Lumio could not read a food list from this photo. Please try another photo or ask dining staff.';

/// Parses and validates a VLM dining answer. Invalid entries are dropped.
/// Allergen and dietary claims are re-labeled before anything is shown.
DiningParseResult parseDiningResponse(String raw) {
  final extracted = _extractJsonObject(raw);
  if (extracted == null) {
    return const DiningParseResult(foods: [], error: kDiningParseError);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(extracted);
  } catch (_) {
    return const DiningParseResult(foods: [], error: kDiningParseError);
  }

  final entries = _foodEntries(decoded);
  if (entries == null) {
    return const DiningParseResult(foods: [], error: kDiningParseError);
  }

  final foods = <DiningFood>[];
  for (final entry in entries) {
    final food = _foodFromMap(entry);
    if (food != null) foods.add(food);
  }

  final sorted = sortDiningFoods(foods);
  if (sorted.isEmpty) {
    return const DiningParseResult(foods: [], error: kDiningParseError);
  }
  return DiningParseResult(foods: sorted);
}

List<DiningFood> sortDiningFoods(List<DiningFood> foods) {
  final indexed = foods.asMap().entries.toList()
    ..sort((a, b) {
      final byLocation = diningLocationSortIndex(
        a.value.location,
      ).compareTo(diningLocationSortIndex(b.value.location));
      if (byLocation != 0) return byLocation;
      return a.key.compareTo(b.key);
    });
  return indexed.map((entry) => entry.value).toList(growable: false);
}

int diningLocationSortIndex(String location) {
  final normalized = normalizeDiningLocation(location);
  final index = kDiningLocations.indexOf(normalized);
  return index < 0 ? kDiningLocations.length : index;
}

String diningLocationLabel(String location) {
  final normalized = normalizeDiningLocation(location);
  if (normalized.isEmpty) return 'Location unknown';
  return normalized
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String normalizeDiningLocation(String raw) {
  var text = raw.toLowerCase().trim();
  text = text.replaceAll(RegExp(r'[_/]+'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  text = text.replaceAll('-', ' ');
  const aliases = {
    'upper left': 'top left',
    'upper center': 'top center',
    'upper centre': 'top center',
    'upper middle': 'top center',
    'upper right': 'top right',
    'top centre': 'top center',
    'top middle': 'top center',
    'top': 'top center',
    'mid left': 'middle left',
    'center left': 'middle left',
    'centre left': 'middle left',
    'middle centre': 'middle center',
    'center center': 'middle center',
    'centre centre': 'middle center',
    'center': 'middle center',
    'centre': 'middle center',
    'middle': 'middle center',
    'mid right': 'middle right',
    'center right': 'middle right',
    'centre right': 'middle right',
    'lower left': 'bottom left',
    'lower center': 'bottom center',
    'lower centre': 'bottom center',
    'lower right': 'bottom right',
    'bottom centre': 'bottom center',
    'bottom middle': 'bottom center',
    'bottom': 'bottom center',
  };
  return aliases[text] ?? text;
}

/// Spoken description for the app's existing text-to-speech helper.
String spokenDiningFood(DiningFood food) {
  final buffer = StringBuffer()
    ..write(food.dishName)
    ..write(
      food.location.isEmpty ? '.' : ' is located at the ${food.location}.',
    );

  if (food.signText.isNotEmpty) {
    buffer.write(' The sign says ${food.signText}.');
  }

  if (food.confidence != 'high' ||
      food.informationSource != DiningInfoSource.sign) {
    buffer.write(' Confidence is ${food.confidence}.');
  }

  final confirmedDiet = food.dietaryPreferences
      .where((claim) => claim.certainty == DiningCertainty.confirmed)
      .map((claim) => claim.label)
      .toList();
  final estimatedDiet = food.dietaryPreferences
      .where((claim) => claim.certainty == DiningCertainty.estimated)
      .map((claim) => _spokenDiet(claim.label))
      .toList();

  if (confirmedDiet.isNotEmpty) {
    buffer.write(' The sign identifies it as ${_joinAnd(confirmedDiet)}.');
  }
  if (estimatedDiet.isNotEmpty) {
    buffer.write(' Dietary estimate: ${_joinAnd(estimatedDiet)}.');
  } else if (confirmedDiet.isEmpty) {
    buffer.write(' Dietary preference is unknown.');
  }

  final confirmedAllergens = food.allergens
      .where((claim) => claim.certainty == DiningCertainty.confirmed)
      .map((claim) => claim.label)
      .toList();
  final estimatedAllergens = food.allergens
      .where((claim) => claim.certainty == DiningCertainty.estimated)
      .map((claim) => claim.label)
      .toList();

  if (confirmedAllergens.isNotEmpty) {
    buffer.write(
      ' The sign identifies it as containing ${_joinAnd(confirmedAllergens)}.',
    );
  }
  if (estimatedAllergens.isNotEmpty) {
    if (confirmedAllergens.isNotEmpty) {
      buffer.write(' ${_joinAnd(estimatedAllergens)} may also be present.');
    } else {
      buffer.write(' Possible allergens: ${_joinAnd(estimatedAllergens)}.');
    }
  } else if (confirmedAllergens.isEmpty) {
    buffer.write(' Allergens could not be confirmed.');
  }

  for (final notice in food.notices) {
    buffer.write(' $notice');
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String spokenDiningFoods(List<DiningFood> foods) {
  if (foods.isEmpty) {
    return 'No foods were identified. Please try another photo or ask dining staff.';
  }
  final count = foods.length == 1 ? '1 food' : '${foods.length} foods';
  final parts = <String>['Lumio found $count.'];
  for (var i = 0; i < foods.length; i++) {
    parts.add('Food ${i + 1}. ${spokenDiningFood(foods[i])}');
  }
  return parts.join(' ');
}

String _spokenDiet(String label) {
  final trimmed = label.trim();
  if (RegExp(r'^possibly\s+', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }
  return 'Possibly $trimmed';
}

String _joinAnd(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  if (items.length == 2) return '${items[0]} and ${items[1]}';
  return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
}

List<String> _dedupeSentences(List<String> lines) {
  final kept = <String>[];
  for (final line in lines) {
    final text = line.trim();
    if (text.isEmpty) continue;
    final lower = text.toLowerCase();
    final already = kept.any((existing) {
      final existingLower = existing.toLowerCase();
      return existingLower == lower ||
          existingLower.contains(lower) ||
          lower.contains(existingLower);
    });
    if (!already) kept.add(text);
  }
  return kept;
}

String? _extractJsonObject(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  text = text.replaceFirst(
    RegExp(r'^```(?:json)?\s*', caseSensitive: false),
    '',
  );
  text = text.replaceFirst(RegExp(r'\s*```$'), '');
  final startObj = text.indexOf('{');
  final startList = text.indexOf('[');
  final start = _firstIndex(startObj, startList);
  if (start < 0) return null;
  final endObj = text.lastIndexOf('}');
  final endList = text.lastIndexOf(']');
  final end = endObj > endList ? endObj : endList;
  if (end <= start) return null;
  var slice = text.substring(start, end + 1);
  slice = slice.replaceAllMapped(RegExp(r',\s*([}\]])'), (match) {
    return match.group(1) ?? '';
  });
  return slice;
}

int _firstIndex(int a, int b) {
  if (a < 0) return b;
  if (b < 0) return a;
  return a < b ? a : b;
}

List<Map<String, dynamic>>? _foodEntries(Object? decoded) {
  if (decoded is List) {
    return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
  if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    final foods = map['foods'];
    if (foods is List) {
      return foods.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    if (map.containsKey('dish_name')) return [map];
  }
  return null;
}

const _junkNames = {
  'none',
  'n/a',
  'na',
  'null',
  'unknown',
  'nothing',
  'no food',
  'not found',
};

DiningFood? _foodFromMap(Map<String, dynamic> map) {
  var dish = _stringValue(map['dish_name']).trim();
  if (dish.isEmpty || _junkNames.contains(dish.toLowerCase())) return null;

  final signText = _stringValue(map['sign_text']).trim();
  var warning = _stringValue(map['warning']).trim();
  final signPartial = _signIsPartial(signText, warning);
  var source = _sourceFrom(
    _stringValue(map['information_source']),
    signText: signText,
  );
  if (source == DiningInfoSource.sign && signText.isEmpty) {
    source = DiningInfoSource.visualEstimate;
    warning = _append(warning, 'No readable sign text was returned.');
  }

  if (source == DiningInfoSource.sign && !signPartial) {
    final signedName = _dishNameFromSign(signText);
    if (signedName != null) dish = signedName;
  }

  var confidence = _confidenceValue(_stringValue(map['confidence']));
  if (source != DiningInfoSource.sign && confidence == 'high') {
    confidence = 'medium';
  }
  if (source == DiningInfoSource.unknown) confidence = 'low';
  if (signPartial && confidence == 'high') confidence = 'medium';

  final dietaryValues = _stringList(map['dietary_preferences']);
  final allergenValues = _stringList(map['allergens']);
  for (final value in dietaryValues) {
    if (_canonicalDietary(value) == null && _canonicalAllergen(value) != null) {
      allergenValues.add(value);
    }
  }
  final allergens = _allergenClaims(
    values: allergenValues,
    signText: signText,
    source: source,
  );
  final dietary = _dietaryClaims(
    values: dietaryValues,
    signText: signText,
    source: source,
  );

  if (signPartial) {
    warning = _append(warning, 'The sign was only partly readable.');
  }
  if (source == DiningInfoSource.visualEstimate) {
    if (warning.isEmpty) {
      warning =
          'This appears to be $dish, but the exact dish could not be confirmed.';
    }
    warning = _append(warning, kVisualAllergenSafety);
  } else if (source == DiningInfoSource.unknown && warning.isEmpty) {
    warning = 'Not enough information to identify this food.';
  }

  if (dish.length > 80) dish = '${dish.substring(0, 77).trim()}...';

  return DiningFood(
    dishName: dish,
    location: _knownLocation(_stringValue(map['location'])),
    confidence: confidence,
    signText: signText,
    allergens: allergens,
    dietaryPreferences: dietary,
    informationSource: source,
    warning: warning.trim(),
    signPartial: signPartial,
  );
}

String _knownLocation(String raw) {
  final normalized = normalizeDiningLocation(raw);
  if (kDiningLocations.contains(normalized)) return normalized;
  return '';
}

DiningInfoSource _sourceFrom(String raw, {required String signText}) {
  final text = raw.toLowerCase().trim();
  if (text.contains('sign') || text.contains('label') || text == 'menu') {
    return DiningInfoSource.sign;
  }
  if (text.contains('unknown') || text == 'none') {
    return signText.isEmpty ? DiningInfoSource.unknown : DiningInfoSource.sign;
  }
  if (text.contains('visual') ||
      text.contains('estimate') ||
      text.contains('guess') ||
      text.contains('appearance')) {
    return DiningInfoSource.visualEstimate;
  }
  if (signText.isNotEmpty) return DiningInfoSource.sign;
  return DiningInfoSource.visualEstimate;
}

String _confidenceValue(String raw) {
  final text = raw.toLowerCase().trim();
  if (text.contains('high') || text == 'certain') return 'high';
  if (text.contains('low') || text.contains('unsure')) return 'low';
  return 'medium';
}

bool _signIsPartial(String signText, String warning) {
  final blob = '$signText $warning'.toLowerCase();
  const hints = [
    'unclear',
    'unreadable',
    'illegible',
    'partial',
    'partly',
    'could not read',
    'hard to read',
    'not fully',
  ];
  if (hints.any(blob.contains)) return true;
  return signText.contains('...') || signText.contains('…');
}

String? _dishNameFromSign(String signText) {
  final parts = signText.split(RegExp(r'\s+[-–—|]\s+'));
  if (parts.isEmpty) return null;
  final first = parts.first.trim();
  if (first.length < 3 || _isLabelOnly(first)) return null;
  return first;
}

bool _isLabelOnly(String text) {
  final lower = text.toLowerCase().trim();
  const labels = {
    'vegetarian',
    'vegan',
    'gluten-free',
    'gluten free',
    'halal',
    'kosher',
    'pescatarian',
  };
  return labels.contains(lower) || lower.startsWith('contains ');
}

const Map<String, List<String>> _allergenAliases = {
  'Dairy': ['dairy', 'milk', 'cheese', 'lactose', 'butter', 'cream', 'whey'],
  'Wheat': ['wheat', 'gluten'],
  'Nuts': [
    'nut',
    'nuts',
    'peanut',
    'peanuts',
    'almond',
    'cashew',
    'walnut',
    'pecan',
    'pistachio',
    'hazelnut',
  ],
  'Eggs': ['egg', 'eggs'],
  'Soy': ['soy', 'soya'],
  'Fish': ['fish', 'salmon', 'tuna'],
  'Shellfish': ['shellfish', 'shrimp', 'prawn', 'crab', 'lobster'],
  'Sesame': ['sesame'],
};

const Map<String, List<String>> _dietaryAliases = {
  'Vegetarian': ['vegetarian'],
  'Vegan': ['vegan'],
  'Gluten-Free': ['gluten-free', 'gluten free', 'glutenfree'],
  'Halal': ['halal'],
  'Kosher': ['kosher'],
  'Pescatarian': ['pescatarian'],
};

List<DiningClaim> _allergenClaims({
  required List<String> values,
  required String signText,
  required DiningInfoSource source,
}) {
  final claims = <DiningClaim>[];
  final seen = <String>{};
  for (final value in values) {
    final canonical = _canonicalAllergen(value);
    if (canonical == null || !seen.add(canonical.toLowerCase())) continue;
    if (_signNegatesAllergen(signText, canonical)) continue;
    final confirmed =
        source == DiningInfoSource.sign &&
        _signSupportsAllergen(signText, canonical);
    claims.add(
      DiningClaim(
        label: canonical,
        certainty: confirmed
            ? DiningCertainty.confirmed
            : DiningCertainty.estimated,
      ),
    );
  }
  return claims;
}

List<DiningClaim> _dietaryClaims({
  required List<String> values,
  required String signText,
  required DiningInfoSource source,
}) {
  final claims = <DiningClaim>[];
  final seen = <String>{};
  for (final value in values) {
    final canonical = _canonicalDietary(value);
    if (canonical == null || !seen.add(canonical.toLowerCase())) continue;
    final confirmed =
        source == DiningInfoSource.sign &&
        _signSupportsDietary(signText, canonical);
    final label = confirmed ? canonical : 'Possibly $canonical';
    claims.add(
      DiningClaim(
        label: label,
        certainty: confirmed
            ? DiningCertainty.confirmed
            : DiningCertainty.estimated,
      ),
    );
  }
  return claims;
}

String? _canonicalAllergen(String raw) {
  final cleaned = raw
      .replaceAll(
        RegExp(r'\b(confirmed|definitely|certainly|possible|possibly)\b'),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty || cleaned.length > 40) return null;
  final lower = cleaned.toLowerCase();
  for (final entry in _allergenAliases.entries) {
    if (entry.value.any((alias) => _containsWord(lower, alias))) {
      return entry.key;
    }
  }
  if (_containsWord(lower, 'allergen')) return null;
  return _titleCase(cleaned);
}

String? _canonicalDietary(String raw) {
  final cleaned = raw
      .replaceAll(
        RegExp(
          r'\b(confirmed|definitely|certainly|possible|possibly|estimated)\b',
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty || cleaned.length > 40) return null;
  final lower = cleaned.toLowerCase();
  for (final entry in _dietaryAliases.entries) {
    if (entry.value.any((alias) => lower.contains(alias))) return entry.key;
  }
  return null;
}

bool _signSupportsAllergen(String signText, String canonical) {
  if (_signNegatesAllergen(signText, canonical)) return false;
  final aliases = _allergenAliases[canonical] ?? [canonical.toLowerCase()];
  final lower = signText.toLowerCase();
  return aliases.any(
    (alias) => _containsWord(lower, alias) && !_signNegatesAlias(lower, alias),
  );
}

bool _signNegatesAllergen(String signText, String canonical) {
  final aliases = _allergenAliases[canonical] ?? [canonical.toLowerCase()];
  final lower = signText.toLowerCase();
  if (canonical == 'Wheat' &&
      (lower.contains('gluten-free') ||
          lower.contains('gluten free') ||
          lower.contains('glutenfree'))) {
    return true;
  }
  return aliases.any((alias) => _signNegatesAlias(lower, alias));
}

bool _signNegatesAlias(String signLower, String alias) {
  final escaped = RegExp.escape(alias);
  final patterns = [
    RegExp('$escaped[\\s-]*free'),
    RegExp('free of $escaped'),
    RegExp('no $escaped'),
    RegExp('without $escaped'),
    RegExp('does not contain $escaped'),
  ];
  return patterns.any((pattern) => pattern.hasMatch(signLower));
}

bool _signSupportsDietary(String signText, String canonical) {
  final aliases = _dietaryAliases[canonical] ?? [canonical.toLowerCase()];
  final lower = signText.toLowerCase();
  return aliases.any(lower.contains);
}

bool _containsWord(String text, String word) {
  return RegExp('\\b${RegExp.escape(word)}s?\\b').hasMatch(text);
}

String _titleCase(String value) {
  return value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _append(String current, String addition) {
  if (current.toLowerCase().contains(addition.toLowerCase())) return current;
  if (current.trim().isEmpty) return addition;
  final spaced = current.endsWith('.') ? current : '$current.';
  return '$spaced $addition';
}

String _stringValue(Object? value) => value == null ? '' : value.toString();

List<String> _stringList(Object? value) {
  if (value is! List) {
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const [];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
