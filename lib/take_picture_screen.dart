import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'display_picture_screen.dart';
import 'save_image_stub.dart' if (dart.library.html) 'save_image_web.dart';

late List<CameraDescription> cameras;

Future<void> initCameras() async {
  cameras = await availableCameras();
}

/// Single camera screen for both web and mobile: live camera preview + capture button.
/// On web this uses camera_web for the preview; no file picker.
class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({super.key});

  @override
  State<TakePictureScreen> createState() => _TakePictureScreenState();
}

class _TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isTakingPicture = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (cameras.isEmpty) {
      _error = 'No camera found. Allow camera access and refresh.';
      return;
    }
    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    if (cameras.isNotEmpty) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture || _error != null) return;
    setState(() => _isTakingPicture = true);

    try {
      await _initializeControllerFuture;
      final xFile = await _controller.takePicture();
      final bytes = await xFile.readAsBytes();
      if (bytes.isEmpty || !mounted) return;

      if (kIsWeb) {
        final name = xFile.name.isNotEmpty ? xFile.name : _defaultPhotoName();
        saveImageToDownloads(bytes, name);
      }

      if (!mounted) return;
      await DisplayPictureScreen.push(context, bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTakingPicture = false);
    }
  }

  String _defaultPhotoName() {
    final now = DateTime.now();
    return 'ocr_photo_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.png';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => initCameras().then((_) => setState(() {})),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera'),
        backgroundColor: Colors.black87,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Camera error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() {
                            _initializeControllerFuture = _controller.initialize();
                          }),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                return CameraPreview(_controller);
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 100,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Point at text, then tap the button to take a photo',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        child: _isTakingPicture
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.camera_alt, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
