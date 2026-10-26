// Manual server check using the already authorized fountain reference image.
// Does not invoke Flutter tests.
import 'dart:convert';
import 'dart:io';

import '../lib/dining_food.dart';
import 'compare_dining_milestone5.dart' show request;

Future<void> main(List<String> args) async {
  if (args.length == 3) {
    final strips = <({String column, String raw})>[];
    for (var i = 0; i < args.length; i++) {
      final response = await request(
        'predict',
        File(args[i]).readAsBytesSync(),
        'fountain-closeup-$i.png',
        {
          'question': kDiningDrinkPrompt,
          'task': kDiningVlmTask,
          'max_tokens': '256',
        },
      ).timeout(const Duration(seconds: 60));
      strips.add((
        column: ['left', 'center', 'right'][i],
        raw: response['answer']?.toString() ?? '',
      ));
    }
    final merged = parseDiningDrinkStrips(strips);
    stdout.writeln(
      jsonEncode({
        'closeups': strips
            .map((s) => {'column': s.column, 'answer': s.raw})
            .toList(),
        'merged_names': merged.foods.map((f) => f.dishName).toList(),
      }),
    );
    return;
  }
  if (args.length != 1)
    throw ArgumentError('Supply one image or three close-ups');
  final response = await request(
    'predict',
    File(args.single).readAsBytesSync(),
    'fountain-drink-check.png',
    {
      'question': kDiningDrinkPrompt,
      'task': kDiningVlmTask,
      'max_tokens': '256',
    },
  ).timeout(const Duration(seconds: 60));
  final raw = response['answer']?.toString() ?? '';
  final parsed = parseDiningDrinks(raw);
  stdout.writeln(
    jsonEncode({
      'raw_answer': raw,
      'items': parsed.foods
          .map((food) => {'name': food.dishName, 'location': food.location})
          .toList(),
      'error': parsed.error,
    }),
  );
}
