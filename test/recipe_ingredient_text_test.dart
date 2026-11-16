import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/recipe_ingredient_text.dart';

String name(String line) =>
    cleanIngredientName(splitIngredientQuantity(line).$2);

void main() {
  test('nested notes leave no stray brackets', () {
    expect(name('2 tbsp cooking oil (vegetable (or canola))'), 'cooking oil');
    expect(name('1 onion (brown (or white)) )'), 'onion');
    expect(name('4 garlic cloves ((minced))'), 'garlic cloves');
    expect(
      name('2 birds eye or Thai chili ((deseeded if you want))'),
      'birds eye or Thai chili',
    );
  });

  test('a second unit after a slash goes with the amount', () {
    final parts = splitIngredientQuantity(
      '450 g / 1 lb pork mince (ground pork)',
    );
    expect(parts.$1, '450 g / 1 lb');
    expect(cleanIngredientName(parts.$2), 'pork mince');
    expect(name('/ 1 lb pork mince )'), 'pork mince');
  });

  test('a line with only a note or a bracket is dropped', () {
    expect(name(')'), '');
    expect(name('(optional)'), '');
    expect(name('1 tbsp ( )'), '');
  });

  test('a slash between words reads as "or"', () {
    expect(name('salt/pepper'), 'salt or pepper');
    expect(name('1 cup milk / water'), 'milk or water');
  });

  test('plain lines are unchanged', () {
    expect(name('1 tbsp fish sauce'), 'fish sauce');
    expect(name('green onion stem, sliced'), 'green onion stem');
    expect(name('Jasmine rice'), 'Jasmine rice');
    expect(splitIngredientQuantity('1/2 cup sugar').$1, '1/2 cup');
    expect(splitIngredientQuantity('1 ½ cups flour').$1, '1 ½ cups');
  });
}
