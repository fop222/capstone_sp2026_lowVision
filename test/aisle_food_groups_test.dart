import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/aisle_food_groups.dart';

void main() {
  // OCR of the user's photo of a "FRUITS" aisle sign.
  const fruitsSign = 'XO;qa8vG\nFRUITS';

  test('a FRUITS sign covers berries', () {
    expect(aisleSignCoversItem(fruitsSign, 'berries', 'Other'), isTrue);
    expect(aisleSignCoversItem(fruitsSign, 'Blueberries', 'Other'), isTrue);
    expect(aisleSignCoversItem(fruitsSign, 'apples', ''), isTrue);
  });

  test('a FRUITS sign does not cover other groups', () {
    expect(aisleSignCoversItem(fruitsSign, 'milk', 'Other'), isFalse);
    expect(aisleSignCoversItem(fruitsSign, 'chips', 'Other'), isFalse);
  });

  test('signs name the group of common items', () {
    expect(aisleSignCoversItem('DAIRY', 'milk', 'Other'), isTrue);
    expect(aisleSignCoversItem('Eggs & Cheese', 'Greek yogurt', ''), isTrue);
    expect(aisleSignCoversItem('SNACKS', 'potato chips', 'Other'), isTrue);
    expect(aisleSignCoversItem('Beverages', 'Sprite', 'Other'), isTrue);
    expect(aisleSignCoversItem('PRODUCE', 'tomatoes', 'Other'), isTrue);
    expect(aisleSignCoversItem('Bakery', 'bagels', 'Other'), isTrue);
    expect(aisleSignCoversItem('Frozen Foods', 'ice cream', 'Other'), isTrue);
    expect(aisleSignCoversItem('Cereal\nBreakfast', 'oatmeal', ''), isTrue);
    expect(aisleSignCoversItem('Paper Goods', 'paper towels', ''), isTrue);
  });

  test('the list section counts too', () {
    expect(aisleSignCoversItem('FRUITS', 'Driscolls', 'Produce'), isTrue);
    expect(aisleSignCoversItem('DAIRY', 'Fage', 'Dairy'), isTrue);
  });

  test('a longer phrase wins over a word inside it', () {
    // Peanut butter is a spread, not dairy.
    expect(aisleSignCoversItem('DAIRY', 'peanut butter', 'Other'), isFalse);
    expect(
      aisleSignCoversItem('Peanut Butter & Jelly', 'peanut butter', ''),
      isTrue,
    );
  });

  test('one OCR slip on a long word still matches', () {
    expect(aisleSignCoversItem('FRUlTS', 'berries', 'Other'), isTrue);
    expect(aisleSignCoversItem('BEVERAGFS', 'juice', 'Other'), isTrue);
  });

  test('short words need an exact match', () {
    // "pea" is not "pear", and junk text names no group.
    expect(aisleGroupsOnSign('XO;qa8vG'), isEmpty);
    expect(aisleSignCoversItem('AISLE 7', 'berries', 'Other'), isFalse);
  });

  test('group labels for the spoken aisle name', () {
    expect(aisleGroupsOnSign(fruitsSign).map((g) => g.label), ['fruit']);
    expect(aisleGroupsOnSign('PRODUCE').map((g) => g.label), [
      'fruit',
      'vegetable',
    ]);
  });

  // Items from a real user's grocery lists.
  test('the last food word names the item', () {
    expect(aisleSignCoversItem('Oils & Sauces', 'Vegetable oil', ''), isTrue);
    expect(aisleSignCoversItem('PRODUCE', 'Vegetable oil', ''), isFalse);
    expect(
      aisleSignCoversItem(
        'CANNED GOODS & SOUP',
        "Campbell's Condensed Tomato Soup",
        '',
      ),
      isTrue,
    );
    expect(aisleSignCoversItem('SNACKS', 'Tortilla Chips', 'Snacks'), isTrue);
    expect(aisleSignCoversItem('BAKERY', 'Tortilla Chips', ''), isFalse);
    expect(aisleSignCoversItem('DAIRY', 'Blueberry Yogurt', ''), isTrue);
  });

  test('every choice in an "or" list counts', () {
    expect(aisleSignCoversItem('DAIRY', 'Milk or water', ''), isTrue);
    expect(aisleSignCoversItem('BEVERAGES', 'Milk or water', ''), isTrue);
    expect(
      aisleSignCoversItem('CONDIMENTS', 'Ketchup, mustard, or mayo', ''),
      isTrue,
    );
  });

  test('frozen items also belong to the frozen aisle', () {
    expect(
      aisleSignCoversItem('FROZEN FOODS', 'organic frozen mixed berries', ''),
      isTrue,
    );
    expect(
      aisleSignCoversItem('FROZEN', 'Cookies and Cream ice-cream cake', ''),
      isTrue,
    );
  });

  test('typed names match exactly; only sign text allows OCR slips', () {
    // "Party" must not read as "patty" (meat).
    expect(aisleSignCoversItem('MEAT', 'Blue Balloons', 'Party'), isFalse);
    expect(
      aisleSignCoversItem('PARTY SUPPLIES', 'Blue Balloons', 'Party'),
      isTrue,
    );
  });

  test('spices, baking and other pantry items', () {
    expect(aisleSignCoversItem('BAKING & SPICES', 'Dried oregano', ''), isTrue);
    expect(aisleSignCoversItem('BAKING & SPICES', 'Sesame seeds', ''), isTrue);
    expect(
      aisleSignCoversItem('BAKING', 'package fudge brownie mix', ''),
      isTrue,
    );
    expect(aisleSignCoversItem('DAIRY', 'Fresh mozzarella', ''), isTrue);
    expect(aisleSignCoversItem('WINE & BEER', 'white wine', ''), isTrue);
  });
}
