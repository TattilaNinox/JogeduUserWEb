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
          '✅ MetadataService: Master Lists loaded -> Cats: ${categories.length}, Tags: ${tags.length}');

      // 3. Lépés: Validálás - Csak olyanokat tartsunk meg, amihez van is jegyzet
      // Párhuzamosan futtatjuk a két szűrést
      final results = await Future.wait([
        _filterActiveItems(activeCollections: [
          'notes',
          'jogesetek',
          'memoriapalota_allomasok'
        ], field: 'category', items: categories, science: science),
        _filterActiveItems(activeCollections: [
          'notes',
          'jogesetek',
          'memoriapalota_allomasok'
        ], field: 'tags', items: tags, science: science, isArray: true),
      ]);

      final activeCategories = results[0];
      final activeTags = results[1];

      print(
          '✅ MetadataService: Active Filtered Lists -> Cats: ${activeCategories.length}, Tags: ${activeTags.length}');

      return {
        'categories': activeCategories,
        'tags': activeTags,
      };
    } catch (e) {
      print('🔴 MetadataService CRITICAL FALLBACK ERROR: $e');
      return {
        'categories': [],
        'tags': [],
      };
    }
  }

  /// Segédfüggvény: Ellenőrzi, hogy a lista elemeihez tartozik-e legalább egy aktív jegyzet.
  /// Több kollekciót is ellenőriz párhuzamosan: notes, jogesetek, memoriapalota_allomasok
  static Future<List<String>> _filterActiveItems({
    required List<String> activeCollections, // Módosítva lista típusra
    required String field,
    required List<String> items,
    required String science,
    bool isArray = false,
  }) async {
    if (items.isEmpty) return [];

    final itemsToCheck =
        isArray && items.length > 50 ? items.take(50).toList() : items;
    final Set<String> activeItems = {}; // Set a duplikációk elkerülésére

    const chunkSize = 10;

    // Minden kollekcióra külön futtatjuk az ellenőrzést párhuzamosan
    final collectionFutures = activeCollections.map((collection) async {
      List<String> foundInCollection = [];
      for (var i = 0; i < itemsToCheck.length; i += chunkSize) {
        final end = (i + chunkSize < itemsToCheck.length)
            ? i + chunkSize
            : itemsToCheck.length;
        final chunk = itemsToCheck.sublist(i, end);

        final futures = chunk.map((item) async {
          // Ha már megtaláltuk bármelyik kollekcióban, ne keressük tovább feleslegesen
          // (Ez a szinkronizáció miatt bonyolult lenne, egyszerűbb hagyni futni)
          try {
            var query = FirebaseConfig.firestore
                .collection(collection)
                .where('science', isEqualTo: science);

            // Csak notes és jogesetek esetén van status mező, amit figyelni kell
            // Állomásoknál nem feltétlenül van Published/Draft status szűrés a listában (ott minden látszik?)
            // A NoteCardGrid szerint: allomasQuery = isAdmin ? ... status IN [Pub, Draft] : ... Pub
            // Tehát mindenhol van status mező.
            query = query
                .where('status', whereIn: ['Published', 'Draft', 'Public']);

            if (isArray) {
              query = query.where(field, arrayContains: item);
            } else {
              query = query.where(field, isEqualTo: item);
            }

            final snapshot = await query.limit(1).get();
            return snapshot.docs.isNotEmpty ? item : null;
          } catch (e) {
            // print('⚠️ Check failed for $item in $collection: $e');
            return null;
          }
        });

        final results = await Future.wait(futures);
        foundInCollection.addAll(results.whereType<String>());
      }
      return foundInCollection;
    });

    final resultsList = await Future.wait(collectionFutures);

    for (final list in resultsList) {
      activeItems.addAll(list);
    }

    if (isArray && items.length > 50) {
      print(
          '⚠️ MetadataService: Tag list truncated for implementation performance (${items.length} -> 50 checked)');
    }

    return activeItems.toList()..sort();
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
