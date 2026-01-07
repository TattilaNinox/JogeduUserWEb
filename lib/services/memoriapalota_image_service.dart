import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:convert';

import '../core/firebase_config.dart';

/// Memóriapalota kép feltöltés szolgáltatás
///
/// Ez a szolgáltatás kezeli:
/// - Képek tömörítését (200 KB alá)
/// - Feltöltést Firebase Storage-ba
/// - Kép URL mentését Firestore-ba
/// - Lokális preview URL létrehozását (optimistic UI)
class MemoriapalotaImageService {
  static final MemoriapalotaImageService _instance =
      MemoriapalotaImageService._internal();
  factory MemoriapalotaImageService() => _instance;
  MemoriapalotaImageService._internal();

  /// Kép tömörítése 200 KB alá - gyorsított verzió
  Future<Uint8List?> compressImage(Uint8List imageBytes) async {
    // Ha már 200 KB alatt van, visszaadja
    if (imageBytes.length <= 200 * 1024) {
      return imageBytes;
    }

    try {
      debugPrint(
          'Starting image compression, platform: ${kIsWeb ? "web" : "mobile"}, size: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');

      Uint8List? compressed;

      if (kIsWeb) {
        // Web-en a compute nem mindig működik megfelelően
        // Kis késleltetés, hogy az UI frissülhessen
        await Future.delayed(const Duration(milliseconds: 50));

        // Aszinkron módon futtatjuk, hogy ne blokkolja a UI-t
        compressed = await Future(() => _compressImageInIsolate(imageBytes));
      } else {
        // Mobil eszközön először próbáljuk a compute-ot, de ha nem működik, közvetlenül futtatjuk
        debugPrint('Using compute for mobile compression...');
        try {
          // Kis késleltetés, hogy az UI frissülhessen
          await Future.delayed(const Duration(milliseconds: 100));
          compressed =
              await compute(_compressImageInIsolate, imageBytes).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Tömörítés timeout');
            },
          );
        } catch (e) {
          debugPrint(
              'Compute failed or timeout, trying direct compression: $e');
          // Ha a compute nem működik vagy timeout, próbáljuk közvetlenül
          // Kis késleltetés, hogy az UI frissülhessen
          await Future.delayed(const Duration(milliseconds: 100));
          compressed =
              await Future(() => _compressImageInIsolate(imageBytes)).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Tömörítés timeout (közvetlen)');
            },
          );
        }
      }

      debugPrint(
          'Compression completed: ${compressed?.length ?? 0} bytes (${(compressed?.length ?? 0) / 1024} KB)');
      return compressed;
    } catch (e, stackTrace) {
      debugPrint('Hiba a tömörítéskor: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Firebase Storage-ba feltöltés
  Future<String> uploadImageToStorage({
    required Uint8List imageBytes,
    required String utvonalId,
    required String allomasId,
    String? existingImageUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Nincs bejelentkezve felhasználó!');
    }

    debugPrint(
        'Uploading image to Storage: memoriapalota_images/$utvonalId/$allomasId/${user.uid}/image.jpg');
    debugPrint(
        'Image size: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');

    // Régi kép törlése (ha van)
    if (existingImageUrl != null && existingImageUrl.startsWith('https://')) {
      try {
        debugPrint('Deleting old image: $existingImageUrl');
        final oldRef = FirebaseStorage.instance.refFromURL(existingImageUrl);
        await oldRef.delete().timeout(const Duration(seconds: 5));
        debugPrint('Old image deleted successfully');
      } catch (e) {
        debugPrint('Could not delete old image (continuing anyway): $e');
        // Ha nem sikerül törölni, folytatjuk
      }
    }

    // Új kép feltöltése
    final ref = FirebaseStorage.instance.ref(
      'memoriapalota_images/$utvonalId/$allomasId/${user.uid}/image.jpg',
    );

    debugPrint('Starting upload to Firebase Storage...');
    try {
      await ref
          .putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception(
              'A képfeltöltés túl sokáig tartott. Kérlek, próbáld újra!');
        },
      );
      debugPrint('Upload to Storage completed');
    } catch (e) {
      debugPrint('Error uploading to Storage: $e');
      rethrow;
    }

    debugPrint('Getting download URL...');
    final imageUrl = await ref.getDownloadURL().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception(
            'Nem sikerült lekérni a kép URL-jét. Kérlek, próbáld újra!');
      },
    );
    debugPrint('Download URL obtained: $imageUrl');

    return imageUrl;
  }

  /// Firestore-ba mentés
  Future<void> saveImageUrlToFirestore({
    required String imageUrl,
    required String utvonalId,
    required String allomasId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Nincs bejelentkezve felhasználó!');
    }

    debugPrint(
        'Saving to Firestore: memoriapalota_allomasok/$utvonalId/allomasok/$allomasId/userImages/${user.uid}');

    try {
      await FirebaseConfig.firestore
          .collection('memoriapalota_allomasok')
          .doc(utvonalId)
          .collection('allomasok')
          .doc(allomasId)
          .collection('userImages')
          .doc(user.uid)
          .set({
        'imageUrl': imageUrl,
        'uploadedAt': Timestamp.now(),
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception(
              'A Firestore mentés túl sokáig tartott. Kérlek, próbáld újra!');
        },
      );
      debugPrint('Firestore save completed');
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
      rethrow;
    }
  }

  /// Kép törlése Storage-ból és Firestore-ból
  Future<void> deleteImage({
    required String imageUrl,
    required String utvonalId,
    required String allomasId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    // Storage-ból törlés
    try {
      final ref = FirebaseStorage.instance.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      debugPrint('Could not delete image from Storage: $e');
      // Ha nem sikerül törölni, folytatjuk
    }

    // Firestore-ból törlés
    await FirebaseConfig.firestore
        .collection('memoriapalota_allomasok')
        .doc(utvonalId)
        .collection('allomasok')
        .doc(allomasId)
        .collection('userImages')
        .doc(user.uid)
        .delete();
  }

  /// Lokális data URL létrehozása web-en (optimistic UI)
  String? createLocalImageUrl(Uint8List imageBytes) {
    if (!kIsWeb) return null;

    try {
      // Base64 kódolás a data URL-hez
      final base64Data = base64Encode(imageBytes);
      // MIME típus meghatározása az első bájtok alapján
      String mimeType = 'image/jpeg';
      if (imageBytes.length >= 4) {
        if (imageBytes[0] == 0x89 &&
            imageBytes[1] == 0x50 &&
            imageBytes[2] == 0x4E &&
            imageBytes[3] == 0x47) {
          mimeType = 'image/png';
        } else if (imageBytes[0] == 0x47 &&
            imageBytes[1] == 0x49 &&
            imageBytes[2] == 0x46) {
          mimeType = 'image/gif';
        } else if (imageBytes.length >= 12 &&
            imageBytes[0] == 0x52 &&
            imageBytes[1] == 0x49 &&
            imageBytes[2] == 0x46 &&
            imageBytes[3] == 0x46 &&
            imageBytes[8] == 0x57 &&
            imageBytes[9] == 0x45 &&
            imageBytes[10] == 0x42 &&
            imageBytes[11] == 0x50) {
          mimeType = 'image/webp';
        }
      }
      return 'data:$mimeType;base64,$base64Data';
    } catch (e) {
      debugPrint('Hiba a lokális kép URL létrehozásakor: $e');
      return null;
    }
  }

  /// Felhasználó képének betöltése adott állomáshoz
  Future<String?> loadUserImage({
    required String utvonalId,
    required String allomasId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    try {
      final imageDoc = await FirebaseConfig.firestore
          .collection('memoriapalota_allomasok')
          .doc(utvonalId)
          .collection('allomasok')
          .doc(allomasId)
          .collection('userImages')
          .doc(user.uid)
          .get();

      if (imageDoc.exists) {
        return imageDoc.data()?['imageUrl'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error loading user image: $e');
      return null;
    }
  }
}

/// Top-level függvény a compute-hoz - gyorsított, egyszerűsített verzió
Future<Uint8List?> _compressImageInIsolate(Uint8List imageBytes) async {
  // Ha már 200 KB alatt van, visszaadja
  if (imageBytes.length <= 200 * 1024) {
    return imageBytes;
  }

  try {
    // Kép dekódolása
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw Exception('Nem sikerült dekódolni a képet');
    }

    // Agresszív kezdeti beállítások - gyors tömörítés
    final originalSizeKB = imageBytes.length / 1024;
    const targetSizeKB = 200.0;
    final sizeRatio = originalSizeKB / targetSizeKB;

    // Kezdeti értékek - agresszívabb tömörítés
    int targetWidth = decodedImage.width;
    int targetHeight = decodedImage.height;
    int quality = 70; // Alacsonyabb kezdeti minőség

    // Agresszív méret csökkentés azonnal
    if (sizeRatio > 3) {
      // Nagyon nagy kép: jelentősen csökkentjük
      const scale = 0.5;
      targetWidth = (decodedImage.width * scale).round();
      targetHeight = (decodedImage.height * scale).round();
      quality = 60;
    } else if (sizeRatio > 2) {
      // Nagy kép: mérsékelten csökkentjük
      const scale = 0.65;
      targetWidth = (decodedImage.width * scale).round();
      targetHeight = (decodedImage.height * scale).round();
      quality = 65;
    } else if (sizeRatio > 1.5) {
      // Közepes kép: kicsit csökkentjük
      const scale = 0.8;
      targetWidth = (decodedImage.width * scale).round();
      targetHeight = (decodedImage.height * scale).round();
      quality = 70;
    }

    // Maximum méret korlátozás - agresszívabb
    if (targetWidth > 1000) {
      final scale = 1000.0 / targetWidth;
      targetWidth = 1000;
      targetHeight = (targetHeight * scale).round();
    }
    if (targetHeight > 1000) {
      final scale = 1000.0 / targetHeight;
      targetHeight = 1000;
      targetWidth = (targetWidth * scale).round();
    }

    // Egyszerű, gyors tömörítés - max 2 iteráció
    Uint8List? compressed;
    int maxIterations = 2; // Csak 2 iteráció a gyorsaságért
    int iteration = 0;

    while (iteration < maxIterations &&
        (compressed == null || compressed.length > 200 * 1024)) {
      iteration++;

      // Kép átméretezése (ha szükséges) - csak egyszer
      img.Image resizedImage;
      if (iteration == 1 &&
          (targetWidth != decodedImage.width ||
              targetHeight != decodedImage.height)) {
        resizedImage = img.copyResize(
          decodedImage,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.linear,
        );
      } else if (iteration == 1) {
        resizedImage = decodedImage;
      } else {
        // Második iterációban újra átméretezünk kisebbre
        targetWidth = (targetWidth * 0.8).round();
        targetHeight = (targetHeight * 0.8).round();
        resizedImage = img.copyResize(
          decodedImage,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.linear,
        );
        quality = 50; // Alacsony minőség második iterációban
      }

      // JPEG formátumban kódolás
      compressed = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: quality),
      );

      // Ha még mindig túl nagy, agresszívabb csökkentés
      if (compressed.length > 200 * 1024 && iteration < maxIterations) {
        quality = 40; // Nagyon alacsony minőség
        targetWidth = (targetWidth * 0.7).round();
        targetHeight = (targetHeight * 0.7).round();
      } else {
        break;
      }
    }

    // Ha még mindig túl nagy, akkor elfogadjuk (max 250 KB)
    if (compressed != null && compressed.length <= 250 * 1024) {
      return compressed;
    }

    // Ha még mindig túl nagy, akkor hiba
    if (compressed == null || compressed.length > 250 * 1024) {
      throw Exception(
          'A kép mérete még tömörítés után is meghaladja a 250 KB-ot (${(compressed?.length ?? 0) / 1024} KB). Kérlek, válassz egy kisebb képet!');
    }

    return compressed;
  } catch (e) {
    rethrow;
  }
}
