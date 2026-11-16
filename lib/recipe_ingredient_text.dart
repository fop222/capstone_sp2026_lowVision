/// Turns a recipe site's ingredient line ("450 g / 1 lb pork mince (ground
/// pork)") into an amount and a clean name ("pork mince").
library;

const String _kNumber = r'[\d\.\/\s¼½¾⅓⅔⅛⅜⅝⅞]+';
const String _kUnits =
    r'cup|cups|tablespoon|tablespoons|tbsp|teaspoon|teaspoons|tsp|'
    r'oz|ounce|ounces|pound|pounds|lb|lbs|gram|grams|g|kg|ml|'
    r'liter|liters|l|can|cans|bunch|bunches|clove|cloves|'
    r'slice|slices|piece|pieces|package|packages|pkg|'
    r'bag|bags|box|boxes|stick|sticks|bar|bars|'
    r'sprig|sprigs|sheet|sheets|strip|strips|'
    r'to taste|as needed|pinch';

final _amountWithUnit = RegExp(
  '^($_kNumber(?:$_kUnits)\\b)\\s*(.*)',
  caseSensitive: false,
);
final _amountOnly = RegExp(r'^([\d\.\/\s¼½¾⅓⅔⅛⅜⅝⅞]+)\s+(.+)');

/// The second unit many sites add ("/ 1 lb", "/ 5 oz") right after the first.
final _otherUnit = RegExp(
  '^/\\s*($_kNumber(?:$_kUnits)\\b)\\s*(.*)',
  caseSensitive: false,
);

/// Splits "450 g / 1 lb pork mince" into ("450 g / 1 lb", "pork mince").
(String, String) splitIngredientQuantity(String text) {
  final t = text.trim();
  final m = _amountWithUnit.firstMatch(t);
  if (m != null) {
    var amount = m.group(1)!.trim();
    var rest = m.group(2)!.trim();
    final other = _otherUnit.firstMatch(rest);
    if (other != null) {
      amount = '$amount / ${other.group(1)!.trim()}';
      rest = other.group(2)!.trim();
    }
    return (amount, rest);
  }
  final nm = _amountOnly.firstMatch(t);
  if (nm != null) return (nm.group(1)!.trim(), nm.group(2)!.trim());
  return ('', t);
}

/// The ingredient's name without notes in brackets, prep after a comma, or
/// stray brackets and slashes: "cooking oil (vegetable (or canola))" ->
/// "cooking oil", "/ 1 lb pork mince" -> "pork mince", ")" -> "".
String cleanIngredientName(String raw) {
  // Drop everything inside (), [] and {}, nested or not, and any bracket
  // left without a partner.
  final out = StringBuffer();
  var depth = 0;
  for (final ch in raw.split('')) {
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      if (depth > 0) depth--;
    } else if (depth == 0) {
      out.write(ch);
    }
  }
  var s = out.toString();

  final comma = s.indexOf(',');
  if (comma >= 0) s = s.substring(0, comma);

  // A second unit left at the start ("/ 1 lb pork mince").
  s = s.replaceFirst(
    RegExp('^\\s*/\\s*$_kNumber(?:(?:$_kUnits)\\b)?', caseSensitive: false),
    '',
  );
  // "salt/pepper" reads as "salt or pepper"; any other slash goes.
  s = s.replaceAllMapped(
    RegExp(r'([A-Za-z])\s*/\s*([A-Za-z])'),
    (m) => '${m[1]} or ${m[2]}',
  );
  s = s.replaceAll('/', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Leftover punctuation at either end ("- onion", "garlic .").
  s = s.replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9.]+$'), '').trim();
  return RegExp('[A-Za-z]').hasMatch(s) ? s : '';
}
