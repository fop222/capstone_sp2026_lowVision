import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/dining_food.dart';
import 'package:my_low_vision_app/dining_history.dart';
import 'package:my_low_vision_app/dining_history_screen.dart';
import 'package:my_low_vision_app/dining_report_screen.dart';
import 'package:my_low_vision_app/dining_results_screen.dart';
import 'package:my_low_vision_app/dining_screen.dart';

const _cornbread = DiningFood(
  dishName: 'Buttermilk Cornbread',
  location: 'closest to you',
  confidence: 'high',
  signText: 'Buttermilk Cornbread\nContains: milk, eggs',
  allergens: [
    DiningClaim(label: 'Milk (Dairy)', certainty: DiningCertainty.confirmed),
    DiningClaim(label: 'Eggs', certainty: DiningCertainty.estimated),
  ],
  dietaryPreferences: [
    DiningClaim(label: 'Vegetarian', certainty: DiningCertainty.confirmed),
  ],
  informationSource: DiningInfoSource.sign,
  warning: '',
  signPartial: false,
);

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('a food survives a round trip through scan history', () {
    final back = DiningFood.fromJson(_cornbread.toJson());
    expect(back.dishName, 'Buttermilk Cornbread');
    expect(back.location, 'closest to you');
    expect(back.informationSource, DiningInfoSource.sign);
    expect(back.allergens.map((c) => c.chipLabel), [
      'Milk (Dairy)',
      'Possible Eggs',
    ]);
    expect(back.dietaryPreferences.single.label, 'Vegetarian');
  });

  test('a partial history row still opens', () {
    final food = DiningFood.fromJson({'dish_name': 'Soup'});
    expect(food.dishName, 'Soup');
    expect(food.informationSource, DiningInfoSource.unknown);
    expect(food.allergens, isEmpty);
  });

  test('scan times read naturally', () {
    final now = DateTime(2026, 11, 2, 18);
    expect(
      formatDiningScanTime(DateTime(2026, 11, 2, 15, 5), now: now),
      'Today at 3:05 PM',
    );
    expect(
      formatDiningScanTime(DateTime(2026, 11, 1, 0, 30), now: now),
      'Yesterday at 12:30 AM',
    );
    expect(
      formatDiningScanTime(DateTime(2026, 10, 26, 12), now: now),
      'Monday, October 26 at 12:00 PM',
    );
    expect(
      formatDiningScanTime(DateTime(2025, 12, 31, 9), now: now),
      'Wednesday, December 31, 2025 at 9:00 AM',
    );
  });

  testWidgets('dining screen has a See scan history button', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(const MaterialApp(home: DiningScreen()));
    expect(find.text('Scan Buffet / Food'), findsOneWidget);
    expect(find.text('See scan history'), findsOneWidget);
    expect(find.bySemanticsLabel('See scan history'), findsOneWidget);
    // Paddle OCR scan is hidden for now.
    expect(find.text('Scan with Paddle OCR'), findsNothing);
    // // Paddle OCR sits directly under Scan Buffet.
    // final scanTop = tester.getTopLeft(find.text('Scan Buffet / Food')).dy;
    // final paddleTop = tester.getTopLeft(find.text('Scan with Paddle OCR')).dy;
    // final historyTop = tester.getTopLeft(find.text('See scan history')).dy;
    // expect(scanTop, lessThan(paddleTop));
    // expect(paddleTop, lessThan(historyTop));
  });

  testWidgets('history lists scans with times and opens one', (tester) async {
    _tallView(tester);
    final when = DateTime.now().subtract(const Duration(minutes: 5));
    await tester.pumpWidget(
      MaterialApp(
        home: DiningHistoryScreen(
          load: () async => [
            DiningScan(id: 'a', createdAt: when, foods: const [_cornbread]),
          ],
          delete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final time = formatDiningScanTime(when);
    expect(time, startsWith('Today at'));
    expect(find.text(time), findsOneWidget);
    expect(find.text('1 food: Buttermilk Cornbread'), findsOneWidget);

    await tester.tap(find.text(time));
    await tester.pumpAndSettle();
    expect(find.text('1 food found'), findsOneWidget);
    expect(find.text('Scanned $time'), findsOneWidget);
    expect(find.text('Back to scan history'), findsOneWidget);
  });

  testWidgets('history says when there are no scans yet', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: DiningHistoryScreen(load: () async => [], delete: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No scans yet. Foods you scan will show up here.'),
      findsOneWidget,
    );
  });

  testWidgets('history load failure offers a retry', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: DiningHistoryScreen(
          load: () async => throw Exception('relation does not exist'),
          delete: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not load scan history. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('report sends the chosen problems and note', (tester) async {
    _tallView(tester);
    List<String>? sentProblems;
    String? sentNote, sentScan;
    await tester.pumpWidget(
      MaterialApp(
        home: DiningReportScreen(
          food: _cornbread,
          scanId: Future.value('scan-1'),
          send:
              ({
                required DiningFood food,
                required List<String> problems,
                String note = '',
                String? scanId,
              }) async {
                sentProblems = problems;
                sentNote = note;
                sentScan = scanId;
              },
        ),
      ),
    );

    // Nothing chosen yet: asks for a choice instead of sending.
    await tester.tap(find.text('Send report'));
    await tester.pump();
    expect(
      find.text('Choose at least one thing that looks wrong.'),
      findsOneWidget,
    );
    expect(sentProblems, isNull);

    await tester.tap(find.text('Wrong allergens'));
    await tester.tap(find.text('Wrong food name'));
    await tester.enterText(find.byType(TextField), 'It is corn muffins');
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(sentProblems, ['Wrong food name', 'Wrong allergens']);
    expect(sentNote, 'It is corn muffins');
    expect(sentScan, 'scan-1');
    expect(find.text('Thank you. Your report was sent.'), findsOneWidget);
  });

  testWidgets('food details have a Report incorrect result button', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      const MaterialApp(home: DiningResultsScreen(foods: [_cornbread])),
    );
    await tester.tap(find.text('1. Buttermilk Cornbread'));
    await tester.pumpAndSettle();
    expect(find.text('Report incorrect result'), findsOneWidget);
    await tester.ensureVisible(find.text('Report incorrect result'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report incorrect result'));
    await tester.pumpAndSettle();
    expect(find.text('What looks wrong?'), findsOneWidget);
  });
}
