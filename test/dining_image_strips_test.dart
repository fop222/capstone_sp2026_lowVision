import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_low_vision_app/dining_image_strips.dart';

Future<Uint8List> _photo(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF884422),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<ui.Image> _decode(Uint8List bytes) async =>
    (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;

void main() {
  testWidgets('a photo becomes overlapping left, center, and right strips', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final strips = await cropDiningStrips(await _photo(1000, 600));
      expect(strips.map((s) => s.column), ['left', 'center', 'right']);
      for (final strip in strips) {
        final image = await _decode(strip.png);
        expect(image.width, 400);
        expect(image.height, 600);
      }
    });
  });

  testWidgets('large photos are scaled down before upload', (tester) async {
    await tester.runAsync(() async {
      final strips = await cropDiningStrips(await _photo(4000, 3000));
      final image = await _decode(strips.first.png);
      expect(image.height, 1024);
      expect(image.width, closeTo(1600 * 1024 / 3000, 1));
    });
  });
}
