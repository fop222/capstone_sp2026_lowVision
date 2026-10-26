import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/dining_food.dart';

void main() {
  group('dining prompt', () {
    test('asks for every food, sign priority, and uncertain allergens', () {
      expect(kDiningVlmPrompt, contains('"foods"'));
      expect(kDiningVlmPrompt, contains('"count"'));
      expect(
        kDiningVlmPrompt.toLowerCase(),
        contains('describe each one exactly once'),
      );
      expect(kDiningVlmPrompt, contains('No two objects have the same'));
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
          "location":"closest to you on your left",
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
        expect(food.location, 'closest to you on your left');
        expect(food.confidence, 'high');
        expect(food.informationSource, DiningInfoSource.sign);
        expect(_claim(food.allergens, 'Dairy'), DiningCertainty.confirmed);
        expect(_claim(food.allergens, 'Wheat'), isNull);
        expect(
          _claim(food.dietaryPreferences, 'Vegetarian'),
          DiningCertainty.confirmed,
        );
        expect(food.notices.join(' '), contains(kPleaseAskStaffAllergens));

        final spoken = spokenDiningFood(food);
        expect(spoken, contains('located closest to you on your left'));
        expect(spoken, contains('Vegetarian'));
        expect(spoken, contains('Dairy'));
        expect(spoken, isNot(contains('Wheat may also be present')));
        expect(spoken, contains('dining staff'));
      },
    );

    test('visual estimate never presents allergens as confirmed', () {
      final result = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Pasta Primavera",
          "location":"farther from you",
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
        contains('Allergens could not be confirmed'),
      );
      expect(spokenDiningFood(food), isNot(contains('confirmed fact')));
    });

    test('a missing sign is not treated as confirmation', () {
      final result = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Roasted Vegetables",
          "location":"furthest from you on your right",
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
      expect(food.allergens, isEmpty);
      expect(
        food.dietaryPreferences.single.certainty,
        DiningCertainty.estimated,
      );
    });

    test('gluten-free sign is not overridden by a wheat guess', () {
      final result = parseDiningResponse('''
        {"foods":[{
          "dish_name":"Rice Bowl",
          "location":"closest to you on your right",
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
      expect(_claim(food.allergens, 'Soy'), isNull);
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
          "location":"farther from you on your left",
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
          {"dish_name":"Brownie","location":"furthest from you on your right","confidence":"medium","sign_text":"","allergens":[],"dietary_preferences":[],"information_source":"visual estimate","warning":""},
          {"dish_name":"Mashed Potatoes","location":"closest to you","confidence":"medium","sign_text":"","allergens":["Dairy"],"dietary_preferences":["Possibly vegetarian"],"information_source":"visual estimate","warning":""},
          {"dish_name":"Roast Chicken","location":"farther from you on your left","confidence":"medium","sign_text":"","allergens":[],"dietary_preferences":[],"information_source":"visual estimate","warning":""},
          {"dish_name":"Green Beans","location":"closest to you on your left","confidence":"medium","sign_text":"","allergens":[],"dietary_preferences":["Possibly vegan"],"information_source":"visual estimate","warning":""}
        ]}
      ''');

      expect(result.foods.map((food) => food.dishName), [
        'Green Beans',
        'Mashed Potatoes',
        'Roast Chicken',
        'Brownie',
      ]);
      expect(result.foods.map((food) => food.location), [
        'closest to you on your left',
        'closest to you',
        'farther from you on your left',
        'furthest from you on your right',
      ]);
    });

    test('crowded tray and similar foods stay separate', () {
      final result = parseDiningResponse('''
        ```json
        {"foods":[
          {"dish_name":"Pasta with red sauce","location":"closest to you on your left","confidence":"low","sign_text":"","allergens":["Wheat"],"dietary_preferences":[],"information_source":"visual estimate","warning":"Similar to the other pasta."},
          {"dish_name":"Pasta with white sauce","location":"closest to you on your right","confidence":"low","sign_text":"","allergens":["Dairy","Wheat"],"dietary_preferences":[],"information_source":"visual estimate","warning":""},
          {"dish_name":"Pasta with vegetables","location":"farther from you","confidence":"low","sign_text":"","allergens":["Wheat"],"dietary_preferences":[],"information_source":"visual estimate","warning":""}
        ],}
        ```
      ''');

      expect(result.foods, hasLength(3));
      expect(result.foods.map((food) => food.location), [
        'closest to you on your left',
        'closest to you on your right',
        'farther from you',
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
          {"dish_name":"Guess","location":"furthest from you","confidence":"high","sign_text":"Tofu Stir Fry - Vegan - Contains Soy","allergens":["Soy"],"dietary_preferences":["Vegan"],"information_source":"sign","warning":""},
          {"dish_name":"Guess","location":"closest to you","confidence":"high","sign_text":"Beef Stew - Contains Wheat","allergens":["Wheat"],"dietary_preferences":[],"information_source":"sign","warning":""}
        ]}
      ''');

      expect(result.foods.first.dishName, 'Beef Stew');
      expect(result.foods.first.location, 'closest to you');
      expect(
        _claim(result.foods.first.allergens, 'Wheat'),
        DiningCertainty.confirmed,
      );
      expect(result.foods.last.dishName, 'Tofu Stir Fry');
      expect(result.foods.last.location, 'furthest from you');
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
          "location":"farther from you on your right",
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

    test('sign text that echoes a visual guess is dropped', () {
      final result = parseDiningResponse('''
        {"foods":[
          {"dish_name":"pepper","location":"furthest from you on your left","sign_text":"pepper","information_source":"visual estimate"},
          {"dish_name":"Buns","location":"closest to you","sign_text":"Bun","information_source":"visual estimate"},
          {"dish_name":"white cheese","location":"furthest from you on your left","sign_text":"BLUE CHEESE","information_source":"visual estimate"}
        ]}
      ''');
      final byName = {for (final f in result.foods) f.dishName: f};
      expect(byName['pepper']!.signText, isEmpty);
      expect(byName['Buns']!.signText, isEmpty);
      expect(byName['white cheese']!.signText, 'BLUE CHEESE');
    });

    test('a real sign that names the dish is kept', () {
      final result = parseDiningResponse('''
        {"foods":[{"dish_name":"Chicken Lasagna","location":"closest to you on your left","sign_text":"Chicken Lasagna","information_source":"sign","confidence":"high"}]}
      ''');
      expect(result.foods.single.signText, 'Chicken Lasagna');
      expect(result.foods.single.informationSource, DiningInfoSource.sign);
    });

    test('one sign on several foods is a station sign, not a dish label', () {
      final result = parseDiningResponse('''
        {"foods":[
          {"dish_name":"potato","location":"closest to you on your left","sign_text":"Köks världen allergen!","information_source":"visual estimate"},
          {"dish_name":"meatballs","location":"closest to you","sign_text":"Köks världen allergen!","information_source":"visual estimate"}
        ]}
      ''');
      expect(result.foods.every((f) => f.signText.isEmpty), isTrue);
    });

    test('a counted-but-repeated answer is detected as a loop', () {
      final looped =
          '{"count":13,"foods":['
          '${List.filled(13, '{"dish_name":"pepper","location":"furthest from you on your left"}').join(',')}'
          ']}';
      expect(diningAnswerLooped(looped), isTrue);
      expect(
        diningAnswerLooped(
          '{"count":8,"foods":[{"dish_name":"red cabbage"},{"dish_name":"carrots"},'
          '{"dish_name":"white cabbage"},{"dish_name":"white cabbage"},'
          '{"dish_name":"peppers"},{"dish_name":"white cabbage"},'
          '{"dish_name":"white cabbage"},{"dish_name":"peppers"}]}',
        ),
        // Any repeat in four or more items gets the closer look; the app
        // still keeps the full-photo list when the strips find no more.
        isTrue,
      );
      expect(
        diningAnswerLooped(
          '{"count":2,"foods":[{"dish_name":"bacon"},{"dish_name":"eggs"}]}',
        ),
        isFalse,
      );
    });

    test('strip answers merge with the column taken from the strip', () {
      final result = parseDiningStrips([
        (
          column: 'left',
          raw:
              '{"foods":[{"dish_name":"carrots","location":"furthest from you on your right"},'
              '{"dish_name":"beets","location":"closest to you","sign_text":"SALAD BAR"}]}',
        ),
        (
          column: 'center',
          raw:
              '{"foods":[{"dish_name":"carrots","location":"furthest from you"},'
              '{"dish_name":"peas","location":"farther from you on your left","sign_text":"SALAD BAR"}]}',
        ),
        (column: 'right', raw: 'not json'),
      ]);
      final byName = {for (final f in result.foods) f.dishName: f};
      expect(byName.keys, containsAll(['carrots', 'beets', 'peas']));
      expect(byName['carrots']!.location, 'furthest from you on your left');
      expect(byName['beets']!.location, 'closest to you on your left');
      expect(byName['peas']!.location, 'farther from you');
      expect(byName['beets']!.signText, isEmpty);
    });

    test('the list speaks name and location only', () {
      final food = parseDiningResponse(
        '{"foods":[{"dish_name":"Meatballs","location":"furthest from you"}]}',
      ).foods.single;
      expect(spokenDiningFoodBrief(food), 'Meatballs, furthest from you.');
      expect(spokenDiningFood(food), isNot(contains('This appears to be')));
      expect(spokenDiningFood(food), isNot(contains(kLumioCouldNotConfirm)));
    });

    test('a looping answer keeps one entry per food name', () {
      final result = parseDiningResponse('''
        {"count":5,"foods":[
          {"dish_name":"Meatballs","location":"closest to you","information_source":"visual estimate"},
          {"dish_name":"Red sauce","location":"closest to you","information_source":"visual estimate"},
          {"dish_name":"meatballs","location":"closest to you","information_source":"visual estimate"},
          {"dish_name":"Red sauce","location":"furthest from you on your left","information_source":"visual estimate"},
          {"dish_name":"Meatballs","location":"closest to you on your right","information_source":"visual estimate"}
        ]}
      ''');
      expect(result.foods.map((f) => f.dishName), ['Meatballs', 'Red sauce']);
    });

    test('unidentified food shows one short notice, even as an estimate', () {
      final result = parseDiningResponse('''
        {"foods":[{"dish_name":"unidentified food","location":"furthest from you",
          "confidence":"low","information_source":"visual estimate",
          "warning":"the dish could not be confirmed"}]}
      ''');
      final food = result.foods.single;
      expect(food.dishName, 'Unidentified food');
      expect(food.informationSource, DiningInfoSource.unknown);
      expect(food.notices, [kLumioCouldNotConfirm]);
    });

    test('answer cut off by the token limit keeps the finished foods', () {
      final result = parseDiningResponse(
        '{"foods":[{"dish_name":"Roast potatoes","location":"furthest from you on your left",'
        '"confidence":"medium","sign_text":"","allergens":[],'
        '"dietary_preferences":[],"information_source":"visual estimate",'
        '"warning":"Say \\"ask staff\\" {first}"},'
        '{"dish_name":"Meatballs","location":"furthest from you",'
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

    test('legacy frame coordinates never imply physical distance', () {
      expect(normalizeDiningLocation('upper left'), 'to your left');
      expect(normalizeDiningLocation('centre'), 'in front of you');
      expect(normalizeDiningLocation('lower right'), 'to your right');
      expect(
        diningLocationSortIndex('furthest from you on your left'),
        lessThan(diningLocationSortIndex('not a place')),
      );
    });
  });

  group('repeated names (Sprint 21 photos)', () {
    Map<String, dynamic> item(String name, String location, [String? sign]) => {
      'dish_name': name,
      'location': location,
      'identification_confidence': 0.9,
      'clearly_visible': true,
      if (sign != null) ...{'sign_text': sign, 'information_source': 'sign'},
    };
    List<String> names(List<Map<String, dynamic>> foods) => parseDiningResponse(
      jsonEncode({'foods': foods}),
      requireEvidence: true,
    ).foods.map((f) => f.dishName).toList();

    test('a general name gives way to a more specific one', () {
      expect(
        names([
          item('Green Beans', 'to your left', 'Green Beans'),
          item('Stewed Green Beans', 'to your right'),
          item('Pasta', 'to your left'),
        ]),
        unorderedEquals(['Stewed Green Beans', 'Pasta']),
      );
    });

    test('cupcakes are not listed under three different names', () {
      expect(
        names([
          item('Cupcakes', 'to your left'),
          item('Raspberry cupcakes', 'to your left'),
          item('Vanilla cupcakes', 'in front of you'),
          item('Blue cupcakes', 'in front of you'),
          item('Brownies', 'in front of you'),
        ]),
        unorderedEquals(['Raspberry cupcakes', 'Vanilla cupcakes', 'Brownies']),
      );
    });

    test('menu card headings are not foods', () {
      expect(
        names([
          item('Lunch', 'to your left', 'Lunch'),
          item('Main Entree', 'to your left', 'Main Entree'),
          item('Vegetarian', 'to your left', 'Vegetarian'),
          item('Italian', 'to your right', 'ITALIAN'),
          item('Honey Ginger Tofu', 'in front of you', 'Honey Ginger Tofu'),
          item('Vegetarian chili', 'to your right'),
        ]),
        // Milestone 3 moves Vegetarian into dietary preferences.
        unorderedEquals(['Honey Ginger Tofu', 'chili']),
      );
    });

    test('OCR noise from a background menu board is not a food', () {
      expect(
        names([
          item('Cocetote', 'to your right', 'Cocetote'),
          item('Foodiatice', 'to your right', 'Foodiatice'),
          item('Kfade=', 'to your right', 'Kfade='),
          item(
            'Funfetti Krispie Treats',
            'to your left',
            'Funfetti\nKrispie Treats',
          ),
          item(
            'Creamy Tomato Basil Soup',
            'to your left',
            'Creamy Tomato Basil Soup',
          ),
          item('Sprite', 'to your right', 'Sprite'),
          // Written by the model from what it sees, not copied: kept.
          item('Blue fudge squares', 'in front of you'),
        ]),
        unorderedEquals([
          'Funfetti Krispie Treats',
          'Creamy Tomato Basil Soup',
          'Sprite',
          'Blue fudge squares',
        ]),
      );
    });

    test('any repeat in a long list asks for a closer look', () {
      // Dessert case: 7 written, 4 distinct names.
      const dessert =
          '{"count":7,"foods":[{"dish_name":"cupcakes"},{"dish_name":"cupcakes"},'
          '{"dish_name":"frozen yogurt"},{"dish_name":"ice cream"},'
          '{"dish_name":"chocolate bars"},{"dish_name":"chocolate bars"},'
          '{"dish_name":"chocolate bars"}]}';
      expect(diningAnswerLooped(dessert), isTrue);
      expect(
        diningAnswerLooped(
          '{"count":4,"foods":[{"dish_name":"Pasta"},{"dish_name":"Sauce"},'
          '{"dish_name":"Green Beans"},{"dish_name":"Rice"}]}',
        ),
        isFalse,
      );
    });

    test('the prompt has no example dish the model can copy', () {
      expect(kDiningVlmPrompt, isNot(contains('Marinara')));
      expect(kDiningVlmPrompt, isNot(contains('red sauce')));
      expect(kDiningVlmPrompt, isNot(contains('at least 0.85')));
    });
  });

  group('drink stations', () {
    // OCR and model output recorded from the Sprint 21 fountain photo.
    const fountainOcr =
        'WATERI\nRPfer)\nGania\nHRC\n@atrt\nFbwer | RBve)\n9\n@utr\nORANGE\n'
        'Us\nPush\nFusm\nPush\nPUSH\nPUSH\nPUSH\nSpniet';
    const waterOnly =
        '{"count":1,"foods":[{"item_id":"1","dish_name":"Water",'
        '"location":"to your right","sign_text":"WATER",'
        '"information_source":"sign","confidence":"high",'
        '"identification_confidence":0.9,"clearly_visible":true}]}';
    const drinkAnswer =
        '```json { "drinks": [ "WATER", "Dr Pepper", "Fanta", "HI-C", '
        '"Coca-Cola", "POWERADE", "Dr Pepper", "Sprite", "Diet Coke", '
        '"Coca-Cola" ] } ```';

    test('dispenser push buttons or a drink name mark a drink station', () {
      expect(
        diningLooksLikeDrinkStation(labels: fountainOcr, answer: ''),
        isTrue,
      );
      expect(
        diningLooksLikeDrinkStation(labels: '', answer: waterOnly),
        isTrue,
      );
      expect(
        diningLooksLikeDrinkStation(
          labels: 'Marinara\nPenne',
          answer:
              '{"foods":[{"dish_name":"Penne pasta"},{"dish_name":"Marinara"}]}',
        ),
        isFalse,
      );
    });

    test('every dispenser becomes a drink, left to right', () {
      final full = parseDiningResponse(waterOnly, requireEvidence: true);
      // The bug as seen in the app: only the one plain-text label.
      expect(full.foods.map((f) => f.dishName), ['WATER']);

      final result = parseDiningDrinks(drinkAnswer, alongside: full);
      expect(result.foods.map((f) => f.dishName), [
        'Water',
        'Dr Pepper',
        'Fanta',
        'Hi-C',
        'Coca-Cola',
        'Powerade',
        'Sprite',
        'Diet Coke',
      ]);
      final byName = {for (final f in result.foods) f.dishName: f};
      expect(byName['Water']!.location, 'to your left');
      expect(byName['Powerade']!.location, 'in front of you');
      expect(byName['Diet Coke']!.location, 'to your right');
      expect(byName['Sprite']!.allergens, isEmpty);
    });

    test('food scanned with the drinks is kept', () {
      final food = parseDiningResponse(
        '{"foods":[{"dish_name":"Popcorn","location":"to your left",'
        '"identification_confidence":0.9,"clearly_visible":true}]}',
        requireEvidence: true,
      );
      final result = parseDiningDrinks(
        '{"drinks":["Sprite"]}',
        alongside: food,
      );
      expect(
        result.foods.map((f) => f.dishName),
        containsAll(['Popcorn', 'Sprite']),
      );
    });

    test('no drinks or bad JSON falls back to the regular scan', () {
      final full = parseDiningResponse(waterOnly, requireEvidence: true);
      expect(
        parseDiningDrinks('{"drinks":[]}', alongside: full).foods.length,
        1,
      );
      expect(parseDiningDrinks('no idea', alongside: full).foods.length, 1);
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
