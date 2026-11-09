/// Cooking-time parsing and the spoken timer cues used in cooking mode.
///
/// A step can mention more than one time ("cook for 5–7 minutes, stirring
/// every 1–2 minutes"). The timer uses the longest one. A range runs for the
/// high end and stays quiet until the low end.
library;

final _timeMention = RegExp(
  r'\b(?:'
  r'(?<rangeLow>\d+)\s*(?:to|–|—|-)\s*(?<rangeHigh>\d+)\s*'
  r'(?<rangeUnit>hours?|hrs?|minutes?|mins?|seconds?|secs?)'
  r'|(?<hours>\d+)\s*(?:hours?|hrs?)\s*(?:and\s+)?'
  r'(?<minutes>\d+)\s*(?:minutes?|mins?)'
  r'|(?:(?:about|at\s+least|another)\s+)?(?<amount>\d+)\s*'
  r'(?:more\s+)?'
  r'(?<unit>hours?|hrs?|minutes?|mins?|seconds?|secs?)'
  r')\b',
  caseSensitive: false,
);

/// A duration found in a cooking step.
///
/// [upper] is the timer length. For a range, [lower] is when remaining-time
/// alerts begin. For a single duration, [lower] and [upper] are equal.
class StepCookTime {
  const StepCookTime({required this.lower, required this.upper});

  final Duration lower;
  final Duration upper;

  bool get isRange => lower < upper;
}

/// Longest cooking time in [step], or null when the step has no time.
StepCookTime? parseStepCookTime(String step) {
  StepCookTime? best;
  for (final match in _timeMention.allMatches(step)) {
    final parsed = _timeFromMatch(match);
    if (parsed == null || parsed.upper <= Duration.zero) continue;
    if (best == null || parsed.upper > best.upper) best = parsed;
  }
  return best;
}

StepCookTime? _timeFromMatch(RegExpMatch match) {
  final rangeLow = match.namedGroup('rangeLow');
  if (rangeLow != null) {
    var low = _fromUnit(int.parse(rangeLow), match.namedGroup('rangeUnit')!);
    var high = _fromUnit(
      int.parse(match.namedGroup('rangeHigh')!),
      match.namedGroup('rangeUnit')!,
    );
    if (low > high) {
      final swap = low;
      low = high;
      high = swap;
    }
    return StepCookTime(lower: low, upper: high);
  }

  final hours = match.namedGroup('hours');
  if (hours != null) {
    final duration = Duration(
      hours: int.parse(hours),
      minutes: int.parse(match.namedGroup('minutes')!),
    );
    return StepCookTime(lower: duration, upper: duration);
  }

  final amount = match.namedGroup('amount');
  if (amount == null) return null;
  final duration = _fromUnit(int.parse(amount), match.namedGroup('unit')!);
  return StepCookTime(lower: duration, upper: duration);
}

Duration _fromUnit(int value, String unit) {
  final u = unit.toLowerCase();
  if (u.startsWith('h')) return Duration(hours: value);
  if (u.startsWith('s')) return Duration(seconds: value);
  return Duration(minutes: value);
}

/// Elapsed moments when the timer should announce remaining time.
///
/// Ranges stay quiet until [lower], then speak at that moment and on every
/// whole minute after it, up to but not including [upper]. Exact times speak
/// on every whole minute before [upper]. Finishing is announced separately.
List<Duration> elapsedAlertMarks(Duration lower, Duration upper) {
  final end = upper.inSeconds;
  if (end <= 0) return const [];

  final marks = <int>[];
  if (lower < upper) {
    final start = lower.inSeconds;
    if (start > 0 && start < end) marks.add(start);
    var nextMinute = (start ~/ 60) * 60 + 60;
    while (nextMinute < end) {
      if (marks.isEmpty || marks.last != nextMinute) marks.add(nextMinute);
      nextMinute += 60;
    }
  } else {
    var nextMinute = 60;
    while (nextMinute < end) {
      marks.add(nextMinute);
      nextMinute += 60;
    }
  }
  return [for (final seconds in marks) Duration(seconds: seconds)];
}

/// Spoken length, such as "18 minutes" or "1 minute 30 seconds".
String formatCookDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds <= 0) return '0 seconds';

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = totalSeconds.remainder(60);
  final parts = <String>[];
  if (hours > 0) {
    parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
  }
  if (minutes > 0) {
    parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');
  }
  if (seconds > 0) {
    parts.add('$seconds ${seconds == 1 ? 'second' : 'seconds'}');
  }
  return parts.join(' ');
}

String _passedClause(Duration duration) {
  final phrase = formatCookDuration(duration);
  final singular = RegExp(r'^1 (hour|minute|second)$').hasMatch(phrase);
  return '$phrase ${singular ? 'has' : 'have'} passed';
}

/// Spoken when a step first offers its timer. The timer is not running yet.
String timerReadySpeech(String timerName, Duration duration) {
  return '$timerName is set for ${formatCookDuration(duration)}. '
      'It will provide alerts along the way. '
      'Press Start to start the timer.';
}

/// Spoken when the cook presses Start.
String timerStartedSpeech(String timerName) => '$timerName started.';

String timerPausedSpeech(String timerName) => '$timerName paused.';

String timerResumedSpeech(String timerName) => '$timerName resumed.';

/// Spoken for an in-progress elapsed and remaining-time alert.
String timerProgressSpeech(
  String timerName,
  Duration elapsed,
  Duration remaining,
) {
  return '$timerName. ${_passedClause(elapsed)}. '
      '${formatCookDuration(remaining)} remaining.';
}

/// Spoken once, when the timer reaches its full duration.
String timerFinishedSpeech(String timerName, Duration duration) {
  return '${_passedClause(duration)}. $timerName is finished.';
}

/// Extra words that mean a recipe-name part, used when the step says
/// "sandwich" instead of "grilled cheese".
const _dishAliases = <String, List<String>>{
  'grilled cheese': ['sandwich'],
  'pancakes': ['pancake'],
  'scrambled eggs': ['egg', 'eggs'],
  'veggie fried rice': ['rice'],
  'chocolate chip cookies': ['cookie', 'cookies'],
  'brownies': ['brownie'],
  'yogurt parfait': ['parfait', 'yogurt'],
  'burger': ['patty', 'bun'],
  'spaghetti': ['pasta', 'noodle', 'noodles', 'sauce'],
  'pizza': ['crust'],
};

class _DishPart {
  const _DishPart(this.label, this.keywords);

  final String label;
  final List<String> keywords;
}

/// Food name for a step timer, such as "Tomato Basil Soup" or
/// "Grilled Cheese, second side".
///
/// Combo recipes (a name split on "+", "&", "and", or "with") use the part
/// the step is about. When this step does not name either food, earlier steps
/// decide which part is underway. A single-recipe step that names an
/// ingredient uses that ingredient.
String cookingTimerFoodLabel({
  required String recipeName,
  required List<String> steps,
  required int stepIndex,
  List<String> ingredientNames = const [],
}) {
  final parts = _dishParts(recipeName);
  final step = steps[stepIndex];

  String? label;
  if (parts.length > 1) {
    label =
        _matchDishPart(step, parts) ??
        _matchEarlierDishPart(steps, stepIndex, parts);
  }
  label ??= _matchIngredient(step, ingredientNames);
  label ??= parts.length == 1 ? parts.first.label : recipeName.trim();

  if (_isSecondSide(step) && !label.toLowerCase().contains('second side')) {
    label = '$label, second side';
  }
  return label;
}

List<_DishPart> _dishParts(String recipeName) {
  final labels = recipeName
      .split(RegExp(r'\s+(?:and|with)\s+|\s*[+&]\s*', caseSensitive: false))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (labels.isEmpty) {
    final name = recipeName.trim();
    return [if (name.isNotEmpty) _DishPart(name, _keywordsFor(name))];
  }
  return [for (final label in labels) _DishPart(label, _keywordsFor(label))];
}

List<String> _keywordsFor(String label) {
  final normalized = label.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final words = normalized
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.length > 3)
      .toList();
  final aliases = _dishAliases[normalized] ?? const <String>[];
  return {...words, ...aliases}.toList();
}

String? _matchDishPart(String text, List<_DishPart> parts) {
  _DishPart? best;
  var bestAt = -1;
  for (final part in parts) {
    for (final keyword in part.keywords) {
      final match = RegExp(
        '\\b${RegExp.escape(keyword)}\\b',
        caseSensitive: false,
      ).allMatches(text);
      for (final found in match) {
        if (found.start >= bestAt) {
          best = part;
          bestAt = found.start;
        }
      }
    }
  }
  return best?.label;
}

String? _matchEarlierDishPart(
  List<String> steps,
  int stepIndex,
  List<_DishPart> parts,
) {
  for (var index = stepIndex - 1; index >= 0; index--) {
    final match = _matchDishPart(steps[index], parts);
    if (match != null) return match;
  }
  return null;
}

String? _matchIngredient(String step, List<String> ingredientNames) {
  for (final ingredient in ingredientNames) {
    final clean = ingredient.trim();
    if (clean.length < 4) continue;
    final words = clean
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length > 3);
    if (words.any((word) => _containsWord(step, word))) return clean;
  }
  return null;
}

bool _containsWord(String text, String word) {
  return RegExp(
    '\\b${RegExp.escape(word)}\\b',
    caseSensitive: false,
  ).hasMatch(text);
}

bool _isSecondSide(String step) {
  return RegExp(
    r'\b(?:second|other)\s+side\b',
    caseSensitive: false,
  ).hasMatch(step);
}
