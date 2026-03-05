import 'package:flutter/material.dart';

import 'take_picture_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Low Vision OCR',
      home: const TakePictureScreen(),
    );
  }
}
