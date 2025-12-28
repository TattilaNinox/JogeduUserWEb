import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/firebase_config.dart';

/// Jegyzetek metaadatait (kategóriák, címkék) kezelő szerviz.
/// Az audit alapján egyetlen 'metadata' dokumentumból olvashatóak ki az adatok,
/// így elkerülhető a teljes kollekció-scan.
class MetadataService {
  /// Lekéri a kategóriákat és címkéket egyetlen dokumentumból.
  /// Ha a dokumentum nem létezik, üres listákkal tér vissza.
  static Future<Map<String, List<String>>> getMetadata(String science) async {
    // 1. Próbálkozás: Metadata dokumentum olvasása (Gyorsítótár)
    try {
      final docId = science.toLowerCase().replaceAll('á', 'a');
      print('🔍 MetadataService: Keresés docId=$docId (science=$science)');
      final doc = await FirebaseConfig.firestore
          .collection('metadata')
          .doc(docId)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        final categories = List<String>.from(data['categories'] ?? []);
        final tags = List<String>.from(data['tags'] ?? []);

        print(
            '🔍 MetadataService: Doc found. Cats: ${categories.length}, Tags: ${tags.length}');

        if (categories.isNotEmpty) {
          return {
            'categories': categories,
            'tags': tags,
          };
        }
      } else {
        print(
            '⚠️ MetadataService: Metadata doc ($docId) NOT found. Proceeding to fallback.');
      }
    } catch (e) {
      // Permission denied vagy más hiba -> Folytatjuk a fallback-kel
      print(
          '⚠️ MetadataService: Optimalizált olvasás sikertelen ($e). Folytatás fallback stratégiával.');
    }

    // 2. Próbálkozás: Fallback - közvetlen kollekció olvasás
    try {
      print(
          '🔄 MetadataService: Fallback indul (Categories & Tags kollekciók)...');

      final categoriesSnapshot = await FirebaseConfig.firestore
          .collection('categories')
          .where('science', isEqualTo: science)
          .get();

      print(
          '🔄 MetadataService: Fallback cats query result: ${categoriesSnapshot.docs.length} docs');

      final tagsSnapshot =
          await FirebaseConfig.firestore.collection('tags').get();

      print(
          '🔄 MetadataService: Fallback tags query result: ${tagsSnapshot.docs.length} docs');

      final categories = categoriesSnapshot.docs
          .map((d) => d.data()['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      final tags = tagsSnapshot.docs
          .map((d) => d.data()['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      print(
          '✅ MetadataService: Final Fallback Lists -> Cats: ${categories.length}, Tags: ${tags.length}');

      return {
        'categories': categories,
        'tags': tags,
      };
    } catch (e) {
      print('🔴 MetadataService CRITICAL FALLBACK ERROR: $e');
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
