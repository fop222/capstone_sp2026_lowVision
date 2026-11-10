// Paddle OCR scan is commented out for now. Uncomment this file to bring it back.

// import 'dart:convert';
//
// import 'package:flutter_test/flutter_test.dart';
// import 'package:my_low_vision_app/dining_food.dart';
// import 'package:my_low_vision_app/dining_paddle.dart';
//
// // Real Paddle OCR (PP-OCRv5 mobile) output for two dining hall photos.
// final _cornbread = jsonEncode({
//   'width': 1500,
//   'height': 2000,
//   'lines': [
//     {
//       'text': 'Buttermilk Cornbread',
//       'score': 0.981,
//       'box': [660, 302, 876, 336],
//     },
//     {
//       'text': 'MCal200',
//       'score': 0.929,
//       'box': [719, 331, 819, 356],
//     },
//     {
//       'text': 'Contains:milk,eggs, wheat,soy bean,gluten',
//       'score': 0.947,
//       'box': [636, 352, 902, 380],
//     },
//     {
//       'text': 'Couueameronpeunu',
//       'score': 0.396,
//       'box': [648, 573, 899, 598],
//     },
//     {
//       'text': '人',
//       'score': 0.733,
//       'box': [734, 602, 748, 614],
//     },
//     {
//       'text': 'C9ISOO',
//       'score': 0.66,
//       'box': [744, 592, 819, 619],
//     },
//     {
//       'text': 'BnfGLwIKCOLUpLe',
//       'score': 0.395,
//       'box': [674, 613, 871, 641],
//     },
//   ],
// });
//
// final _falafel = jsonEncode({
//   'width': 960,
//   'height': 1280,
//   'lines': [
//     {
//       'text': 'Falafel',
//       'score': 0.999,
//       'box': [265, 160, 316, 178],
//     },
//     {
//       'text': 'Roasted Brussels Sprouts',
//       'score': 0.988,
//       'box': [498, 161, 643, 175],
//     },
//     {
//       'text': 'Cal 60',
//       'score': 0.893,
//       'box': [531, 174, 605, 188],
//     },
//     {
//       'text': 'Y',
//       'score': 0.477,
//       'box': [120, 470, 337, 583],
//     },
//   ],
// });
//
// void main() {
//   test('one card: its name and every Contains allergen', () {
//     final result = diningFoodsFromPaddle(PaddleRead.fromJson(_cornbread));
//     final food = result.foods.single;
//     expect(food.dishName, 'Buttermilk Cornbread');
//     expect(food.informationSource, DiningInfoSource.sign);
//     expect(food.location, 'in front of you');
//     expect(
//       food.allergens.map((c) => c.label),
//       containsAll(['Milk (Dairy)', 'Eggs', 'Wheat']),
//     );
//   });
//
//   test('two cards side by side are two foods, left and right', () {
//     final foods = diningFoodsFromPaddle(PaddleRead.fromJson(_falafel)).foods;
//     expect(
//       {for (final f in foods) f.dishName: f.location},
//       {'Falafel': 'to your left', 'Roasted Brussels Sprouts': 'to your right'},
//     );
//     // Calories stay out of names.
//     expect(foods.every((f) => !f.dishName.contains('Cal')), isTrue);
//   });
//
//   test('no card title gives no foods but keeps the text read', () {
//     final read = PaddleRead.fromJson(
//       jsonEncode({
//         'width': 800,
//         'height': 600,
//         'lines': [
//           {
//             'text': 'Contains: milk',
//             'score': 0.95,
//             'box': [10, 10, 200, 30],
//           },
//           {
//             'text': 'Cal 120',
//             'score': 0.9,
//             'box': [10, 40, 120, 60],
//           },
//         ],
//       }),
//     );
//     expect(diningFoodsFromPaddle(read).foods, isEmpty);
//     expect(read.text, 'Contains: milk\nCal 120');
//   });
//
//   test('unreadable output gives no lines', () {
//     expect(PaddleRead.fromJson('not json').lines, isEmpty);
//   });
// }

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Paddle OCR scan is commented out for now',
    () {},
    skip: 'Paddle OCR is turned off',
  );
}
