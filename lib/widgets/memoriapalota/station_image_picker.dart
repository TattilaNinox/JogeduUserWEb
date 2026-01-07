import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:typed_data';
import 'dart:async';

/// Képválasztó dialógus a memóriapalota állomásokhoz
///
/// Lehetőséget ad:
/// - Kamera használatára (csak mobil)
/// - Galéria/fájlrendszer használatára
/// - Meglévő kép törlésére
class MemoriapalotaImagePicker {
  final ImagePicker _imagePicker = ImagePicker();

  /// Megjeleníti a képválasztó dialógust
  ///
  /// Visszatérési érték: a kiválasztott kép byte-jai, vagy null ha megszakította
  Future<Uint8List?> showImagePickerDialog({
    required BuildContext context,
    required bool hasExistingImage,
    required VoidCallback onDeleteRequested,
    required VoidCallback onDialogOpened,
    required VoidCallback onDialogClosed,
  }) async {
    Uint8List? selectedBytes;

    onDialogOpened();
    try {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kép kiválasztása'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!kIsWeb)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    selectedBytes = await _pickImageFromCamera(context);
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Fotó készítése'),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (kIsWeb) {
                    selectedBytes = await _pickImageFromFileWeb(context);
                  } else {
                    selectedBytes = await _pickImageFromGallery(context);
                  }
                },
                icon: const Icon(Icons.photo_library),
                label: kIsWeb
                    ? const Text('Fájlból választás')
                    : const Text('Galériából választás'),
              ),
              if (hasExistingImage) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onDeleteRequested();
                  },
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Kép törlése',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ],
          ),
        ),
      );
    } finally {
      onDialogClosed();
    }

    return selectedBytes;
  }

  /// Web fájl kiválasztás közvetlenül (dialógus nélkül)
  Future<Uint8List?> pickImageDirectly(BuildContext context) async {
    if (kIsWeb) {
      return await _pickImageFromFileWeb(context);
    } else {
      return await _pickImageFromGallery(context);
    }
  }

  /// Web-en file_selector használata
  Future<Uint8List?> _pickImageFromFileWeb(BuildContext context) async {
    try {
      debugPrint('Opening file selector...');
      const typeGroup = XTypeGroup(
        label: 'Képek',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      debugPrint('File selector returned: ${file?.name ?? "NULL"}');

      if (file == null) {
        debugPrint('User cancelled');
        return null;
      }

      debugPrint('Reading file bytes...');
      final bytes = await file.readAsBytes();
      debugPrint('File bytes read: ${bytes.length} bytes');

      if (bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A fájl üres!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }

      return bytes;
    } catch (e, stackTrace) {
      debugPrint('ERROR in file selector: $e');
      debugPrint('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return null;
    }
  }

  /// Mobil kamera megnyitása
  Future<Uint8List?> _pickImageFromCamera(BuildContext context) async {
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Kamera csak mobil eszközökön érhető el!')),
        );
      }
      return null;
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 70,
      );

      if (image != null) {
        return await image.readAsBytes();
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a kép készítésekor: $e')),
        );
      }
      return null;
    }
  }

  /// Mobil galéria kiválasztás (image_picker)
  Future<Uint8List?> _pickImageFromGallery(BuildContext context) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: kIsWeb ? 85 : 70,
      );

      if (image == null) {
        debugPrint('User cancelled image selection');
        return null;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kép betöltése...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final bytes = await image.readAsBytes();
      debugPrint('Image bytes read: ${bytes.length} bytes');

      if (bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A kiválasztott fájl üres!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }

      return bytes;
    } catch (e, stackTrace) {
      debugPrint('ERROR in image picker: $e');
      debugPrint('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba a kép kiválasztásakor: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return null;
    }
  }
}

/// Progress dialógus a képfeltöltéshez
class UploadProgressDialog extends StatelessWidget {
  final double progress;
  final String phase;

  const UploadProgressDialog({
    super.key,
    required this.progress,
    required this.phase,
  });

  String get _phaseText {
    switch (phase) {
      case 'loading':
        return 'Kép betöltése...';
      case 'compressing':
        return 'Kép tömörítése...';
      case 'uploading':
        return 'Kép feltöltése...';
      default:
        return 'Feldolgozás...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _phaseText,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 6,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
          ),
          const SizedBox(height: 8),
          Text(
            progress > 0
                ? '${(progress * 100).toStringAsFixed(0)}%'
                : 'Feldolgozás...',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
