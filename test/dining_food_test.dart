import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/dining_food.dart';

void main() {
  group('dining prompt', () {
    test('asks for every food, sign priority, and uncertain allergens', () {
      expect(kDiningVlmPrompt, contains('"foods"'));
      expect(kDiningVlmPrompt, contains('Do not stop after the first food'));
      for (final location in kDiningLocations) {
        expect(kDiningVlmPrompt, contains(location));
      }
      expect(kDiningVlmPrompt.toLowerCase(), contains('sign'));
      expect(kDiningVlmPrompt, contains('visual estimate'));
      expect(
        kDiningVlmPrompt.toLowerCase(),
        contains('do not invent exact ingredients'),
      );
      expect(kDiningVlmPrompt.toLowerCase(), contains('buffet'));
      expect(kDiningVlmPrompt.toLowerCase(), contains('plate'));
      expect(kDiningVlmPrompt.toLowerCase(), contains('tray'));
    });
  });

  group('parseDiningResponse', () {
    test(
      'one signed food keeps the sign and does not confirm extra allergens',
      () {
        final result = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Chicken Lasagna",
          "location":"top left",
          "confidence":"high",
          "sign_text":"Vegetable Lasagna - Vegetarian - Contains Dairy",
          "allergens":["Dairy","Wheat"],
          "dietary_preferences":["Vegetarian"],
          "information_source":"sign",
          "warning":""
        }]}
      ''');

        expect(result.isValid, isTrue);
        final food = result.foods.single;
        expect(food.dishName, 'Vegetable Lasagna');
        expect(food.location, 'top left');
        expect(food.confidence, 'high');
        expect(food.informationSource, DiningInfoSource.sign);
        expect(_claim(food.allergens, 'Dairy'), DiningCertainty.confirmed);
        expect(_claim(food.allergens, 'Wheat'), DiningCertainty.estimated);
        expect(
          _claim(food.dietaryPreferences, 'Vegetarian'),
          DiningCertainty.confirmed,
        );
        expect(food.notices.join(' '), contains(kPleaseConfirmWithStaff));
        expect(food.notices.join(' '), contains(kLumioCouldNotConfirm));

        final spoken = spokenDiningFood(food);
        expect(spoken, contains('located at the top left'));
        expect(spoken, contains('Vegetarian'));
        expect(spoken, contains('Dairy'));
        expect(spoken, contains('Wheat may also be present'));
        expect(spoken, contains('dining staff'));
      },
    );

    test('visual estimate never presents allergens as confirmed', () {
      final result = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Pasta Primavera",
          "location":"middle center",
          "confidence":"high",
          "sign_text":"",
          "allergens":["Dairy","Wheat"],
          "dietary_preferences":["Vegetarian"],
          "information_source":"visual estimate",
          "warning":"This appears to be pasta with vegetables, but the exact dish could not be confirmed."
        }]}
      ''');

      final food = result.foods.single;
      expect(food.confidence, 'medium');
      expect(food.informationSource, DiningInfoSource.visualEstimate);
      expect(
        food.allergens.every(
          (claim) => claim.certainty == DiningCertainty.estimated,
        ),
        isTrue,
      );
      expect(
        food.dietaryPreferences.single.certainty,
        DiningCertainty.estimated,
      );
      expect(food.dietaryPreferences.single.label, 'Possibly Vegetarian');
      expect(food.warning, contains('could not be confirmed visually'));
      expect(food.notices.join(' '), contains(kLumioCouldNotConfirm));
      expect(food.notices.join(' '), contains(kPleaseConfirmWithStaff));
      expect(
        spokenDiningFood(food),
        contains('Possible allergens: Dairy and Wheat'),
      );
      expect(spokenDiningFood(food), isNot(contains('confirmed fact')));
    });

    test('a missing sign is not treated as confirmation', () {
      final result = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Roasted Vegetables",
          "location":"bottom right",
          "confidence":"high",
          "sign_text":"",
          "allergens":["Dairy"],
          "dietary_preferences":["Vegan"],
          "information_source":"sign",
          "warning":""
        }]}
      ''');
      final food = result.foods.single;
      expect(food.informationSource, DiningInfoSource.visualEstimate);
      expect(food.allergens.single.certainty, DiningCertainty.estimated);
      expect(
        food.dietaryPreferences.single.certainty,
        DiningCertainty.estimated,
      );
    });

    test('gluten-free sign is not overridden by a wheat guess', () {
      final result = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Rice Bowl",
          "location":"top right",
          "confidence":"high",
          "sign_text":"Rice Bowl - Vegan - Gluten-Free",
          "allergens":["Wheat","Soy"],
          "dietary_preferences":["Vegan","Gluten-Free"],
          "information_source":"sign",
          "warning":""
        }]}
      ''');
      final food = result.foods.single;
      expect(food.dishName, 'Rice Bowl');
      expect(
        food.allergens.map((claim) => claim.label),
        isNot(contains('Wheat')),
      );
      expect(_claim(food.allergens, 'Soy'), DiningCertainty.estimated);
      expect(
        _claim(food.dietaryPreferences, 'Vegan'),
        DiningCertainty.confirmed,
      );
      expect(
        _claim(food.dietaryPreferences, 'Gluten-Free'),
        DiningCertainty.confirmed,
      );
    });

    test('partially readable sign stays uncertain', () {
      final result = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Soup",
          "location":"middle left",
          "confidence":"low",
          "sign_text":"Tomato... Veget...",
          "allergens":["Dairy"],
          "dietary_preferences":["Vegetarian"],
          "information_source":"sign",
          "warning":"The sign is unclear."
        }]}
      ''');
      final food = result.foods.single;
      expect(food.signPartial, isTrue);
      expect(food.dishName, 'Soup');
      expect(food.confidence, isNot('high'));
      expect(
        _claim(food.dietaryPreferences, 'Vegetarian'),
        DiningCertainty.estimated,
      );
      expect(food.warning.toLowerCase(), contains('partly readable'));
      expect(food.notices.join(' '), contains(kLumioCouldNotConfirm));
    });

    test('several foods on one plate are kept and ordered by location', () {
      final result = parseDiningResponse('''
        {"foods":[
          {"dish_name":"Brownie","location":"bottom right","confidence":"medium","sign_text":"","allergens":[],"dietary_preferences":[],"information_source":"visual estimate","warning":""},
          {"dish_name":"Mashed Potatoes","location":"top center","confidence":"medium","sign_text":"","allergens":["Dairy"],"dietary_preferences":["Possibly vegetarian"],"information_source":"visual estimate","warning":""},
          {"dish_name":"Roast Chicken","location":"middle left","confidence":"medium","sign_text":"","allergens":[],"dietary_preferences":[],"information_source":"visual estimate","warning":""},
          {"dish_name":"Green Beans","location":"top left","confidence":"medium","sign_text":"","allergens":[],"dietary_preferences":["Possibly vegan"],"information_source":"visual estimate","warning":""}
        ]}
      ''');

      expect(result.foods.map((food) => food.dishName), [
        'Green Beans',
        'Mashed Potatoes',
        'Roast Chicken',
        'Brownie',
      ]);
      expect(result.foods.map((food) => food.location), [
        'top left',
        'top center',
        'middle left',
        'bottom right',
      ]);
    });

    test('crowded tray and similar foods stay separate', () {
      final result = parseDiningResponse('''
        ```json
        {"foods":[
          {"dish_name":"Pasta with red sauce","location":"top-left","confidence":"low","sign_text":"","allergens":["Wheat"],"dietary_preferences":[],"information_source":"visual estimate","warning":"Similar to the other pasta."},
          {"dish_name":"Pasta with white sauce","location":"top right","confidence":"low","sign_text":"","allergens":["Dairy","Wheat"],"dietary_preferences":[],"information_source":"visual estimate","warning":""},
          {"dish_name":"Pasta with vegetables","location":"middle","confidence":"low","sign_text":"","allergens":["Wheat"],"dietary_preferences":[],"information_source":"visual estimate","warning":""}
        ],}
        ```
      ''');

      expect(result.foods, hasLength(3));
      expect(result.foods.map((food) => food.location), [
        'top left',
        'top right',
        'middle center',
      ]);
      expect(
        result.foods.every(
          (food) => food.allergens.every(
            (claim) => claim.certainty == DiningCertainty.estimated,
          ),
        ),
        isTrue,
      );
    });

    test('buffet pans with clear signs use each sign', () {
      final result = parseDiningResponse('''
        {"foods":[
          {"dish_name":"Guess","location":"bottom","confidence":"high","sign_text":"Tofu Stir Fry - Vegan - Contains Soy","allergens":["Soy"],"dietary_preferences":["Vegan"],"information_source":"sign","warning":""},
          {"dish_name":"Guess","location":"top","confidence":"high","sign_text":"Beef Stew - Contains Wheat","allergens":["Wheat"],"dietary_preferences":[],"information_source":"sign","warning":""}
        ]}
      ''');

      expect(result.foods.first.dishName, 'Beef Stew');
      expect(result.foods.first.location, 'top center');
      expect(
        _claim(result.foods.first.allergens, 'Wheat'),
        DiningCertainty.confirmed,
      );
      expect(result.foods.last.dishName, 'Tofu Stir Fry');
      expect(result.foods.last.location, 'bottom center');
      expect(
        _claim(result.foods.last.allergens, 'Soy'),
        DiningCertainty.confirmed,
      );
      expect(
        _claim(result.foods.last.dietaryPreferences, 'Vegan'),
        DiningCertainty.confirmed,
      );
    });

    test('unknown food and invalid answers are not invented', () {
      final unknown = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Unidentified food",
          "location":"middle right",
          "confidence":"low",
          "sign_text":"",
          "allergens":[],
          "dietary_preferences":[],
          "information_source":"unknown",
          "warning":""
        }]}
      ''');
      expect(unknown.foods.single.informationSource, DiningInfoSource.unknown);
      expect(unknown.foods.single.confidence, 'low');
      expect(unknown.foods.single.allergens, isEmpty);
      expect(
        unknown.foods.single.notices.join(' '),
        contains(kLumioCouldNotConfirm),
      );

      expect(parseDiningResponse('I see lasagna and soup.').isValid, isFalse);
      expect(parseDiningResponse('{"foods":[]}').isValid, isFalse);
      expect(parseDiningResponse('').error, kDiningParseError);
    });

    test('answer cut off by the token limit keeps the finished foods', () {
      final result = parseDiningResponse(
        '{"foods":[{"dish_name":"Roast potatoes","location":"bottom left",'
        '"confidence":"medium","sign_text":"","allergens":[],'
        '"dietary_preferences":[],"information_source":"visual estimate",'
        '"warning":"Say \\"ask staff\\" {first}"},'
        '{"dish_name":"Meatballs","location":"bottom center",'
        '"confidence":"medium","sign_text":"","allergens":[],'
        '"dietary_preferences":[],"information_source":"visual estimate",'
        '"warning":""},{"dish_name":"',
      );
      expect(result.isValid, isTrue);
      expect(result.foods.map((f) => f.dishName), [
        'Roast potatoes',
        'Meatballs',
      ]);
    });

    test('different camera angles still map onto the nine locations', () {
      expect(normalizeDiningLocation('upper left'), 'top left');
      expect(normalizeDiningLocation('centre'), 'middle center');
      expect(normalizeDiningLocation('lower right'), 'bottom right');
      expect(
        diningLocationSortIndex('bottom left'),
        lessThan(diningLocationSortIndex('not a place')),
      );
    });
  });
}

DiningCertainty? _claim(List<DiningClaim> claims, String label) {
  for (final claim in claims) {
    if (claim.label == label || claim.label == 'Possibly $label') {
      return claim.certainty;
    }
  }
  return null;
}
