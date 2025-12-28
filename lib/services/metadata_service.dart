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

      if (!doc.exists) {
        return {
          'categories': [],
          'tags': [],
        };
      }

      final data = doc.data() ?? {};
      return {
        'categories': List<String>.from(data['categories'] ?? []),
        'tags': List<String>.from(data['tags'] ?? []),
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
