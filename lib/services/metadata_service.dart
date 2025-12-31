import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/firebase_config.dart';
import 'package:flutter/foundation.dart';

/// Jegyzetek metaadatait (kategóriák, címkék) kezelő szerviz.
/// Az audit alapján egyetlen 'metadata' dokumentumból olvashatóak ki az adatok,
/// így elkerülhető a teljes kollekció-scan.
class MetadataService {
  /// Lekéri a kategóriákat és címkéket egyetlen dokumentumból.
  /// Ha a dokumentum nem létezik, üres listákkal tér vissza.
  static Future<Map<String, List<String>>> getMetadata(String science) async {
    // 1. Próbálkozás: Active Metadata dokumentum olvasása (Cloud Function által generált)
    // Ez a skálázható megoldás (egyetlen olvasás)
    try {
      // Konstans 'jogasz_active', vagy dinamikusan: '${science.toLowerCase()}_active'
      // Mivel a Cloud Function a 'jogasz_active' ID-t használja:
      final activeDocId =
          '${science.toLowerCase().replaceAll('á', 'a')}_active';

      if (kDebugMode) {
        debugPrint(
            '🔍 MetadataService: Skálázható keresés docId=$activeDocId (science=$science)');
      }
      final doc = await FirebaseConfig.firestore
          .collection('metadata')
          .doc(activeDocId)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        final categories = List<String>.from(data['categories'] ?? []);
        final tags = List<String>.from(data['tags'] ?? []);

        if (kDebugMode) {
          debugPrint(
              '✅ MetadataService: Active Doc found (Cloud Function). Cats: ${categories.length}, Tags: ${tags.length}');
        }

        if (categories.isNotEmpty || tags.isNotEmpty) {
          return {
            'categories': categories,
            'tags': tags,
          };
        }
      } else {
        if (kDebugMode) {
          debugPrint(
              '⚠️ MetadataService: Active Metadata doc ($activeDocId) NOT found yet. Proceeding to fallback.');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ MetadataService: Aktív metadata olvasás hiba ($e). Folytatás fallback stratégiával.');
      }
    }

    // 2. Próbálkozás: Fallback - közvetlen kollekció olvasás
    try {
      if (kDebugMode) {
        debugPrint(
            '🔄 MetadataService: Fallback indul (Categories & Tags kollekciók)...');
      }

      final categoriesSnapshot = await FirebaseConfig.firestore
          .collection('categories')
          .where('science', isEqualTo: science)
          .get();

      if (kDebugMode) {
        debugPrint(
            '🔄 MetadataService: Fallback cats query result: ${categoriesSnapshot.docs.length} docs');
      }

      final tagsSnapshot =
          await FirebaseConfig.firestore.collection('tags').get();

      if (kDebugMode) {
        debugPrint(
            '🔄 MetadataService: Fallback tags query result: ${tagsSnapshot.docs.length} docs');
      }

      final categories = categoriesSnapshot.docs
          .map((d) => d.data()['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      final tags = tagsSnapshot.docs
          .map((d) => d.data()['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      if (kDebugMode) {
        debugPrint(
            '✅ MetadataService: Master Lists loaded -> Cats: ${categories.length}, Tags: ${tags.length}');
      }

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

      if (kDebugMode) {
        debugPrint(
            '✅ MetadataService: Active Filtered Lists -> Cats: ${activeCategories.length}, Tags: ${activeTags.length}');
      }

      return {
        'categories': activeCategories,
        'tags': activeTags,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🔴 MetadataService CRITICAL FALLBACK ERROR: $e');
      }
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
      if (kDebugMode) {
        debugPrint(
            '⚠️ MetadataService: Tag list truncated for implementation performance (${items.length} -> 50 checked)');
      }
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

  /// Skálázható kapcsolatépítés: Aggregált dokumentum olvasása.
  /// A `metadata/jogasz_structure` dokumentum tartalmazza az előre kiszámolt térképet.
  /// Így 1 db olvasás elegendő a több ezer helyett.
  static Future<Map<String, Map<String, Set<String>>>> getCategoryTagMapping(
      String science) async {
    try {
      final docId = '${science.toLowerCase().replaceAll('á', 'a')}_structure';
      final doc = await FirebaseConfig.firestore
          .collection('metadata')
          .doc(docId)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        // Firestore Map<String, dynamic> -> Map<String, Set<String>> konverzió
        final catToTagsMap = <String, Set<String>>{};
        final tagToCatsMap = <String, Set<String>>{};

        final rawCatToTags = data['catToTags'] as Map<String, dynamic>? ?? {};
        final rawTagToCats = data['tagToCats'] as Map<String, dynamic>? ?? {};

        rawCatToTags.forEach((key, value) {
          catToTagsMap[key] = Set<String>.from(value as List? ?? []);
        });

        rawTagToCats.forEach((key, value) {
          tagToCatsMap[key] = Set<String>.from(value as List? ?? []);
        });

        if (kDebugMode) {
          debugPrint('✅ MetadataService: Aggregated Structure loaded ($docId)');
        }

        return {
          'catToTags': catToTagsMap,
          'tagToCats': tagToCatsMap,
        };
      } else {
        if (kDebugMode) {
          debugPrint(
              '⚠️ MetadataService: Aggregated Structure ($docId) NOT found. Empty map returned.');
        }
        return {
          'catToTags': {},
          'tagToCats': {},
        };
      }
    } catch (e) {
      debugPrint('🔴 MetadataService: Error loading aggregated map: $e');
      return {
        'catToTags': {},
        'tagToCats': {},
      };
    }
  }

  /// ADMIN FUNKCIÓ: Metadata Aggregáció Frissítése.
  /// Végigolvassa az összes aktív jegyzetet (és egyéb típusokat) és újraépíti
  /// a `metadata/jogasz_structure` dokumentumot.
  /// Ezt a funkciót csak Adminisztrátor hívhatja meg!
  static Future<int> refreshMetadataAggregation(String science) async {
    try {
      if (kDebugMode) debugPrint('🔄 Metadata Aggregation STARTED...');

      final catToTags = <String, Set<String>>{};
      final tagToCats = <String, Set<String>>{};
      int docCount = 0;

      // Segédfüggvény egy kollekció feldolgozására
      Future<void> processCollection(String collectionName) async {
        try {
          // Ha 'memoriapalota_allomasok', ott nincs feltétlenül 'status' mező mindenhol?
          // De a NoteCardGrid szűrés szerint: status IN [Pub, Draft] vagy csak Pub.
          // Feltételezzük, hogy van status mező, vagy ha nincs, akkor minden elem publikus?
          // A biztonság kedvéért megpróbáljuk status szűréssel, ha üres lesz, akkor status nélkül.
          // DE: A legegyszerűbb, ha csak azokat vesszük, ahol VAN status és az megfelelő.
          Query query = FirebaseConfig.firestore
              .collection(collectionName)
              .where('science', isEqualTo: science);

          // Mindenhol szűrünk statusra, mert a felhasználó megerősítette, hogy fontos és mindenhol van.
          query =
              query.where('status', whereIn: ['Published', 'Draft', 'Public']);

          final snapshot = await query.get();
          docCount += snapshot.docs.length;

          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final category = data['category'] as String?;

            // Hibatűrő címke olvasás:
            // A 'dialogus_fajlok' esetén a tags egy Map (pl. {tartalom: "..."}),
            // nem List<String>. Ezt kezelni kell, különben elszáll a castolásnál.
            List<String> tags = [];
            final rawTags = data['tags'];
            if (rawTags is List) {
              tags = List<String>.from(rawTags);
            } else if (rawTags is Map) {
              // Ha Map, akkor nem címke, hanem egyéb adat (pl. tartalom),
              // így itt üres listának tekintjük a szűrés szempontjából.
              tags = [];
            }

            if (category != null && category.isNotEmpty) {
              if (!catToTags.containsKey(category)) {
                catToTags[category] = {};
              }
              catToTags[category]!.addAll(tags);

              for (var tag in tags) {
                if (!tagToCats.containsKey(tag)) {
                  tagToCats[tag] = {};
                }
                tagToCats[tag]!.add(category);
              }
            }
          }
          if (kDebugMode) {
            debugPrint(
                '   -> Processed $collectionName: ${snapshot.docs.length} docs');
          }
        } catch (e) {
          debugPrint('⚠️ Error processing collection $collectionName: $e');
        }
      }

      // Minden releváns kollekciót feldolgozunk
      await processCollection('notes');
      await processCollection('jogesetek');
      await processCollection('memoriapalota_allomasok');
      await processCollection('dialogus_fajlok');

      // 2. Mentés: Aggregált dokumentum írása
      // Firestore nem támogat Set-et, List-té kell konvertálni
      final catToTagsExport = <String, List<String>>{};
      final tagToCatsExport = <String, List<String>>{};

      catToTags.forEach((k, v) => catToTagsExport[k] = v.toList()..sort());
      tagToCats.forEach((k, v) => tagToCatsExport[k] = v.toList()..sort());

      final docId = '${science.toLowerCase().replaceAll('á', 'a')}_structure';
      await FirebaseConfig.firestore.collection('metadata').doc(docId).set({
        'catToTags': catToTagsExport,
        'tagToCats': tagToCatsExport,
        'updatedAt': FieldValue.serverTimestamp(),
        'docCount': docCount,
      });

      if (kDebugMode) {
        debugPrint(
            '✅ Metadata Aggregation COMPLETED. Processed $docCount docs (Total).');
      }
      return docCount;
    } catch (e) {
      debugPrint('🔴 Metadata Aggregation FAILED: $e');
      rethrow;
    }
  }
}
