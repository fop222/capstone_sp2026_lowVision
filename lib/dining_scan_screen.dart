import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'app_tts.dart';
import 'dining_food.dart';
import 'dining_image_strips.dart';
import 'dining_results_screen.dart';
import 'grocery_ui.dart';
import 'ocr_config.dart';
import 'take_picture_screen.dart' show backCamerasOnly;

/// Captures or uploads one dining photo and sends it through `/predict`.
class DiningScanScreen extends StatefulWidget {
  const DiningScanScreen({super.key});

  @override
  State<DiningScanScreen> createState() => _DiningScanScreenState();
}

class _DiningScanScreenState extends State<DiningScanScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _takingPicture = false;
  bool _analyzing = false;
  bool _lookingCloser = false;
  String? _cameraError;
  String? _statusError;
  Uint8List? _previewBytes;

  final FlutterTts _tts = FlutterTts();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak(
        'Dining scan. Point your camera at the buffet, plate, or tray. '
        'Then take a photo or upload an image.',
      );
    });
  }

  @override
  void dispose() {
    _camera?.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    try {
      await applyEnglishTts(_tts);
      await _tts.speak(text);
    } catch (error) {
      debugPrint('Dining TTS unavailable: $error');
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = backCamerasOnly(await availableCameras());
      if (cams.isEmpty) {
        if (!mounted) return;
        setState(
          () => _cameraError = 'No camera found. You can still upload a photo.',
        );
        return;
      }
      final controller = CameraController(
        cams.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraReady = true;
        _cameraError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _cameraError = 'Camera unavailable. You can still upload a photo.',
      );
      debugPrint('Dining camera error: $error');
    }
  }

  Future<void> _restartCamera() async {
    await _camera?.dispose();
    if (!mounted) return;
    setState(() {
      _camera = null;
      _cameraReady = false;
      _previewBytes = null;
    });
    await _initCamera();
  }

  Future<Uint8List?> _capturePhoto() async {
    final camera = _camera;
    if (camera == null || !_cameraReady || _takingPicture) return null;
    setState(() => _takingPicture = true);
    try {
      final file = await camera.takePicture();
      return await file.readAsBytes();
    } catch (error) {
      if (mounted) {
        setState(
          () => _statusError = 'Could not take a photo. Please try again.',
        );
      }
      debugPrint('Dining capture error: $error');
      return null;
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  Future<Uint8List?> _pickFromGallery() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return null;
      return await file.readAsBytes();
    } catch (error) {
      if (mounted) {
        setState(
          () => _statusError = 'Could not open your photos. Please try again.',
        );
      }
      debugPrint('Dining gallery error: $error');
      return null;
    }
  }

  Future<void> _analyze({required bool fromGallery}) async {
    if (_analyzing) return;
    final bytes = fromGallery
        ? await _pickFromGallery()
        : await _capturePhoto();
    if (bytes == null || !mounted) return;

    await _camera?.dispose();
    if (!mounted) return;
    setState(() {
      _camera = null;
      _cameraReady = false;
      _previewBytes = bytes;
      _analyzing = true;
      _lookingCloser = false;
      _statusError = null;
    });
    await _speak('Analyzing foods.');

    final result = await _runDiningPredict(bytes);
    if (!mounted) return;
    setState(() => _analyzing = false);

    if (!result.isValid) {
      final message = result.error ?? kDiningParseError;
      setState(() => _statusError = message);
      await _speak(message);
      await _restartCamera();
      return;
    }

    final count = result.foods.length == 1
        ? '1 food'
        : '${result.foods.length} foods';
    await _speak('Found $count.');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DiningResultsScreen(foods: result.foods, photoBytes: bytes),
      ),
    );
    if (mounted) await _restartCamera();
  }

  /// Sends one image to `/predict` and returns the model's answer text, or
  /// null when the server failed.
  Future<String?> _askVlm(Uint8List bytes, String filename) async {
    final request = http.MultipartRequest('POST', vlmPredictUri())
      ..files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: filename),
      )
      ..fields['question'] = kDiningVlmPrompt
      ..fields['task'] = kDiningVlmTask
      ..fields['max_tokens'] = '$kDiningMaxTokens';
    final response = await request.send().timeout(const Duration(seconds: 90));
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(body);
    if (decoded is! Map) return '';
    return (decoded['answer'] as String? ?? '').trim();
  }

  Future<DiningParseResult> _runDiningPredict(Uint8List bytes) async {
    try {
      final answer = await _askVlm(bytes, 'dining.jpg');
      if (answer == null) {
        return const DiningParseResult(
          foods: [],
          error:
              'Lumio could not analyze this photo. Please try again or ask dining staff.',
        );
      }
      final full = parseDiningResponse(answer);
      if (!diningAnswerLooped(answer)) return full;

      // Crowded photo: the model repeated one food instead of naming each
      // pan. Look at the left, center, and right separately.
      if (mounted) setState(() => _lookingCloser = true);
      await _speak('Looking closer at each part of the photo.');
      final answers = <({String column, String raw})>[];
      for (final strip in await cropDiningStrips(bytes)) {
        final raw = await _askVlm(strip.png, 'dining_${strip.column}.png');
        if (raw != null) answers.add((column: strip.column, raw: raw));
      }
      final closer = parseDiningStrips(answers);
      return closer.foods.length > full.foods.length ? closer : full;
    } catch (error) {
      debugPrint('Dining predict error: $error');
      return const DiningParseResult(
        foods: [],
        error:
            'Lumio could not reach the scan service. Please try again or ask dining staff.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Buffet / Food'),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(flex: 3, child: _buildPreview()),
          Expanded(flex: 2, child: _buildControls()),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_analyzing) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_previewBytes != null)
            Image.memory(_previewBytes!, fit: BoxFit.cover),
          const ColoredBox(color: Color(0xAA000000)),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: kBrandPurpleLight),
                const SizedBox(height: 16),
                Text(
                  _lookingCloser
                      ? 'Looking closer at each part…'
                      : 'Analyzing foods…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_cameraReady && _camera != null) {
      return ClipRect(child: CameraPreview(_camera!));
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _cameraError ?? 'Starting camera…',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final busy = _analyzing || _takingPicture;
    return Container(
      color: const Color(0xFF12102A),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Whole-room shots make the model guess at food it cannot see;
          // pans that fill the frame are named far more accurately.
          const Text(
            'Stand at the counter so the food fills the photo. Include any signs.',
            style: TextStyle(color: Colors.white, fontSize: 20, height: 1.3),
          ),
          if (_statusError != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                _statusError!,
                style: const TextStyle(
                  color: Color(0xFFFF8C5A),
                  fontSize: 20,
                  height: 1.3,
                ),
              ),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Take Photo',
                  onPressed: busy || !_cameraReady
                      ? null
                      : () => _analyze(fromGallery: false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: 'Upload Image',
                  outlined: true,
                  onPressed: busy ? null : () => _analyze(fromGallery: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        height: 60,
        child: outlined
            ? OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: enabled ? Colors.white : Colors.white30,
                  side: BorderSide(
                    color: enabled ? kBrandPurpleLight : Colors.white12,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(label, textAlign: TextAlign.center),
              )
            : ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: enabled
                      ? kBrandPurpleMid
                      : kBrandPurpleMid.withValues(alpha: 0.35),
                  foregroundColor: enabled ? Colors.white : Colors.white30,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(label, textAlign: TextAlign.center),
              ),
      ),
    );
  }
}
