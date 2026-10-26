// Manual, live before/after image comparison; not a Flutter test.
// Usage: dart scripts/compare_dining_milestone5.dart INPUT_DIR OUTPUT_DIR [compact]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/dining_food.dart';
import '../lib/dining_ocr.dart';

const trayFocus = '''
For visual identification of an unlabeled food, focus only on the food inside that item's tray, bowl, plate, or serving container. Use its visible shape, texture, and color to choose a short supported dish name. Ignore nearby decorations, station headings, utensils, and other dishes as evidence of its ingredients. Do not output a visual description or reasoning; return only the existing JSON fields. This rule applies only to visual inference: still prioritize readable dish labels and include readable drink-dispenser options.''';

const compactTrayFocus =
    'Without a readable label, identify only the food inside each tray, bowl, '
    'or plate. Use its visible shape, color, and texture to choose a short '
    'supported name. Ignore the surroundings when inferring ingredients. '
    'Keep this visual assessment out of the response.';

Future<Map<String, dynamic>> request(
  String route,
  List<int> bytes,
  String filename,
  Map<String, String> fields,
) async {
  final client = HttpClient();
  const boundary = 'lumio-milestone5-comparison';
  try {
    final body = BytesBuilder();
    void text(String value) => body.add(utf8.encode(value));
    for (final field in fields.entries) {
      text(
        '--$boundary\r\nContent-Disposition: form-data; name="${field.key}"\r\n\r\n${field.value}\r\n',
      );
    }
    text(
      '--$boundary\r\nContent-Disposition: form-data; name="image"; filename="$filename"\r\nContent-Type: image/png\r\n\r\n',
    );
    body.add(bytes);
    text('\r\n--$boundary--\r\n');
    final req = await client.postUrl(
      Uri.parse('http://128.180.121.230:5010/$route'),
    );
    req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
    req.add(body.takeBytes());
    final response = await req.close();
    final result = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode}: $result');
    }
    return jsonDecode(result) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  if (args.length < 2 || args.length > 3) {
    throw ArgumentError('INPUT_DIR OUTPUT_DIR [compact] required');
  }
  final compact = args.length == 3 && args[2] == 'compact';
  final output = Directory(args[1])..createSync(recursive: true);
  const names = [
    'test1-drinks',
    'test2-four-pans',
    'test3-desserts',
    'test4-hot-line',
    'test5-wide-line',
  ];
  for (var i = 0; i < names.length; i++) {
    final name = names[i];
    final bytes = File('${args[0]}/$name.png').readAsBytesSync();
    final ocrFile = File('${output.path}/$name-ocr.json');
    final ocr = ocrFile.existsSync()
        ? jsonDecode(ocrFile.readAsStringSync()) as Map<String, dynamic>
        : await request(
            'extract-text',
            bytes,
            '$name.png',
            {},
          ).timeout(const Duration(seconds: 90));
    File('${output.path}/$name-ocr.json').writeAsStringSync(jsonEncode(ocr));
    final prompt = diningPromptWithOcr(diningOcrText(ocr));
    // Alternate order to reduce a simple warm-up/order bias.
    final variants = compact
        ? ['compact-tray']
        : i.isEven
        ? ['baseline', 'tray']
        : ['tray', 'baseline'];
    for (final variant in variants) {
      final question = compact
          ? prompt.replaceFirst(
              'Without a readable label, use a short visual estimate such as red sauce.',
              compactTrayFocus,
            )
          : variant == 'tray'
          ? '$prompt\n$trayFocus'
          : prompt;
      File(
        '${output.path}/$name-$variant-prompt.txt',
      ).writeAsStringSync(question);
      stdout.writeln('Starting $name $variant');
      final watch = Stopwatch()..start();
      try {
        final response = await request('predict', bytes, '$name.png', {
          'question': question,
          'task': kDiningVlmTask,
          'max_tokens': '$kDiningMaxTokens',
        }).timeout(const Duration(seconds: 120));
        final raw = response['answer']?.toString() ?? '';
        File('${output.path}/$name-$variant-raw.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(response),
        );
        final parsed = parseDiningResponse(raw, requireEvidence: true);
        final record = {
          'image': name,
          'variant': variant,
          'elapsed_ms': watch.elapsedMilliseconds,
          'raw_response': response,
          'parsed_names': parsed.foods.map((food) => food.dishName).toList(),
          'incomplete': diningAnswerIncomplete(raw),
          'looped': diningAnswerLooped(raw),
          'parse_error': parsed.error,
        };
        File(
          '${output.path}/$name-$variant.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(record));
        stdout.writeln(
          jsonEncode({
            'image': name,
            'variant': variant,
            'parsed_names': record['parsed_names'],
            'raw_answer': raw,
            'incomplete': record['incomplete'],
            'elapsed_ms': record['elapsed_ms'],
          }),
        );
      } catch (error) {
        File(
          '${output.path}/$name-$variant-error.txt',
        ).writeAsStringSync('$error');
        stdout.writeln('$name $variant failed: $error');
      }
    }
  }
}
