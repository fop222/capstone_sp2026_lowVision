import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/dining_screen.dart';
import 'package:my_low_vision_app/home_landing_screen.dart';

void main() {
  testWidgets('EATING opens Dining instead of coming soon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeLandingScreen()),
    );

    expect(find.text('EATING'), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);

    await tester.tap(find.text('EATING'));
    await tester.pumpAndSettle();

    expect(find.byType(DiningScreen), findsOneWidget);
    expect(find.text('Scan Buffet / Food'), findsOneWidget);
  });
}
