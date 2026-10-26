import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/dining_food.dart';
import 'package:my_low_vision_app/dining_results_screen.dart';

void main() {
  testWidgets('list shows name and location; details hold the facts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final parsed = parseDiningResponse('''
      {"foods":[
        {"dish_name":"Brownie","location":"furthest from you on your right","confidence":"medium","sign_text":"","allergens":["Nuts"],"dietary_preferences":[],"information_source":"visual estimate","warning":"No readable sign was visible."},
        {"dish_name":"Vegetable Lasagna","location":"closest to you on your left","confidence":"high","sign_text":"Vegetable Lasagna - Vegetarian - Contains Dairy","allergens":["Dairy"],"dietary_preferences":["Vegetarian"],"information_source":"sign","warning":""}
      ]}
    ''');

    await tester.pumpWidget(
      MaterialApp(home: DiningResultsScreen(foods: parsed.foods)),
    );

    expect(find.text('2 foods found'), findsOneWidget);
    final lasagnaTop = tester.getTopLeft(find.text('1. Vegetable Lasagna')).dy;
    final brownieTop = tester.getTopLeft(find.text('2. Brownie')).dy;
    expect(lasagnaTop, lessThan(brownieTop));

    // Screen readers hear position, name, and location, once each.
    expect(
      find.bySemanticsLabel(
        'Food 1 of 2. Vegetable Lasagna, closest to you on your left.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Hear all foods'), findsOneWidget);

    // The list is name and location only.
    expect(find.text('Location: Closest to you on your left'), findsOneWidget);
    expect(
      find.text('Location: Furthest from you on your right'),
      findsOneWidget,
    );
    expect(find.textContaining('Sign says'), findsNothing);
    expect(find.text('Allergens'), findsNothing);
    expect(find.textContaining('Confidence'), findsNothing);
    expect(find.textContaining('could not be confirmed'), findsNothing);

    await tester.tap(find.text('1. Vegetable Lasagna'));
    await tester.pumpAndSettle();

    expect(find.text('Hear this food'), findsOneWidget);
    expect(find.text('Dairy · Confirmed'), findsOneWidget);
    expect(find.text('Vegetarian · Confirmed'), findsOneWidget);
    expect(find.textContaining('Sign says: Vegetable Lasagna'), findsOneWidget);
    expect(find.text('Location: Closest to you on your left'), findsOneWidget);
    expect(find.textContaining('Confidence'), findsOneWidget);
    // One short staff line, not the long uncertainty paragraph.
    expect(find.text(kPleaseConfirmWithStaff), findsOneWidget);
    expect(find.textContaining('could not be confirmed'), findsNothing);
    expect(find.textContaining(kLumioCouldNotConfirm), findsNothing);
  });

  testWidgets('estimated food detail has no uncertainty paragraph', (
    tester,
  ) async {
    final parsed = parseDiningResponse('''
      {"foods":[{"dish_name":"Red cabbage","location":"closest to you on your left","confidence":"medium","sign_text":"","information_source":"visual estimate"}]}
    ''');
    await tester.pumpWidget(
      MaterialApp(home: DiningFoodDetailScreen(food: parsed.foods.single)),
    );
    expect(find.text('Possible Nuts · Estimated'), findsNothing);
    expect(find.text('Allergens'), findsOneWidget);
    expect(find.text('Dietary preferences'), findsOneWidget);
    expect(find.textContaining('Confidence'), findsOneWidget);
    expect(find.textContaining('This appears to be'), findsNothing);
    expect(find.textContaining('Ingredients and allergens'), findsNothing);
    expect(find.text(kPleaseConfirmWithStaff), findsOneWidget);
  });
}
