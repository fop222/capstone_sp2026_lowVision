import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'display_picture_screen.dart';
import 'save_image_stub.dart' if (dart.library.html) 'save_image_web.dart';

/// Web: use camera to take a photo, save to Downloads, then extract text.

Future<void> initCameras() async {}

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({super.key});

  @override
  State<TakePictureScreen> createState() => _TakePictureScreenState();
}

class _TakePictureScreenState extends State<TakePictureScreen> {
  bool _isLoading = false;

  Future<void> _takePhotoAndProcess() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );
      if (xFile == null || !mounted) return;

      final bytes = await xFile.readAsBytes();
      if (bytes.isEmpty || !mounted) return;

      // Save photo to computer's Downloads folder (browser download)
      final name = xFile.name.isNotEmpty ? xFile.name : _defaultPhotoName();
      saveImageToDownloads(bytes, name);

      if (!mounted) return;
      await DisplayPictureScreen.push(context, bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _defaultPhotoName() {
    final now = DateTime.now();
    return 'ocr_photo_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.png';
  }

  Future<void> _pickFromGalleryAndProcess() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (xFile == null || !mounted) return;
      final bytes = await xFile.readAsBytes();
      if (bytes.isEmpty || !mounted) return;
      final name = xFile.name.isNotEmpty ? xFile.name : _defaultPhotoName();
      saveImageToDownloads(bytes, name);
      if (!mounted) return;
      await DisplayPictureScreen.push(context, bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera – take photo for OCR')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Use your device camera to take a photo. The image will be saved to your Downloads folder and text will be extracted.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Text(
                'When you tap below, your browser will ask for camera access.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _takePhotoAndProcess,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(_isLoading ? 'Processing...' : 'Take photo with camera'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  minimumSize: const Size(280, 48),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _isLoading ? null : _pickFromGalleryAndProcess,
                icon: const Icon(Icons.photo_library, size: 20),
                label: const Text('Choose from gallery instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
