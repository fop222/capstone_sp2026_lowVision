/// Splits a dining photo into overlapping left / center / right strips.
///
/// The 2B VLM loops on crowded buffets: it counts 13 pans, then writes the
/// first one 13 times. Each strip holds fewer foods, so it names them, and
/// the strip tells us the column without trusting the model's left/right.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// (column, start, end) as fractions of the photo width. The overlap keeps a
/// pan on a strip edge whole in at least one strip.
const List<(String, double, double)> kDiningStrips = [
  ('left', 0.0, 0.4),
  ('center', 0.3, 0.7),
  ('right', 0.6, 1.0),
];

/// The server downsizes to 768px anyway; keeping strips small keeps the
/// three uploads fast.
const int _kMaxStripSide = 1024;

Future<List<({String column, Uint8List png})>> cropDiningStrips(
  Uint8List photo,
) async {
  final codec = await ui.instantiateImageCodec(photo);
  final source = (await codec.getNextFrame()).image;
  final strips = <({String column, Uint8List png})>[];
  try {
    for (final (column, start, end) in kDiningStrips) {
      final png = await _cropPng(source, start, end);
      if (png != null) strips.add((column: column, png: png));
    }
  } finally {
    source.dispose();
  }
  return strips;
}

Future<Uint8List?> _cropPng(ui.Image source, double start, double end) async {
  final left = source.width * start;
  final width = source.width * (end - start);
  final height = source.height.toDouble();
  final longest = width > height ? width : height;
  final scale = longest > _kMaxStripSide ? _kMaxStripSide / longest : 1.0;
  final outWidth = (width * scale).round();
  final outHeight = (height * scale).round();
  if (outWidth < 1 || outHeight < 1) return null;

  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    ui.Rect.fromLTWH(left, 0, width, height),
    ui.Rect.fromLTWH(0, 0, outWidth.toDouble(), outHeight.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(outWidth, outHeight);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
