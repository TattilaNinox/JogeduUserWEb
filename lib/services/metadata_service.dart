import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/firebase_config.dart';

/// Jegyzetek metaadatait (kategóriák, címkék) kezelő szerviz.
/// Az audit alapján egyetlen 'metadata' dokumentumból olvashatóak ki az adatok,
/// így elkerülhető a teljes kollekció-scan.
class MetadataService {
  /// Lekéri a kategóriákat és címkéket egyetlen dokumentumból.
  /// Ha a dokumentum nem létezik, üres listákkal tér vissza.
  static Future<Map<String, List<String>>> getMetadata(String science) async {
    try {
      // Megjegyzés: A 'science' paraméter alapján keressük a megfelelő dokumentumot.
      // Példa: metadata/jogasz
      final docId = science.toLowerCase().replaceAll('á', 'a');
      final doc = await FirebaseConfig.firestore
          .collection('metadata')
          .doc(docId)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        final categories = List<String>.from(data['categories'] ?? []);
        final tags = List<String>.from(data['tags'] ?? []);

        if (categories.isNotEmpty) {
          return {
            'categories': categories,
            'tags': tags,
          };
        }
      }

      // Fallback: ha nincs metadata, olvassuk ki a kollekciókból
      // Ez lassabb, de garantáltan működik
      final categoriesSnapshot = await FirebaseConfig.firestore
          .collection('categories')
          .where('science', isEqualTo: science)
          .get();

      final tagsSnapshot = await FirebaseConfig.firestore
          .collection('tags') // Feltételezve, hogy van tags kollekció
          .get();

      final categories = categoriesSnapshot.docs
          .map((d) => d.data()['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      final tags = tagsSnapshot.docs
          .map((d) => d.data()['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      // Opcionális: frissíthetjük a metadata-t a jövőre nézve
      // if (categories.isNotEmpty) updateMetadata(science, categories, tags);

      return {
        'categories': categories,
        'tags': tags,
      };
    } catch (e) {
      return {
        'categories': [],
        'tags': [],
      };
    }
  }

  /// Metadata frissítése (Admin funkció - opcionális kiegészítés a jövőre nézve)
  static Future<void> updateMetadata(
      String science, List<String> categories, List<String> tags) async {
    final docId = science.toLowerCase().replaceAll('á', 'a');
    await FirebaseConfig.firestore.collection('metadata').doc(docId).set({
      'categories': categories,
      'tags': tags,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
