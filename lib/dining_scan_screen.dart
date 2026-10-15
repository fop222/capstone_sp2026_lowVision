import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'app_tts.dart';
import 'dining_food.dart';
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

  Future<DiningParseResult> _runDiningPredict(Uint8List bytes) async {
    try {
      final request = http.MultipartRequest('POST', vlmPredictUri())
        ..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: 'dining.jpg'),
        )
        ..fields['question'] = kDiningVlmPrompt
        ..fields['task'] = kDiningVlmTask
        ..fields['max_tokens'] = '$kDiningMaxTokens';
      final response = await request.send().timeout(
        const Duration(seconds: 90),
      );
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200) {
        return const DiningParseResult(
          foods: [],
          error:
              'Lumio could not analyze this photo. Please try again or ask dining staff.',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const DiningParseResult(foods: [], error: kDiningParseError);
      }
      final answer = (decoded['answer'] as String? ?? '').trim();
      if (answer.isEmpty) {
        return const DiningParseResult(foods: [], error: kDiningParseError);
      }
      return parseDiningResponse(answer);
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
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: kBrandPurpleLight),
                SizedBox(height: 16),
                Text(
                  'Analyzing foods…',
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
          const Text(
            'Include the foods and any signs in the frame.',
            style: TextStyle(color: Colors.white, fontSize: 20, height: 1.3),
          ),
          if (_statusError != null) ...[
            const SizedBox(height: 10),
            Text(
              _statusError!,
              style: const TextStyle(
                color: Color(0xFFFF8C5A),
                fontSize: 18,
                height: 1.3,
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
