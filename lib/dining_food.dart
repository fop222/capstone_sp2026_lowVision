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
const int kDiningMaxTokens = 1024;

const String kLumioCouldNotConfirm =
    'Lumio could not confidently confirm this information. Please ask dining staff for verification.';

const String kPleaseConfirmWithStaff = 'Please confirm with dining staff.';

const String kPleaseAskStaffAllergens =
    'Please ask dining staff if you need allergen confirmation.';

const String kVisualAllergenSafety =
    'Ingredients and allergens could not be confirmed visually. Please ask dining staff before eating if you have dietary restrictions or allergies.';

/// Prompt for one buffet, station, plate, tray, or mixed dining photo.
///
/// Tuned against Qwen3-VL-2B on buffet lines, close-up pans, and plates.
/// Asking for a count first and a compact object per food keeps the small
/// model from looping; generic names like "salad" are banned because it
/// otherwise uses them for every dish.
const String kDiningVlmPrompt = '''
Look at this dining photo. It may show a buffet line, serving pans, a plate, a tray, or a fountain drink station.
Count only clearly visible, prominent foods and readable drink options. Describe each one exactly once, left to right. Include dispenser labels even when no drink is visible in a cup. Ignore empty containers, utensils, decorations, tiny toppings, and distant or obscured foods.

Read each nearby dish or drink label carefully. Use a readable label's exact dish name (for example Marinara), rather than a generic guess. Recheck letters affected by glare; do not complete unreadable words or autocorrect a brand or dish from memory. Without a readable label, use a short visual estimate such as red sauce. Do not invent exact ingredients, flavors, seasonings, or hidden fillings. Prefer a broad supported name over a specific guess.

Return ONLY compact JSON on one line, no other text:
{"count":0,"foods":[{"item_id":"1","dish_name":"...","location":"...","sign_text":"","information_source":"visual estimate","confidence":"medium","identification_confidence":0.9,"clearly_visible":true}]}

Rules:
- foods has exactly "count" objects, one per pan, bowl, or portion, then the JSON ends.
- No two objects have the same dish_name.
- item_id identifies one physical serving container or drink option. Do not list both cupcakes and vanilla cupcakes for the same tray. Keep distinct varieties separate.
- identification_confidence is a number from 0 to 1 for the name you give. Only name an item if it is clearly visible and this score is at least 0.85. This is your estimate, not a measured probability. Omit uncertain items; the user can take a closer photo.
- location describes distance from the viewer, never image coordinates. When perspective clearly shows depth, use: closest to you on your left, closest to you, closest to you on your right, farther from you on your left, farther from you, farther from you on your right, furthest from you on your left, furthest from you, or furthest from you on your right.
- For one row of pans or dispensers, or whenever depth is unclear, use: to your left, in front of you, or to your right. Never infer distance just from an item's vertical position in the image. Do not use top, bottom, center, or middle-right. Return location "" if uncertain.
- Prioritize prominent items that the user can clearly distinguish. Skip insignificant objects and distant foods too small to identify. Several items can share a location.
- sign_text is only text you can actually read on a sign or label in the photo; otherwise "".
- information_source is "sign" with confidence "high" only when you read the dish name on a sign; then add "allergens" and "dietary_preferences" lists with only the words on the sign.
- dish_name contains only the dish name, never dietary tags or allergen declarations. Put Vegetarian/Veg, Vegan, Pescatarian, Gluten-Free/GF, Dairy-Free, Keto, Low-Carb, Low-Sodium, Halal, and Kosher in dietary_preferences. Put explicitly printed allergen declarations in allergens. If the sign does not state allergens, return an empty allergens list; do not infer allergens from the dish name or appearance.
- Otherwise information_source is "visual estimate" with confidence "medium" or "low". Do not invent exact ingredients.
- Use "Unidentified food" only when a food cannot be described at all.''';

const List<String> kDiningLocations = [
  'closest to you on your left',
  'closest to you',
  'closest to you on your right',
  'farther from you on your left',
  'farther from you',
  'farther from you on your right',
  'furthest from you on your left',
  'furthest from you',
  'furthest from you on your right',
  'to your left',
  'in front of you',
  'to your right',
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
    // Nothing was identified, so a stack of "could not confirm" paragraphs
    // adds no information. One staff redirect is enough.
    if (informationSource == DiningInfoSource.unknown) {
      return const [kLumioCouldNotConfirm];
    }
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
DiningParseResult parseDiningResponse(
  String raw, {
  bool requireEvidence = false,
}) {
  final entries = _entriesFromRaw(raw);
  if (entries == null) {
    return const DiningParseResult(foods: [], error: kDiningParseError);
  }
  return _resultFromEntries(entries, requireEvidence: requireEvidence);
}

/// Left, center, and right strips of one photo, as sent by the scan screen
/// when the full photo looped. Keep explicit relative depth, with horizontal
/// direction from the crop. Pixel rows never establish physical distance.
DiningParseResult parseDiningStrips(
  List<({String column, String raw})> strips, {
  bool requireEvidence = false,
}) {
  final entries = <Map<String, dynamic>>[];
  for (final strip in strips) {
    for (final entry in _entriesFromRaw(strip.raw) ?? const []) {
      final location = normalizeDiningLocation(_stringValue(entry['location']));
      final depth = RegExp(
        r'^(closest to you|farther from you|furthest from you)',
      ).firstMatch(location)?.group(0);
      final direction = strip.column == 'center'
          ? 'in front of you'
          : 'to your ${strip.column}';
      entries.add({
        ...entry,
        if (entry['item_id'] != null)
          'item_id': '${strip.column}:${entry['item_id']}',
        'location': depth == null
            ? direction
            : strip.column == 'center'
            ? depth
            : '$depth on your ${strip.column}',
      });
    }
  }
  return _resultFromEntries(entries, requireEvidence: requireEvidence);
}

/// True when the model counted several foods but named only a few, i.e. it
/// repeated one entry instead of describing each pan. A closer look at
/// smaller parts of the photo usually breaks the loop.
bool diningAnswerLooped(String raw) {
  final entries = _entriesFromRaw(raw) ?? const [];
  final counted =
      int.tryParse(
        RegExp(r'"count"\s*:\s*(\d+)').firstMatch(raw)?.group(1) ?? '',
      ) ??
      0;
  final written = counted > entries.length ? counted : entries.length;
  final names = entries
      .map((e) => _stringValue(e['dish_name']).toLowerCase().trim())
      .where((n) => n.isNotEmpty)
      .toSet();
  return written >= 4 && names.length * 2 < written;
}

/// Longer relative locations must not silently truncate a multi-item scan.
bool diningAnswerIncomplete(String raw) {
  final count = int.tryParse(
    RegExp(r'"count"\s*:\s*(\d+)').firstMatch(raw)?.group(1) ?? '',
  );
  return count != null && count > (_entriesFromRaw(raw)?.length ?? 0);
}

List<Map<String, dynamic>>? _entriesFromRaw(String raw) {
  final extracted = _extractJsonObject(raw);
  if (extracted == null) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(extracted);
  } catch (_) {
    // A token limit can cut the answer off mid-food. Keep the foods that
    // finished instead of failing the whole scan.
    decoded = _completeFoodObjects(raw);
    if (decoded == null) return null;
  }
  return _foodEntries(decoded);
}

DiningParseResult _resultFromEntries(
  List<Map<String, dynamic>> entries, {
  bool requireEvidence = false,
}) {
  final cleaned = _withoutFakeSigns(entries);

  // The small VLM often loops, repeating one food until the token limit.
  // A repeated name is far more likely a loop than a second pan, so keep
  // only the first of each.
  final foods = <DiningFood>[];
  final seenNames = <String>{};
  final seenIds = <String, int>{};
  for (final entry in cleaned) {
    final score = num.tryParse('${entry['identification_confidence']}');
    if (entry['clearly_visible'] == false ||
        (score != null && (!score.isFinite || score < 0.85 || score > 1)) ||
        (requireEvidence &&
            (score == null || entry['clearly_visible'] != true))) {
      continue;
    }
    final food = _foodFromMap(entry);
    if (food == null) continue;
    final id = _stringValue(entry['item_id']).trim();
    final existing = id.isEmpty ? null : seenIds[id];
    if (existing != null) {
      // A readable label is preferable to a generic estimate of the same tray.
      if (food.informationSource == DiningInfoSource.sign &&
          foods[existing].informationSource != DiningInfoSource.sign) {
        foods[existing] = food;
      }
      continue;
    }
    if (seenNames.add(_signKey(food.dishName))) {
      if (id.isNotEmpty) seenIds[id] = foods.length;
      foods.add(food);
    }
  }

  final sorted = sortDiningFoods(foods);
  if (sorted.isEmpty) {
    return const DiningParseResult(foods: [], error: kDiningParseError);
  }
  return DiningParseResult(foods: sorted);
}

/// Clears sign_text the model did not actually read off a dish label:
/// - the same text on two or more different foods is a section or station
///   sign ("SALAD BAR", "Ask staff about allergens"), not a dish label;
/// - on a visual estimate, sign text that just repeats the dish name is the
///   model echoing its own guess ("pepper" / sign "pepper").
List<Map<String, dynamic>> _withoutFakeSigns(
  List<Map<String, dynamic>> entries,
) {
  final dishesPerSign = <String, Set<String>>{};
  for (final entry in entries) {
    final sign = _signKey(_stringValue(entry['sign_text']));
    if (sign.isEmpty) continue;
    dishesPerSign
        .putIfAbsent(sign, () => <String>{})
        .add(_signKey(_stringValue(entry['dish_name'])));
  }

  return [
    for (final entry in entries)
      if (_isFakeSign(entry, dishesPerSign))
        {...entry, 'sign_text': ''}
      else
        entry,
  ];
}

bool _isFakeSign(
  Map<String, dynamic> entry,
  Map<String, Set<String>> dishesPerSign,
) {
  final sign = _signKey(_stringValue(entry['sign_text']));
  if (sign.isEmpty) return false;
  if ((dishesPerSign[sign]?.length ?? 0) > 1) return true;

  final claimsSign = _stringValue(
    entry['information_source'],
  ).toLowerCase().contains('sign');
  if (claimsSign) return false;
  final dish = _signKey(_stringValue(entry['dish_name']));
  return dish.isNotEmpty && (dish.contains(sign) || sign.contains(dish));
}

/// Lowercase letters and digits only, with a plural "s" dropped, so
/// "Buns" and "bun" compare equal.
String _signKey(String text) {
  final key = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9À-￿]'), '');
  return key.endsWith('s') ? key.substring(0, key.length - 1) : key;
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
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

String normalizeDiningLocation(String raw) {
  var text = raw.toLowerCase().trim();
  text = text.replaceAll(RegExp(r'[_/]+'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  text = text.replaceAll('-', ' ');
  text = text
      .replaceAll('farthest', 'furthest')
      .replaceAll('nearest', 'closest');
  if (kDiningLocations.contains(text)) return text;
  // Legacy frame coordinates give horizontal direction, not physical depth.
  // Restrict this fallback to known coordinates, never arbitrary prose.
  if (RegExp(
    r'^(?:(?:top|upper|middle|mid|bottom|lower|center|centre) )?left$',
  ).hasMatch(text)) {
    return 'to your left';
  }
  if (RegExp(
    r'^(?:(?:top|upper|middle|mid|bottom|lower|center|centre) )?right$',
  ).hasMatch(text)) {
    return 'to your right';
  }
  if (RegExp(
    r'^(?:(?:top|upper|middle|bottom|lower|center|centre) )?(?:center|centre|middle)$',
  ).hasMatch(text)) {
    return 'in front of you';
  }
  return '';
}

/// Spoken description for the app's existing text-to-speech helper.
String spokenDiningFood(DiningFood food) {
  final buffer = StringBuffer()
    ..write(food.dishName)
    ..write(food.location.isEmpty ? '.' : ' is located ${food.location}.');

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
      ' Allergen information on the sign: ${_joinAnd(confirmedAllergens)}.',
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

  buffer.write(' $kPleaseConfirmWithStaff');
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Name and location only, for the results list. Details are spoken on the
/// food's own screen.
String spokenDiningFoodBrief(DiningFood food) {
  if (food.location.isEmpty) return '${food.dishName}.';
  return '${food.dishName}, ${food.location}.';
}

String spokenDiningFoods(List<DiningFood> foods) {
  if (foods.isEmpty) {
    return 'No foods were identified. Please try another photo or ask dining staff.';
  }
  final count = foods.length == 1 ? '1 food' : '${foods.length} foods';
  final parts = <String>['Lumio found $count.'];
  for (var i = 0; i < foods.length; i++) {
    parts.add('Food ${i + 1}. ${spokenDiningFoodBrief(foods[i])}');
  }
  parts.add('Tap a food for allergens and dietary details.');
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

/// Returns every fully closed `{...}` object inside the first JSON array of
/// [raw], or null if none closed. Used when the answer was truncated.
List<Object?>? _completeFoodObjects(String raw) {
  final arrayStart = raw.indexOf('[');
  if (arrayStart < 0) return null;
  final foods = <Object?>[];
  var depth = 0;
  var objectStart = -1;
  var inString = false;
  var escaped = false;
  for (var i = arrayStart + 1; i < raw.length; i++) {
    final c = raw[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{') {
      if (depth == 0) objectStart = i;
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0 && objectStart >= 0) {
        try {
          foods.add(jsonDecode(raw.substring(objectStart, i + 1)));
        } catch (_) {}
        objectStart = -1;
      }
    } else if (c == ']' && depth == 0) {
      break;
    }
  }
  return foods.isEmpty ? null : foods;
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

/// The model labels a food it could not name with one of these, sometimes
/// while still claiming a visual estimate.
final _unidentifiedName = RegExp(
  r'^(unidentified|unknown|unrecognized|unclear)\s+(food|dish|item)$',
  caseSensitive: false,
);

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
  if (_unidentifiedName.hasMatch(dish)) {
    dish = 'Unidentified food';
    source = DiningInfoSource.unknown;
    warning = '';
  }
  if (source == DiningInfoSource.sign && signText.isEmpty) {
    source = DiningInfoSource.visualEstimate;
    warning = _append(warning, 'No readable sign text was returned.');
  }

  if (source == DiningInfoSource.sign && !signPartial) {
    final signedName = _dishNameFromSign(signText);
    if (signedName != null) dish = signedName;
  }
  dish = _cleanDishTitle(dish);
  if (dish.isEmpty) return null;

  var confidence = _confidenceValue(_stringValue(map['confidence']));
  if (source != DiningInfoSource.sign && confidence == 'high') {
    confidence = 'medium';
  }
  if (source == DiningInfoSource.unknown) confidence = 'low';
  if (signPartial && confidence == 'high') confidence = 'medium';

  final dietaryValues = _stringList(map['dietary_preferences']);
  dietaryValues.addAll(
    _dietaryAliases.keys.where(
      (label) => _signSupportsDietary(_stringValue(map['dish_name']), label),
    ),
  );
  final allergenValues = _stringList(map['allergens']);
  if (source == DiningInfoSource.sign && !signPartial) {
    dietaryValues.addAll(
      _dietaryAliases.keys.where(
        (label) => _signSupportsDietary(signText, label),
      ),
    );
    allergenValues.addAll(
      _allergenAliases.keys.where(
        (label) => _signSupportsAllergen(signText, label),
      ),
    );
  }
  for (final value in dietaryValues) {
    if (_canonicalDietary(value) == null && _canonicalAllergen(value) != null) {
      allergenValues.add(value);
    }
  }
  final allergens = _allergenClaims(
    values: allergenValues,
    signText: signPartial ? '' : signText,
    source: source,
  );
  final dietary = _dietaryClaims(
    values: dietaryValues,
    signText: signPartial ? '' : signText,
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
  if (kDiningLocations.contains(normalized) ||
      normalized == 'left' ||
      normalized == 'right') {
    return normalized;
  }
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
  final name = _cleanDishTitle(signText);
  return name.isEmpty || _isLabelOnly(name) ? null : name;
}

bool _isLabelOnly(String text) {
  return _cleanDishTitle(text).isEmpty;
}

const Map<String, List<String>> _allergenAliases = {
  'Dairy': ['dairy', 'milk'],
  'Wheat': ['wheat', 'gluten'],
  'Peanuts': ['peanut', 'peanuts'],
  'Tree Nuts': [
    'tree nut',
    'tree nuts',
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
  'Mustard': ['mustard'],
};

const Map<String, List<String>> _dietaryAliases = {
  'Vegetarian': ['vegetarian', 'veg'],
  'Vegan': ['vegan'],
  'Gluten-Free': ['gluten-free', 'gluten free', 'glutenfree', 'gf'],
  'Dairy-Free': ['dairy-free', 'dairy free'],
  'Keto': ['keto', 'ketogenic'],
  'Low-Carb': ['low-carb', 'low carb', 'low carbohydrate'],
  'Low-Sodium': ['low-sodium', 'low sodium'],
  'Halal': ['halal'],
  'Kosher': ['kosher'],
  'Pescatarian': ['pescatarian'],
};

final _allergenDeclaration = RegExp(
  r'\b(?:(?:may\s+)?contains?|allergens?\s*:?)\s*:?\s*([^\n;|]+)',
  caseSensitive: false,
);

RegExp _aliasPattern(Iterable<String> aliases) {
  final sorted = aliases.toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return RegExp(
    '\\b(?:${sorted.map(RegExp.escape).join('|')})\\b',
    caseSensitive: false,
  );
}

bool _isAllergenList(String text) {
  var remainder = text.replaceAll(
    _aliasPattern(_allergenAliases.values.expand((aliases) => aliases)),
    '',
  );
  if (remainder == text) return false;
  remainder = remainder.replaceAll(
    RegExp(r'\band\b', caseSensitive: false),
    '',
  );
  return remainder.replaceAll(RegExp(r'[\s,;/()\[\]&.:\-]+'), '').isEmpty;
}

/// Separate metadata without deleting ingredient names such as Fish Tacos or
/// Milk Chocolate. Bare allergens are metadata only in a separate segment.
String _cleanDishTitle(String text) {
  var title = text.replaceAllMapped(RegExp(r'\(([^)]*)\)|\[([^\]]*)\]'), (m) {
    final inner = m.group(1) ?? m.group(2) ?? '';
    final withoutDiet = inner.replaceAll(
      _aliasPattern(_dietaryAliases.values.expand((aliases) => aliases)),
      '',
    );
    return _isAllergenList(inner) ||
            _allergenDeclaration.hasMatch(inner) ||
            withoutDiet.replaceAll(RegExp(r'[\s,/;&]+'), '').isEmpty
        ? ''
        : m.group(0)!;
  });
  title = title.replaceAll(_allergenDeclaration, '');
  title = title.replaceAll(
    _aliasPattern(_dietaryAliases.values.expand((aliases) => aliases)),
    '',
  );
  final parts = title.split(RegExp(r'\r?\n|\s+[–—-]\s+|[|;]'));
  return parts
      .where((part) => parts.length == 1 || !_isAllergenList(part.trim()))
      .join(' ')
      .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), '')
      .replaceAll(RegExp(r'^[\s,/:;|–—-]+|[\s,/:;|–—-]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> _allergenDeclarations(String text) {
  final declarations = _allergenDeclaration
      .allMatches(text)
      .map((m) => m.group(0)!)
      .toList();
  for (final m in RegExp(r'\(([^)]*)\)|\[([^\]]*)\]').allMatches(text)) {
    final inner = m.group(1) ?? m.group(2) ?? '';
    if (_isAllergenList(inner)) declarations.add(inner);
  }
  final parts = text.split(RegExp(r'\r?\n|\s+[–—-]\s+|[|;]'));
  if (parts.length > 1) {
    declarations.addAll(parts.where((part) => _isAllergenList(part.trim())));
  }
  return declarations;
}

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
    if (!confirmed) continue;
    final aliases = _allergenAliases[canonical]!;
    final mayContain = _allergenDeclarations(signText).any(
      (declaration) =>
          RegExp(
            r'\bmay\s+contain',
            caseSensitive: false,
          ).hasMatch(declaration) &&
          _aliasPattern(aliases).hasMatch(declaration),
    );
    claims.add(
      DiningClaim(
        label: mayContain ? 'May contain $canonical' : canonical,
        certainty: DiningCertainty.confirmed,
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
  return null;
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
    if (_aliasPattern(entry.value).hasMatch(lower)) return entry.key;
  }
  return null;
}

bool _signSupportsAllergen(String signText, String canonical) {
  if (_signNegatesAllergen(signText, canonical)) return false;
  final aliases = _allergenAliases[canonical] ?? [canonical.toLowerCase()];
  return _allergenDeclarations(signText).any(
    (declaration) => aliases.any(
      (alias) =>
          _containsWord(declaration.toLowerCase(), alias) &&
          !_signNegatesAlias(declaration.toLowerCase(), alias),
    ),
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
  return aliases.any(
    (alias) =>
        _aliasPattern([alias]).hasMatch(lower) &&
        !RegExp(
          '\\b(?:not|non|no)[\\s-]+${RegExp.escape(alias)}\\b',
        ).hasMatch(lower),
  );
}

bool _containsWord(String text, String word) {
  return RegExp('\\b${RegExp.escape(word)}s?\\b').hasMatch(text);
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
