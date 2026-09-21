/// "Surprise Me!" scanning screen.
///
/// Opens the camera in pantry/fridge mode, lets the user scan as many times
/// as they like, accumulates a deduplicated ingredient list across all scans,
/// then sends the list to Gemini when the user taps "Done Scanning."
/// Detected ingredients are announced via TTS with their on-screen location.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'app_tts.dart';
import 'gemini_service.dart';
import 'grocery_ui.dart';
import 'ocr_config.dart';
import 'surprise_me_state.dart';
import 'take_picture_screen.dart' show backCamerasOnly;

// ─────────────────────────────────────────────────────────────────────────────

class SurpriseMeScanScreen extends StatefulWidget {
  const SurpriseMeScanScreen({super.key});

  @override
  State<SurpriseMeScanScreen> createState() => _SurpriseMeScanScreenState();
}

// ─── State ───────────────────────────────────────────────────────────────────

class _SurpriseMeScanScreenState extends State<SurpriseMeScanScreen> {
  // ── Camera ─────────────────────────────────────────────────────────────────
  CameraController? _camera;
  bool _cameraReady = false;
  bool _takingPicture = false;
  String? _cameraError;

  // ── Scan state ─────────────────────────────────────────────────────────────
  bool _scanning = false;       // VLM request in flight
  bool _generating = false;     // Gemini request in flight
  Uint8List? _previewBytes;     // last captured frame

  // ── Detected ingredients (accumulated across all scans) ────────────────────
  // Map of lowercased name → (display name, location).
  // Using a Map guarantees no duplicate names regardless of how many scans run.
  final Map<String, ({String name, String location})> _detectedMap = {};

  // ── TTS & gallery ──────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  final ImagePicker _picker = ImagePicker();

  // ── VLM prompt ─────────────────────────────────────────────────────────────
  static const _kPrompt =
      'Look carefully at this photo of a refrigerator, pantry, or kitchen cabinet. '
      'List ONLY the food items you can clearly and certainly identify in the image. '
      'Be very conservative — if you are not 100%% sure what an item is, do NOT list it. '
      'For each item write one line in this exact format:  ItemName | region\n'
      'Use one of these nine regions:\n'
      '  top left, top, top right, middle left, middle, middle right, '
      'bottom left, bottom, bottom right\n'
      'Example:\n'
      'Eggs | middle\n'
      'Orange Juice | top right\n'
      'If you cannot confidently identify any food items, write exactly: NONE';

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tts.awaitSpeakCompletion(true);
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _speak(
        'Surprise Me mode. Point your camera at your pantry or refrigerator. '
        'I will detect ingredients and suggest recipes. '
        'Open drawers to check for fruits and vegetables. '
        'Tap Scan when ready.',
      );
    });
  }

  @override
  void dispose() {
    _camera?.dispose();
    _tts.stop();
    super.dispose();
  }

  // ── Camera helpers ──────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final all = await availableCameras();
      final cams = backCamerasOnly(all);
      if (cams.isEmpty) {
        setState(() => _cameraError = 'No camera found.');
        return;
      }
      final ctrl = CameraController(
        cams.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _camera = ctrl;
        _cameraReady = true;
        _cameraError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
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
    if (_camera == null || !_cameraReady || _takingPicture) return null;
    setState(() => _takingPicture = true);
    try {
      final xFile = await _camera!.takePicture();
      return await xFile.readAsBytes();
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Capture error: $e');
      return null;
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  Future<Uint8List?> _pickFromGallery() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return null;
    return xFile.readAsBytes();
  }

  // ── VLM ─────────────────────────────────────────────────────────────────────
  Future<String> _runVlmPredict(Uint8List bytes) async {
    try {
      final req = http.MultipartRequest('POST', vlmPredictUri())
        ..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: 'img.png'),
        )
        ..fields['question'] = _kPrompt;
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) return '';
      final decoded = json.decode(body) as Map<String, dynamic>;
      return (decoded['answer'] as String? ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  /// Parses "ItemName | region" lines from [answer].
  /// Filters out any line whose name is "none", "not found", or blank.
  List<({String name, String location})> _parseItems(String answer) {
    final upper = answer.trim().toUpperCase();
    if (upper == 'NONE' ||
        upper.startsWith('NONE\n') ||
        upper.startsWith('NOT FOUND')) return [];

    // Words that the VLM uses when it found nothing — never show as food items.
    const _kJunkNames = {
      'none', 'not found', 'none found', 'no items', 'no items found',
      'n/a', 'nothing', 'unknown',
    };

    final results = <({String name, String location})>[];
    for (final raw in answer.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      String name;
      String location = '';
      if (line.contains('|')) {
        final parts = line.split('|');
        name = parts[0]
            .trim()
            .replaceFirst(RegExp(r'^[\d\.\-\*\•]+\s*'), '');
        location = parts[1].trim().toLowerCase();
      } else {
        name = line.replaceFirst(RegExp(r'^[\d\.\-\*\•]+\s*'), '').trim();
      }
      if (name.isEmpty) continue;
      // Skip junk / placeholder names.
      if (_kJunkNames.contains(name.toLowerCase())) continue;
      // Capitalise first letter.
      name = name[0].toUpperCase() + name.substring(1);
      results.add((name: name, location: location));
    }
    return results;
  }

  // ── Scan action ──────────────────────────────────────────────────────────────
  Future<void> _onScan({bool fromGallery = false}) async {
    if (_scanning || _generating) return;

    final bytes =
        fromGallery ? await _pickFromGallery() : await _capturePhoto();
    if (bytes == null) return;

    // Stop live preview while processing.
    await _camera?.dispose();
    if (mounted) {
      setState(() {
        _camera = null;
        _cameraReady = false;
        _previewBytes = bytes;
        _scanning = true;
      });
    }

    await _speak('Scanning.');

    final answer = await _runVlmPredict(bytes);
    final parsed = _parseItems(answer);

    // Find genuinely new items — the Map key guarantees no duplicates
    // both within this scan and across all previous scans.
    final newItems = <({String name, String location})>[];
    for (final p in parsed) {
      final key = p.name.toLowerCase();
      if (!_detectedMap.containsKey(key)) {
        _detectedMap[key] = p;
        newItems.add(p);
      }
    }

    if (!mounted) return;
    setState(() {
      _scanning = false;
      // newItems were already inserted into _detectedMap above.
    });

    if (newItems.isEmpty) {
      await _speak('No new items detected. Try a different angle or area.');
    } else {
      // Announce each new item with its location.
      for (final item in newItems) {
        final loc = item.location.isNotEmpty ? ' at the ${item.location}' : '';
        await _speak('${item.name} detected$loc.');
      }
    }

    // Restart camera for the next scan.
    await _restartCamera();
  }

  // ── Done Scanning ────────────────────────────────────────────────────────────
Future<void> _onDoneScanning() async {
  if (_generating) return;

  if (_detectedMap.isEmpty) {
    await _speak(
      'No ingredients detected yet. '
      'Please scan your pantry or fridge first.',
    );
    return;
  }

  // Show the loading screen
  setState(() => _generating = true);

  // Don't await TTS here.
  // If TTS gets stuck, it would otherwise prevent Gemini from running.
  _speak('Generating recipe suggestions. Please wait.');

  try {
    final names = _detectedMap.values
        .map((d) => d.name)
        .toList();

    print('[Surprise Me] Detected ingredients: $names');
    print('[Surprise Me] Calling Gemini...');

    final recipes = await generateRecipeSuggestions(names);

    print('[Surprise Me] Gemini returned ${recipes.length} recipes');

    if (!mounted) return;

    // Stop the loading screen no matter what Gemini returned.
    setState(() => _generating = false);

    if (recipes.isEmpty) {
      print('[Surprise Me] No recipes were generated.');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'I could not generate recipes right now. '
            'Please try again.',
          ),
          duration: Duration(seconds: 4),
        ),
      );

      return;
    }

    print('[Surprise Me] Recipes generated successfully.');

    // Save the recipes so the recipe screen can display them.
    setRecommendedRecipes(recipes);

    // Leave the scanning screen.
    if (mounted) {
      Navigator.of(context).pop();
    }
  } catch (e, stackTrace) {
    print('[Surprise Me] ERROR: $e');
    print(stackTrace);

    if (!mounted) return;

    // Make absolutely sure the loading screen goes away.
    setState(() => _generating = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Something went wrong while generating recipes: $e',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

  // ── TTS helper ───────────────────────────────────────────────────────────────
  Future<void> _speak(String text) async {
    await applyEnglishTts(_tts);
    await _tts.speak(text);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Surprise Me!',
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: (_scanning || _generating) ? null : _onDoneScanning,
            child: Text(
              'Done Scanning',
              style: TextStyle(
                color: (_scanning || _generating)
                    ? Colors.white38
                    : kBrandPurpleLight,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Camera / preview area ──────────────────────────────────────────
          Expanded(
            flex: 3,
            child: _buildCameraArea(),
          ),

          // ── Detected ingredients panel ─────────────────────────────────────
          Expanded(
            flex: 2,
            child: _buildDetectedPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraArea() {
    if (_generating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kBrandPurpleLight),
            SizedBox(height: 16),
            Text(
              'Finding recipes for you…',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_scanning) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_previewBytes != null)
            Image.memory(_previewBytes!, fit: BoxFit.cover),
          const ColoredBox(color: Color(0x88000000)),
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: kBrandPurpleLight),
                SizedBox(height: 12),
                Text(
                  'Detecting ingredients…',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _cameraError!,
            style: const TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!_cameraReady || _camera == null) {
      return const Center(
        child: CircularProgressIndicator(color: kBrandPurpleLight),
      );
    }

    return ClipRect(child: CameraPreview(_camera!));
  }

  Widget _buildDetectedPanel() {
    return Container(
      color: const Color(0xFF12102A),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header + scan buttons ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  _detectedMap.isEmpty
                      ? 'Detected Ingredients'
                      : 'Detected (${_detectedMap.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Ingredient chips (scrollable) ────────────────────────────────
          Expanded(
            child: _detectedMap.isEmpty
                ? const Center(
                    child: Text(
                      'No ingredients detected yet.\nPoint camera at your pantry or fridge.',
                      style: TextStyle(color: Colors.white54, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  )
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final item in _detectedMap.values)
                          _IngredientChip(
                            name: item.name,
                            location: item.location,
                          ),
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 10),

          // ── Action buttons ───────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _ScanButton(
                  label: 'Scan',
                  onTap: (_scanning || _generating) ? null : () => _onScan(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ScanButton(
                  label: 'Use Gallery',
                  onTap: (_scanning || _generating)
                      ? null
                      : () => _onScan(fromGallery: true),
                  outlined: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── _IngredientChip ──────────────────────────────────────────────────────────

class _IngredientChip extends StatelessWidget {
  const _IngredientChip({required this.name, required this.location});
  final String name;
  final String location;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kBrandPurpleLight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: kBrandPurpleLight.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (location.isNotEmpty)
            Text(
              location,
              style: TextStyle(
                color: kBrandPurpleLight.withValues(alpha: 0.9),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── _ScanButton ──────────────────────────────────────────────────────────────

class _ScanButton extends StatelessWidget {
  const _ScanButton({
    required this.label,
    required this.onTap,
    this.outlined = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 60,
        decoration: BoxDecoration(
          color: outlined
              ? Colors.transparent
              : (onTap == null
                  ? kBrandPurpleMid.withValues(alpha: 0.3)
                  : kBrandPurpleMid),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: onTap == null
                ? Colors.white12
                : kBrandPurpleLight.withValues(alpha: 0.7),
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null ? Colors.white30 : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }
}
