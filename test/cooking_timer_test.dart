import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/cooking_timer.dart';

void main() {
  test('uses the longest duration and the high end of a range', () {
    final pizza = parseStepCookTime(
      'Bake the pizza for 12–18 minutes until the crust is golden '
      'and the cheese is bubbly.',
    );
    expect(pizza?.lower, const Duration(minutes: 12));
    expect(pizza?.upper, const Duration(minutes: 18));

    final hyphenated = parseStepCookTime('Bake for 12-18 minutes.');
    expect(hyphenated?.lower, const Duration(minutes: 12));
    expect(hyphenated?.upper, const Duration(minutes: 18));

    final soup = parseStepCookTime(
      'Place the saucepan on the stove over medium heat and cook for '
      '5–7 minutes, stirring every 1–2 minutes.',
    );
    expect(soup?.lower, const Duration(minutes: 5));
    expect(soup?.upper, const Duration(minutes: 7));
  });

  test('reads single minutes, seconds, and combined hours', () {
    expect(
      parseStepCookTime('mix for about 1 minute until smooth')?.upper,
      const Duration(minutes: 1),
    );
    expect(
      parseStepCookTime('let the brownies cool for at least 20 minutes')?.upper,
      const Duration(minutes: 20),
    );
    expect(
      parseStepCookTime('cook for 1 more minute')?.upper,
      const Duration(minutes: 1),
    );
    expect(
      parseStepCookTime(
        'Stir the dry ingredients together for 30 seconds.',
      )?.upper,
      const Duration(seconds: 30),
    );
    expect(
      parseStepCookTime('Simmer for 1 hour and 30 minutes.')?.upper,
      const Duration(hours: 1, minutes: 30),
    );

    final sequential = parseStepCookTime(
      'microwave for 20 seconds, then another 10 seconds if needed',
    );
    expect(sequential?.upper, const Duration(seconds: 20));
    expect(sequential?.isRange, isFalse);
  });

  test('ignores temperatures, measurements, and steps with no time', () {
    expect(
      parseStepCookTime(
        'Preheat the oven to 425–475 degrees Fahrenheit, following the '
        'dough package for the exact temperature.',
      ),
      isNull,
    );
    expect(
      parseStepCookTime(
        'Lightly flour the work surface and stretch or roll the pizza dough '
        'into a 12–14 inch circle.',
      ),
      isNull,
    );
    expect(
      parseStepCookTime('Add 1–2 teaspoons oil or 1 pat of butter.'),
      isNull,
    );
    expect(parseStepCookTime('Slice and serve.'), isNull);
  });

  test('alerts start at the low end of a range, then every minute', () {
    expect(
      elapsedAlertMarks(
        const Duration(minutes: 12),
        const Duration(minutes: 18),
      ),
      [
        const Duration(minutes: 12),
        const Duration(minutes: 13),
        const Duration(minutes: 14),
        const Duration(minutes: 15),
        const Duration(minutes: 16),
        const Duration(minutes: 17),
      ],
    );
    expect(
      elapsedAlertMarks(const Duration(minutes: 2), const Duration(minutes: 4)),
      [const Duration(minutes: 2), const Duration(minutes: 3)],
    );
  });

  test('exact times announce every minute before the end', () {
    expect(
      elapsedAlertMarks(const Duration(minutes: 5), const Duration(minutes: 5)),
      [
        const Duration(minutes: 1),
        const Duration(minutes: 2),
        const Duration(minutes: 3),
        const Duration(minutes: 4),
      ],
    );
    expect(
      elapsedAlertMarks(
        const Duration(seconds: 30),
        const Duration(seconds: 30),
      ),
      isEmpty,
    );
  });

  test('speech names the timer, its duration, and the later alerts', () {
    expect(
      timerReadySpeech('Pizza Timer', const Duration(minutes: 18)),
      'Pizza Timer is set for 18 minutes. '
      'It will provide alerts along the way. '
      'Press Start to start the timer.',
    );
    expect(timerStartedSpeech('Pizza Timer'), 'Pizza Timer started.');
    expect(
      timerProgressSpeech(
        'Pizza Timer',
        const Duration(minutes: 12),
        const Duration(minutes: 6),
      ),
      'Pizza Timer. 12 minutes have passed. 6 minutes remaining.',
    );
    expect(
      timerFinishedSpeech('Pizza Timer', const Duration(minutes: 18)),
      '18 minutes have passed. Pizza Timer is finished.',
    );
    expect(
      timerFinishedSpeech('Pancake Timer', const Duration(seconds: 30)),
      '30 seconds have passed. Pancake Timer is finished.',
    );
  });
}
