import 'dart:async';
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
import 'dining_ocr.dart';
import 'dining_results_screen.dart';
import 'grocery_ui.dart';
import 'ocr_config.dart';
import 'take_picture_screen.dart' show backCamerasOnly;

/// One `/predict` call; the Vercel proxy itself gives up at 60 s.
const Duration _kCallTimeout = Duration(seconds: 55);

/// Strips are only started while this much time remains, so a crowded photo
/// adds at most about a minute.
const Duration _kCloserLookBudget = Duration(seconds: 50);

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
  bool _readingLabels = false;
  int _elapsed = 0;

  /// OCR text from the most recent full-photo [_askVlm] call.
  String _lastLabels = '';
  Timer? _progressTimer;
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
    _progressTimer?.cancel();
    _camera?.dispose();
    _tts.stop();
    super.dispose();
  }

  /// Voice setup polls the browser for up to ~1.5 s; do it once per screen.
  late final Future<void> _ttsReady = applyEnglishTts(_tts).catchError((_) {});

  /// Speaks [text]. Never blocks a scan: Android Chrome sometimes never
  /// reports that speech finished, which used to leave "Analyzing foods…" on
  /// screen forever before the photo was even sent.
  Future<void> _speak(String text) async {
    try {
      await _ttsReady.timeout(const Duration(seconds: 3));
      await _tts.speak(text).timeout(const Duration(seconds: 6));
    } catch (error) {
      debugPrint('Dining TTS unavailable or slow: $error');
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
        ResolutionPreset.high,
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
      _elapsed = 0;
    });
    unawaited(_speak('Reading food and drink labels, then identifying items.'));
    // Visible seconds and a periodic spoken update, so a long scan never
    // looks or sounds frozen.
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _elapsed++);
      if (_elapsed % 20 == 0) unawaited(_speak('Still working.'));
    });

    final result = await _runDiningPredict(await shrinkDiningPhoto(bytes));
    _progressTimer?.cancel();
    if (!mounted) return;
    setState(() => _analyzing = false);

    if (!result.isValid) {
      final message = result.error ?? kDiningParseError;
      setState(() => _statusError = message);
      unawaited(_speak(message));
      await _restartCamera();
      return;
    }

    final count = result.foods.length == 1
        ? '1 food'
        : '${result.foods.length} foods';
    unawaited(_speak('Found $count.'));
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
    // Run OCR on this exact image (including a crop) before asking the VLM.
    // Whole-photo labels must never be passed to an unrelated crop.
    final labelText = await _readDiningLabels(bytes, filename);
    _lastLabels = labelText;
    return _askVlmQuestion(bytes, filename, diningPromptWithOcr(labelText));
  }

  /// Posts [question] about [bytes] to `/predict`; null when the server failed.
  Future<String?> _askVlmQuestion(
    Uint8List bytes,
    String filename,
    String question, {
    int maxTokens = kDiningMaxTokens,
  }) async {
    final request = http.MultipartRequest('POST', vlmPredictUri())
      ..files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: filename),
      )
      ..fields['question'] = question
      ..fields['task'] = kDiningVlmTask
      ..fields['max_tokens'] = '$maxTokens';
    // The Vercel proxy stops at 60 s; a normal call takes 5-20 s.
    final response = await request.send().timeout(_kCallTimeout);
    final body = await response.stream.bytesToString().timeout(_kCallTimeout);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(body);
    if (decoded is! Map) return '';
    return (decoded['answer'] as String? ?? '').trim();
  }

  Future<String> _readDiningLabels(Uint8List bytes, String filename) async {
    if (mounted) setState(() => _readingLabels = true);
    final client = http.Client();
    try {
      final request = http.MultipartRequest('POST', ocrMultipartUri())
        ..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: filename),
        );
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return '';
      return diningOcrText(jsonDecode(response.body));
    } catch (error) {
      debugPrint('Dining label OCR unavailable: $error');
      return '';
    } finally {
      client.close();
      if (mounted) setState(() => _readingLabels = false);
    }
  }

  Future<DiningParseResult> _runDiningPredict(Uint8List bytes) async {
    final result = await _runDiningScan(bytes);
    if (!result.isValid) return result;
    // Small print such as "Contains milk" is easy to miss in a whole-photo
    // answer; read the card of any labelled dish that came back without
    // allergens.
    final foods = [...result.foods];
    if (!foods.any(diningNeedsLabelCheck)) return result;
    // Two reads (the photo and an 80% copy); only allergens both find are
    // kept, so a one-off invented allergen is dropped.
    final copy = await rescaleDiningPhoto(bytes, 0.8);
    var checked = 0;
    for (var i = 0; i < foods.length; i++) {
      if (checked >= kDiningLabelCheckLimit) break;
      if (!diningNeedsLabelCheck(foods[i])) continue;
      checked++;
      try {
        final reads = <String>[];
        for (final (image, name) in [
          (bytes, 'dining_label.jpg'),
          (copy, 'dining_label_small.png'),
        ]) {
          final raw = await _askVlmQuestion(
            image,
            name,
            diningLabelPrompt(foods[i].dishName),
            maxTokens: 200,
          );
          if (raw == null) break;
          reads.add(raw);
        }
        if (reads.length == 2) {
          foods[i] = diningFoodWithLabels(foods[i], reads);
        }
      } catch (error) {
        debugPrint('Dining label read failed: $error');
      }
    }
    return DiningParseResult(foods: foods);
  }

  Future<DiningParseResult> _runDiningScan(Uint8List bytes) async {
    try {
      final answer = await _askVlm(bytes, 'dining.jpg');
      if (answer == null) {
        return const DiningParseResult(
          foods: [],
          error:
              'Lumio could not analyze this photo. Please try again or ask dining staff.',
        );
      }
      final full = parseDiningResponse(answer, requireEvidence: true);

      // Drink station: brand labels are logos the regular pass will not
      // name, so ask about the drinks directly.
      if (diningLooksLikeDrinkStation(labels: _lastLabels, answer: answer)) {
        unawaited(_speak('Reading the drink options.'));
        try {
          final raw = await _askVlmQuestion(
            bytes,
            'dining_drinks.jpg',
            kDiningDrinkPrompt,
            maxTokens: 256,
          );
          if (raw != null) {
            final drinks = parseDiningDrinks(raw, alongside: full);
            if (diningDrinksNeedCloserLook(raw)) {
              final closeups = <({String column, String raw})>[];
              try {
                if (mounted) setState(() => _lookingCloser = true);
                final deadline = DateTime.now().add(_kCloserLookBudget);
                for (final strip in await cropDiningStrips(bytes)) {
                  final remaining = deadline.difference(DateTime.now());
                  if (remaining <= Duration.zero) break;
                  final detail = await _askVlmQuestion(
                    strip.png,
                    'drinks_${strip.column}.png',
                    kDiningDrinkPrompt,
                    maxTokens: 256,
                  ).timeout(remaining);
                  if (detail != null && parseDiningDrinks(detail).isValid) {
                    closeups.add((column: strip.column, raw: detail));
                  }
                }
              } catch (error) {
                debugPrint('Dining drink close-up failed: $error');
              }
              // Keep the complete first pass if any region could not be read.
              if (closeups.length == 3) {
                final detailed = parseDiningDrinkStrips(
                  closeups,
                  alongside: full,
                );
                if (detailed.foods.length >= drinks.foods.length) {
                  return detailed;
                }
              }
            }
            if (drinks.foods.length > full.foods.length) return drinks;
          }
        } catch (error) {
          // A failed supplemental pass must not discard the initial result.
          debugPrint('Dining drink scan failed: $error');
        }
      }

      // An empty first answer gets the closer look too: the small model
      // sometimes declines a whole crowded counter but names each part.
      // A counter of printed cards gets the closer look too: on one photo
      // the full view read "Steamed Baked Fish" or "Stuffed Grilled
      // Salmon" across neighbouring cards, while each strip read its cards
      // correctly.
      final labelled = full.foods
          .where((f) => f.informationSource == DiningInfoSource.sign)
          .length;
      if (full.foods.isNotEmpty &&
          labelled < 2 &&
          !diningAnswerLooped(answer) &&
          !diningAnswerIncomplete(answer)) {
        return full;
      }

      // Crowded photo: the model repeated one food instead of naming each
      // pan. Look at the left, center, and right separately.
      if (mounted) setState(() => _lookingCloser = true);
      unawaited(_speak('Looking closer at each part of the photo.'));
      final answers = <({String column, String raw})>[];
      final deadline = DateTime.now().add(_kCloserLookBudget);
      for (final strip in await cropDiningStrips(bytes)) {
        // Out of time: keep what we have rather than make the user wait.
        if (DateTime.now().isAfter(deadline)) break;
        try {
          final raw = await _askVlm(strip.png, 'dining_${strip.column}.png');
          if (raw != null) answers.add((column: strip.column, raw: raw));
        } catch (error) {
          debugPrint('Dining strip ${strip.column} failed: $error');
        }
      }
      final closer = parseDiningStrips(answers, requireEvidence: true);
      // Strips read cards more reliably; prefer them unless they found less.
      return closer.foods.length >= full.foods.length ? closer : full;
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
                  '${_readingLabels
                      ? 'Reading food and drink labels…'
                      : _lookingCloser
                      ? 'Looking closer at each part…'
                      : 'Identifying foods and drinks…'}  ${_elapsed}s',
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
