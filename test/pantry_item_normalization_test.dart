import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/pantry_item_normalization.dart';

void main() {
  group('normalizePantryFoodName', () {
    final cases = {
      'potatoes': 'potato',
      'Potato': 'potato',
      'carrots': 'carrot',
      'bell peppers': 'pepper',
      'bok choy': 'bok choy',
      'pak choi': 'bok choy',
      'romaine lettuce': 'lettuce',
      'celery stalks': 'celery',
      '  BELL-PEPPERS!! ': 'pepper',
    };

    for (final entry in cases.entries) {
      test('${entry.key} normalizes consistently', () {
        expect(normalizePantryFoodName(entry.key), entry.value);
      });
    }

    test('removes packaging words without creating a food match', () {
      expect(
        normalizePantryFoodName('Fresh Farms plastic bag'),
        'fresh farms',
      );
      expect(normalizePantryFoodName('unrelated cereal box'), 'unrelated cereal');
    });

    test('unrelated foods remain distinct', () {
      expect(
        normalizePantryFoodName('potatoes'),
        isNot(normalizePantryFoodName('tomatoes')),
      );
    });

    test('matches equivalent unchecked list names without substring matching', () {
      expect(matchPantryFoodName('potatoes', ['Potato']), ['Potato']);
      expect(matchPantryFoodName('potato', ['Potatoes']), ['Potatoes']);
      expect(matchPantryFoodName('carrots', ['Carrot']), ['Carrot']);
      expect(matchPantryFoodName('bell peppers', ['Pepper']), ['Pepper']);
      expect(matchPantryFoodName('bok choy', ['Bok Choy']), ['Bok Choy']);
      expect(matchPantryFoodName('romaine lettuce', ['Lettuce']), ['Lettuce']);
      expect(matchPantryFoodName('tomatoes', ['Potato']), isEmpty);
      expect(matchPantryFoodName('potato brand box', ['Potato']), isEmpty);
    });

    test('requires clarification for equivalent names', () {
      expect(matchPantryFoodName('potatoes', ['Potato', 'Potatoes']), isEmpty);
    });
  });
}
