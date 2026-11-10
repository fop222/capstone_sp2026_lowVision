// Paddle OCR scan is commented out for now. Uncomment this file to bring it back.

// /// Turns Paddle OCR lines into dining results, with no VLM: each dish card's
// /// title becomes a food, and the lines printed under it (Contains, icons,
// /// calories) become that card's sign text.
// library;
//
// import 'dart:convert';
//
// import 'dining_food.dart';
//
// /// Paddle reads below this are mostly glare and reflections.
// const double kPaddleMinScore = 0.6;
//
// /// One line Paddle read, with its box in image pixels.
// class PaddleLine {
//   const PaddleLine({
//     required this.text,
//     required this.score,
//     required this.left,
//     required this.top,
//     required this.right,
//     required this.bottom,
//   });
//
//   final String text;
//   final double score;
//   final double left, top, right, bottom;
//
//   double get height => bottom - top;
//   double get centerX => (left + right) / 2;
// }
//
// /// Paddle's read of one photo.
// class PaddleRead {
//   const PaddleRead({
//     required this.width,
//     required this.height,
//     required this.lines,
//   });
//
//   /// Parses the JSON from `paddleReadText`. Unreadable input gives no lines.
//   factory PaddleRead.fromJson(String raw) {
//     try {
//       final json = jsonDecode(raw) as Map<String, dynamic>;
//       final lines = <PaddleLine>[];
//       for (final item in json['lines'] as List? ?? const []) {
//         if (item is! Map) continue;
//         final box = item['box'];
//         if (box is! List || box.length != 4) continue;
//         final text = '${item['text'] ?? ''}'.trim();
//         if (text.isEmpty) continue;
//         lines.add(
//           PaddleLine(
//             text: text,
//             score: (item['score'] as num?)?.toDouble() ?? 0,
//             left: (box[0] as num).toDouble(),
//             top: (box[1] as num).toDouble(),
//             right: (box[2] as num).toDouble(),
//             bottom: (box[3] as num).toDouble(),
//           ),
//         );
//       }
//       return PaddleRead(
//         width: (json['width'] as num?)?.toDouble() ?? 0,
//         height: (json['height'] as num?)?.toDouble() ?? 0,
//         lines: lines,
//       );
//     } catch (_) {
//       return const PaddleRead(width: 0, height: 0, lines: []);
//     }
//   }
//
//   final double width;
//   final double height;
//   final List<PaddleLine> lines;
//
//   /// Lines Paddle is reasonably sure of, top to bottom.
//   List<PaddleLine> get confidentLines =>
//       lines.where((line) => line.score >= kPaddleMinScore).toList()
//         ..sort((a, b) => a.top.compareTo(b.top));
//
//   /// Everything read, one line each, for showing or speaking when no dish
//   /// card was found.
//   String get text => confidentLines.map((line) => line.text).join('\n');
// }
//
// /// Words that sit on a card but are never its dish name.
// const _cardDetailWords = {
//   'contains',
//   'contain',
//   'vegan',
//   'vegetarian',
//   'gluten',
//   'free',
//   'cal',
//   'cals',
//   'calories',
//   'kcal',
//   'allergen',
//   'allergens',
//   'halal',
//   'kosher',
// };
//
// /// A card title: a short clean line Paddle read with confidence, or one with
// /// a known food word. "Contains: milk", "Cal 60", and glare like "C9ISOO" are
// /// not titles.
// bool _isTitle(PaddleLine line) {
//   final text = line.text;
//   if (text.contains(':') || diningBannerLine.hasMatch(text)) return false;
//   if (diningOcrTitles(text).isNotEmpty) return true;
//   if (line.score < 0.9) return false;
//   final words = text.split(RegExp(r'\s+'));
//   if (words.isEmpty || words.length > 6) return false;
//   final clean = RegExp(r"^[A-Za-z][A-Za-z'&-]*$");
//   if (!words.every(clean.hasMatch)) return false;
//   if (!words.any(
//     (w) => w.length >= 3 && RegExp('[aeiouyAEIOUY]').hasMatch(w),
//   )) {
//     return false;
//   }
//   return !words.every((w) => _cardDetailWords.contains(w.toLowerCase()));
// }
//
// /// Left, front, or right. With several cards, by where each sits among the
// /// cards (two cards side by side are left and right even when both are near
// /// the middle of the photo); a single card by where it sits in the photo.
// String _locationOf(PaddleLine title, List<PaddleLine> titles, double width) {
//   final xs = titles.map((t) => t.centerX);
//   final low = xs.reduce((a, b) => a < b ? a : b);
//   final high = xs.reduce((a, b) => a > b ? a : b);
//   final double x;
//   if (high - low > width * 0.1) {
//     x = (title.centerX - low) / (high - low);
//   } else if (width > 0) {
//     x = title.centerX / width;
//   } else {
//     return '';
//   }
//   if (x < 0.34) return 'to your left';
//   if (x > 0.66) return 'to your right';
//   return 'in front of you';
// }
//
// /// Each dish card Paddle read, as foods with allergens from their Contains
// /// lines. Empty when no card title was found.
// DiningParseResult diningFoodsFromPaddle(PaddleRead read) {
//   final lines = read.confidentLines;
//   final titles = lines.where(_isTitle).toList();
//   if (titles.isEmpty) {
//     return const DiningParseResult(foods: [], error: kDiningParseError);
//   }
//
//   // A detail line belongs to the nearest title above it that it lines up
//   // with: "Cal 60" under "Roasted Brussels Sprouts", not under "Falafel".
//   final details = {for (final title in titles) title: <String>[]};
//   for (final line in lines) {
//     if (titles.contains(line)) continue;
//     PaddleLine? owner;
//     var best = double.infinity;
//     for (final title in titles) {
//       final gap = line.top - title.top;
//       final reach = (title.height <= 0 ? 20 : title.height) * 5;
//       final spread = (title.right - title.left) * 0.75;
//       if (gap < 0 || gap > reach) continue;
//       if (line.centerX < title.left - spread ||
//           line.centerX > title.right + spread) {
//         continue;
//       }
//       if (gap < best) {
//         best = gap;
//         owner = title;
//       }
//     }
//     if (owner != null) details[owner]!.add(line.text);
//   }
//
//   final entries = [
//     for (var i = 0; i < titles.length; i++)
//       {
//         'item_id': '${i + 1}',
//         'dish_name': titles[i].text,
//         'location': _locationOf(titles[i], titles, read.width),
//         'sign_text': [titles[i].text, ...details[titles[i]]!].join('\n'),
//         'information_source': 'sign',
//         'confidence': titles[i].score >= 0.9 ? 'high' : 'medium',
//         'identification_confidence': 0.95,
//         'clearly_visible': true,
//       },
//   ];
//   return parseDiningResponse(
//     jsonEncode({'count': entries.length, 'foods': entries}),
//     requireEvidence: true,
//     ocrText: read.text,
//   );
// }
