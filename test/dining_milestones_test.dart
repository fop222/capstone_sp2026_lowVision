import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/dining_food.dart';

Map<String, Object?> item(String name, {String? id}) => {
  'dish_name': name,
  'item_id': id,
  'location': 'middle left',
  'information_source': 'visual estimate',
  'identification_confidence': 0.9,
  'clearly_visible': true,
};

DiningParseResult scan(List<Map<String, Object?>> entries) =>
    parseDiningResponse(jsonEncode({'foods': entries}), requireEvidence: true);

void main() {
  test('drink labels are accepted and repeated options are deduplicated', () {
    final result = scan([
      {...item('Water'), 'sign_text': 'Water', 'information_source': 'sign'},
      {...item('Sprite'), 'sign_text': 'Sprite', 'information_source': 'sign'},
      item('Sprite'),
    ]);
    expect(result.foods.map((f) => f.dishName), ['Water', 'Sprite']);
  });

  test('one dessert tray is not counted under generic and labelled names', () {
    final result = scan([
      item('Cupcakes', id: 'tray1'),
      {
        ...item('Vanilla cupcakes', id: 'tray1'),
        'information_source': 'sign',
        'sign_text': 'Vanilla cupcakes',
      },
      item('Raspberry cupcakes', id: 'tray2'),
    ]);
    expect(result.foods.map((f) => f.dishName), [
      'Vanilla cupcakes',
      'Raspberry cupcakes',
    ]);
  });

  test(
    'low confidence, hidden and missing-evidence predictions are excluded',
    () {
      final result = scan([
        {...item('Chicken'), 'identification_confidence': 0.84},
        {...item('Potatoes'), 'clearly_visible': false},
        {...item('Carrots'), 'identification_confidence': null},
        {...item('Peppers'), 'identification_confidence': 85},
        {...item('Pasta'), 'identification_confidence': 0.85},
      ]);
      expect(result.foods.single.dishName, 'Pasta');
    },
  );

  test(
    'readable Marinara sign replaces generic sauce; glare stays uncertain',
    () {
      final result = scan([
        {
          ...item('Sauce'),
          'sign_text': 'Marinara',
          'information_source': 'sign',
        },
        {
          ...item('Rice'),
          'sign_text': 'Cil... lime rice',
          'information_source': 'sign',
          'warning': 'Glare: partly readable',
        },
      ]);
      expect(result.foods.first.dishName, 'Marinara');
      expect(result.foods.last.dishName, 'Rice');
      expect(result.foods.last.signPartial, isTrue);
    },
  );
}
