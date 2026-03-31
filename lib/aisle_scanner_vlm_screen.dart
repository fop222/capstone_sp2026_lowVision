import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'main.dart';
import 'ocr_config.dart';

class _Item {
  final String id;
  final String name;
  final String category;
  bool isChecked;
  int? aisle;

  _Item({
    required this.id,
    required this.name,
    required this.category,
    required this.isChecked,
    this.aisle,
  });

  static _Item fromMap(Map<String, dynamic> m) => _Item(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        category: m['category'] as String? ?? 'Other',
        isChecked: m['is_checked'] as bool? ?? false,
      );
}

enum _Phase { aisleSign, aisleResults, shelf, shelfResults }

class AisleScannerVlmScreen extends StatefulWidget {
  final String listId;
  final String listTitle;
  final List<Map<String, dynamic>> items;
  final List<CameraDescription> cameras;

  const AisleScannerVlmScreen({
    super.key,
    required this.listId,
    required this.listTitle,
    required this.items,
    required this.cameras,
  });

  @override
  State<AisleScannerVlmScreen> createState() => _AisleScannerVlmScreenState();
}

class _AisleScannerVlmScreenState extends State<AisleScannerVlmScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _takingPicture = false;
  String? _cameraError;
  int _cameraIndex = 0;

  final FlutterTts _tts = FlutterTts();
  final ImagePicker _picker = ImagePicker();

  _Phase _phase = _Phase.aisleSign;
  int _currentAisle = 1;
  String _currentAisleLabel = '1';

  bool _loading = false;
  String? _error;

  String _aisleOcrText = '';
  String _aisleStatusMessage = '';
  String _shelfOcrText = '';
  String _shelfStatusMessage = '';
  String _vlmAnswer = '';
  Uint8List? _lastShelfImageBytes;
  String _lastSpoken = '';

  List<_Item> _aisleMatches = [];
  List<_Item> _shelfMatches = [];
  List<_Item> _pendingShelfItems = [];
  int _shelfPromptIndex = 0;

  late List<_Item> _items;
  late final Map<String, bool> _initialCheckedById;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map(_Item.fromMap).toList();
    _initialCheckedById = {for (final item in _items) item.id: item.isChecked};
    _tts.awaitSpeakCompletion(true);
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _speak(
        'VLM shopping mode started for ${widget.listTitle}. Point your camera at the aisle sign and tap Scan Aisle Sign.',
      );
    });
  }

  @override
  void dispose() {
    _camera?.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() => _cameraError = 'No camera found.');
      return;
    }

    final ctrl = CameraController(
      widget.cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _camera = ctrl;
        _cameraReady = true;
        _cameraError = null;
      });
    } catch (e) {
      setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _restartCamera() async {
    await _camera?.dispose();
    _camera = null;
    _cameraReady = false;
    await _initCamera();
  }

  Future<void> _flipCamera() async {
    if (widget.cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;
    await _restartCamera();
  }

  Future<Uint8List?> _capturePhoto() async {
    if (_camera == null || !_cameraReady || _takingPicture) return null;
    setState(() => _takingPicture = true);
    try {
      final xFile = await _camera!.takePicture();
      return await xFile.readAsBytes();
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
      return null;
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  Future<Uint8List?> _pickFromGallery() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return null;
    return await xFile.readAsBytes();
  }

  Future<String?> _runOcr(Uint8List bytes) async {
    try {
      final req = http.MultipartRequest('POST', ocrMultipartUri())
        ..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: 'img.png'),
        );

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200) {
        final data = json.decode(body) as Map<String, dynamic>;
        return (data['full_text'] as String?)?.trim() ?? '';
      }

      setState(() => _error = 'OCR server error ${res.statusCode}.');
      return null;
    } catch (_) {
      setState(() => _error =
          'Cannot reach OCR service at ${ocrServiceBaseUrl()}.');
      return null;
    }
  }

  Future<String> _runVlmPredict(
    Uint8List bytes, {
    required String question,
  }) async {
    try {
      final req = http.MultipartRequest('POST', vlmPredictUri())
        ..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: 'img.png'),
        )
        ..fields['question'] = question;

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode != 200) {
        // Surface server errors instead of swallowing them.
        try {
          final decoded = json.decode(body);
          if (decoded is Map<String, dynamic> && decoded['error'] is String) {
            return 'VLM server error ${res.statusCode}: ${decoded['error']}';
          }
        } catch (_) {}
        final snippet = body.trim();
        return snippet.isEmpty
            ? 'VLM server error ${res.statusCode}.'
            : 'VLM server error ${res.statusCode}: $snippet';
      }

      final decoded = json.decode(body) as Map<String, dynamic>;
      final answer = (decoded['answer'] as String? ?? '').trim();
      return answer.isEmpty ? 'VLM returned an empty answer.' : answer;
    } catch (e) {
      return 'VLM request failed: $e';
    }
  }

  bool _vlmSaysItemFound(String answer) {
    final upper = answer.toUpperCase();
    // Important: "ITEM NOT FOUND" contains the substring "ITEM FOUND".
    if (upper.contains('ITEM NOT FOUND')) return false;
    return RegExp(r'\bITEM FOUND\b').hasMatch(upper);
  }

  bool _vlmAnswerMatchesTarget(String answer, _Item target) {
    final answerWords = _tokenize(answer);
    final targetWords = _tokenize(target.name);
    for (final t in targetWords) {
      if (answerWords.any((w) => _isFuzzyTokenMatch(t, w))) return true;
    }
    return false;
  }

  String _normalizeToken(String token) {
    final lower = token.toLowerCase();
    final normalized = lower
        .replaceAll('0', 'o')
        .replaceAll('1', 'l')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('7', 't')
        .replaceAll(r'$', 's');

    if (normalized.length > 3 && normalized.endsWith('s')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Set<String> _tokenize(String text) {
    return text
        .split(RegExp(r'[^A-Za-z0-9$]+'))
        .map(_normalizeToken)
        .where((w) => w.length > 2)
        .toSet();
  }

  bool _looksLikeUsefulAisleText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final letterCount = RegExp(r'[A-Za-z]').allMatches(trimmed).length;
    if (letterCount < 3) return false;
    final tokens = _tokenize(trimmed);
    return tokens.isNotEmpty;
  }

  int _levenshteinDistance(String a, String b, {int maxDistance = 2}) {
    if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      int minInRow = curr[0];
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,
          curr[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        if (curr[j] < minInRow) minInRow = curr[j];
      }
      if (minInRow > maxDistance) return maxDistance + 1;
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[b.length];
  }

  bool _isFuzzyTokenMatch(String target, String candidate) {
    if (target == candidate) return true;
    if (target[0] != candidate[0]) return false;
    final maxDistance = target.length >= 10 || candidate.length >= 10 ? 2 : 1;
    return _levenshteinDistance(target, candidate, maxDistance: maxDistance) <=
        maxDistance;
  }

  bool _itemMatchesText(_Item item, Set<String> words) {
    final itemWords = {..._tokenize(item.name), ..._tokenize(item.category)};
    for (final target in itemWords) {
      if (words.any((word) => _isFuzzyTokenMatch(target, word))) {
        return true;
      }
    }
    return false;
  }

  List<_Item> _matchItems(String text) {
    final words = _tokenize(text);
    return _items.where((item) {
      if (item.isChecked) return false;
      return _itemMatchesText(item, words);
    }).toList();
  }

  _Item? get _currentShelfTarget {
    if (_pendingShelfItems.isEmpty) return null;
    if (_shelfPromptIndex < 0 || _shelfPromptIndex >= _pendingShelfItems.length) {
      return null;
    }
    return _pendingShelfItems[_shelfPromptIndex];
  }

  Future<void> _onScanAisleSign({bool fromGallery = false}) async {
    final Uint8List? bytes =
        fromGallery ? await _pickFromGallery() : await _capturePhoto();
    if (bytes == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    await _speak('Reading aisle sign.');

    final text = await _runOcr(bytes);

    setState(() => _loading = false);

    if (text == null) {
      await _speak('Could not read the sign. Please try again.');
      return;
    }

    _aisleOcrText = text;

    if (!_looksLikeUsefulAisleText(text)) {
      setState(() {
        _phase = _Phase.aisleSign;
        _aisleStatusMessage = 'Sign text unclear. Retake aisle sign photo.';
      });
      await _speak(
        'This aisle sign image is unclear. Please go closer and retake the photo.',
      );
      return;
    }

    _aisleMatches = _matchItems(text);
    _pendingShelfItems = _aisleMatches.where((i) => !i.isChecked).toList();
    _shelfPromptIndex = 0;

    for (final item in _aisleMatches) {
      item.aisle ??= _currentAisle;
    }

    setState(() {
      _phase = _Phase.aisleResults;
      _aisleStatusMessage = _aisleMatches.isEmpty
          ? 'No list items match this aisle.'
          : 'Matched items: ${_aisleMatches.map((e) => e.name).join(", ")}';
    });

    await _speak(_aisleStatusMessage);
  }

  Future<void> _onGoToShelf() async {
    setState(() {
      _phase = _Phase.shelf;
      _shelfStatusMessage = '';
      _shelfOcrText = '';
      _vlmAnswer = '';
      _shelfMatches = [];
    });

    await _restartCamera();

    final target = _currentShelfTarget;
    if (target != null) {
      await _speak(
        'Point your camera at the shelf for ${target.name}, then tap Scan Shelf.',
      );
    } else {
      await _speak('Point your camera at the shelf, then tap Scan Shelf.');
    }
  }

  Future<void> _onScanShelf({bool fromGallery = false}) async {
    final Uint8List? bytes =
        fromGallery ? await _pickFromGallery() : await _capturePhoto();
    if (bytes == null) return;
    _lastShelfImageBytes = bytes;

    setState(() {
      _loading = true;
      _error = null;
    });

    await _speak('Reading shelf.');

    final shelfText = await _runOcr(bytes);
    final target = _currentShelfTarget;

    String question;
    if (target != null) {
      question =
          'Do NOT read any text, labels, or signs. Use only visual appearance. '
          'First, describe what grocery item you see concisely (1–2 sentences). '
          'Then, say whether the described item matches "${target.name}". '
          'If it matches, end with: ITEM FOUND.';
    } else {
      question =
          'Do NOT read any text, labels, or signs. Use only visual appearance. '
          'Describe the main grocery item(s) you see concisely for a low-vision user.';
    }

    final vlmAnswer = await _runVlmPredict(bytes, question: question);

    setState(() => _loading = false);

    if (shelfText == null) {
      await _speak('Could not read the shelf text. Please try again.');
      return;
    }

    _shelfOcrText = shelfText;
    _vlmAnswer = vlmAnswer;
    _shelfMatches = _matchItems(shelfText);

    final matchedNames = _shelfMatches.map((i) => i.name).join(', ');
    final targetFound = target != null &&
        (_vlmSaysItemFound(vlmAnswer) ||
            _vlmAnswerMatchesTarget(vlmAnswer, target));

    setState(() {
      if (matchedNames.isEmpty) {
        _shelfStatusMessage = vlmAnswer.isEmpty
            ? 'VLM detected: nothing clear.'
            : 'VLM detected: $vlmAnswer';
      } else {
        _shelfStatusMessage = vlmAnswer.isEmpty
            ? 'Detected list matches: $matchedNames'
            : 'Detected list matches: $matchedNames. VLM detected: $vlmAnswer';
      }
      _phase = _Phase.shelfResults;
    });

    await _speak(_shelfStatusMessage);

    if (target != null && targetFound) {
      setState(() {
        target.isChecked = true;
      });
      await _saveItemCheckedState(target);
      await _speak('Item found. ${target.name} checked off.');
    }
  }

  Future<void> _onTryWithVlm() async {
    final bytes = _lastShelfImageBytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan or upload a shelf image first.')),
      );
      return;
    }

    final target = _currentShelfTarget;
    final question = target != null
        ? 'Do NOT read any text, labels, or signs. Use only visual appearance. '
            'First, describe what grocery item you see concisely (1–2 sentences). '
            'Then, say whether the described item matches "${target.name}". '
            'If it matches, end with: ITEM FOUND.'
        : 'Do NOT read any text, labels, or signs. Use only visual appearance. '
            'Describe the main grocery item(s) you see concisely for a low-vision user.';

    setState(() => _loading = true);
    final answer = await _runVlmPredict(bytes, question: question);
    setState(() {
      _loading = false;
      _vlmAnswer = answer.isEmpty ? 'No VLM answer returned.' : answer;
    });

    if (target != null &&
        (_vlmSaysItemFound(answer) ||
            _vlmAnswerMatchesTarget(answer, target))) {
      setState(() => target.isChecked = true);
      await _saveItemCheckedState(target);
      await _speak('Item found. ${target.name} checked off.');
    }
  }

  Future<void> _onNextAisle() async {
    setState(() {
      _currentAisle++;
      _currentAisleLabel = _currentAisle.toString();
      _phase = _Phase.aisleSign;
      _aisleOcrText = '';
      _aisleStatusMessage = '';
      _shelfOcrText = '';
      _shelfStatusMessage = '';
      _vlmAnswer = '';
      _aisleMatches = [];
      _shelfMatches = [];
      _pendingShelfItems = [];
      _shelfPromptIndex = 0;
    });

    await _restartCamera();
    await _speak(
      'Moving to aisle $_currentAisleLabel. Point at the aisle sign and tap Scan Aisle Sign.',
    );
  }

  Future<void> _toggleItem(_Item item) async {
    setState(() => item.isChecked = !item.isChecked);
    await _saveItemCheckedState(item);
    await _speak(
      item.isChecked ? '${item.name} checked off.' : '${item.name} unchecked.',
    );
  }

  Future<void> _saveItemCheckedState(_Item item) async {
    if (item.id.isEmpty) return;
    try {
      await supabase
          .from('grocery_items')
          .update({'is_checked': item.isChecked})
          .eq('id', item.id)
          .eq('list_id', widget.listId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save "${item.name}".')),
      );
    }
  }

  Future<void> _saveAllProgress() async {
    for (final item in _items) {
      final initial = _initialCheckedById[item.id];
      if (initial != null && initial != item.isChecked) {
        await _saveItemCheckedState(item);
      }
    }
  }

  Future<void> _onEndShopping() async {
    setState(() => _loading = true);
    await _saveAllProgress();
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _speak(String text) async {
    if (mounted) {
      setState(() => _lastSpoken = text);
    } else {
      _lastSpoken = text;
    }
    await _tts.speak(text);
  }

  Widget _spokenPanel(BuildContext context) {
    final spoken = _lastSpoken.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Speaking:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            spoken.isEmpty ? '—' : spoken,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  List<_Item> get _uncheckedSorted {
    final withAisle = _items.where((i) => !i.isChecked && i.aisle != null).toList()
      ..sort((a, b) => a.aisle!.compareTo(b.aisle!));
    final noAisle = _items.where((i) => !i.isChecked && i.aisle == null).toList();
    return [...withAisle, ...noAisle];
  }

  @override
  Widget build(BuildContext context) {
    final title = _phase == _Phase.aisleSign
        ? 'VLM Aisle $_currentAisleLabel — Scan Sign'
        : _phase == _Phase.shelf
            ? 'VLM Aisle $_currentAisleLabel — Scan Shelf'
            : 'VLM Aisle $_currentAisleLabel';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'End shopping',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: _loading ? null : _onEndShopping,
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ],
      ),
      endDrawer: _buildListDrawer(),
      body: _phase == _Phase.aisleSign || _phase == _Phase.shelf
          ? _buildCameraView()
          : _phase == _Phase.aisleResults
              ? _buildAisleResults()
              : _buildShelfResults(),
    );
  }

  Widget _buildCameraView() {
    final isAisle = _phase == _Phase.aisleSign;
    final target = _currentShelfTarget;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_cameraError != null)
                Center(child: Text(_cameraError!))
              else if (!_cameraReady)
                const Center(child: CircularProgressIndicator())
              else
                CameraPreview(_camera!),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    isAisle
                        ? 'Point at the aisle sign'
                        : target != null
                            ? 'Point at shelf for ${target.name}'
                            : 'Point at the shelf',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
              ),

              Positioned(
                top: 75,
                right: 12,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: _flipCamera,
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                  ),
                ),
              ),

              if (_loading)
                Container(
                  color: Colors.black54,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isAisle ? _onScanAisleSign : _onScanShelf,
                      child: Text(isAisle ? 'Scan Aisle Sign' : 'Scan Shelf'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => isAisle
                          ? _onScanAisleSign(fromGallery: true)
                          : _onScanShelf(fromGallery: true),
                      child: const Text('Use Gallery Image'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAisleResults() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _spokenPanel(context),
          const SizedBox(height: 16),
          Text(
            _aisleStatusMessage,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: _aisleMatches
                  .map(
                    (item) => CheckboxListTile(
                      value: item.isChecked,
                      onChanged: (_) => _toggleItem(item),
                      title: Text(item.name),
                      subtitle: Text(item.category),
                    ),
                  )
                  .toList(),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _onGoToShelf,
                  child: const Text('Go To Shelf Scan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _onNextAisle,
                  child: const Text('Next Aisle'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShelfResults() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              children: [
                _spokenPanel(context),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _onTryWithVlm,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Try with VLM'),
                ),
                const SizedBox(height: 16),
                ..._uncheckedSorted.map(
                  (item) => CheckboxListTile(
                    value: item.isChecked,
                    onChanged: (_) => _toggleItem(item),
                    title: Text(item.name),
                    subtitle: Text(item.category),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _onGoToShelf,
                  child: const Text('Scan Another Shelf'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _onNextAisle,
                  child: const Text('Next Aisle'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: Text(
                widget.listTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              subtitle: const Text('Shopping list'),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: _items
                    .map(
                      (item) => CheckboxListTile(
                        value: item.isChecked,
                        onChanged: (_) => _toggleItem(item),
                        title: Text(item.name),
                        subtitle: Text(item.category),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}