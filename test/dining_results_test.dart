import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/dining_food.dart';
import 'package:my_low_vision_app/dining_results_screen.dart';

void main() {
  testWidgets('detected foods stay in location order and open details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final parsed = parseDiningResponse('''
      {"foods":[
        {"dish_name":"Brownie","location":"bottom right","confidence":"medium","sign_text":"","allergens":["Nuts"],"dietary_preferences":[],"information_source":"visual estimate","warning":"No readable sign was visible."},
        {"dish_name":"Vegetable Lasagna","location":"top left","confidence":"high","sign_text":"Vegetable Lasagna - Vegetarian - Contains Dairy","allergens":["Dairy"],"dietary_preferences":["Vegetarian"],"information_source":"sign","warning":""}
      ]}
    ''');

    await tester.pumpWidget(
      MaterialApp(home: DiningResultsScreen(foods: parsed.foods)),
    );

    expect(find.text('2 foods found'), findsOneWidget);
    expect(find.textContaining('Sign says: Vegetable Lasagna'), findsOneWidget);
    expect(
      find.textContaining('Please confirm with dining staff.'),
      findsWidgets,
    );
    expect(find.text('Possible Nuts · Estimated'), findsOneWidget);
    expect(find.text('Vegetarian · Confirmed'), findsOneWidget);

    final lasagnaTop = tester.getTopLeft(find.text('1. Vegetable Lasagna')).dy;
    final brownieTop = tester.getTopLeft(find.text('2. Brownie')).dy;
    expect(lasagnaTop, lessThan(brownieTop));

    await tester.tap(find.text('1. Vegetable Lasagna'));
    await tester.pumpAndSettle();

    expect(find.text('Hear this food'), findsOneWidget);
    expect(find.text('Dairy · Confirmed'), findsOneWidget);
    expect(find.textContaining('Sign says: Vegetable Lasagna'), findsOneWidget);
  });
}
