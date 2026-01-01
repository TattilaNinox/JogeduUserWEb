import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/firebase_config.dart';
import 'package:flutter/foundation.dart';

/// Jegyzetek metaadatait (kategóriák, címkék) kezelő szerviz.
/// Az audit alapján egyetlen 'metadata' dokumentumból olvashatóak ki az adatok,
/// így elkerülhető a teljes kollekció-scan.
class MetadataService {
  /// Értesítő, amit a metadata frissítése után kiváltunk.
  /// A UI widgetek erre figyelhetnek, hogy újratöltsék az adataikat.
  static final refreshNotifier = ValueNotifier<int>(0);

  /// Lekéri a kategóriákat és címkéket egyetlen dokumentumból.
  /// Ha a dokumentum nem létezik, üres listákkal tér vissza.
  static Future<Map<String, List<String>>> getMetadata(String science) async {
    // 0. Próbálkozás: Az új Aggregált Structure használata (ez a legfrissebb és tartalmazza a dialogus tageket is)
    try {
      final structDocId =
          '${science.toLowerCase().replaceAll('á', 'a')}_structure';
      final structDoc = await FirebaseConfig.firestore
          .collection('metadata')
          .doc(structDocId)
          .get();

      if (structDoc.exists) {
        final data = structDoc.data() ?? {};
        final rawCatToTags = data['catToTags'] as Map<String, dynamic>? ?? {};
        final rawTagToCats = data['tagToCats'] as Map<String, dynamic>? ?? {};

        final categories = rawCatToTags.keys.toList()..sort();
        final tags = rawTagToCats.keys.toList()..sort();

        if (kDebugMode) {
          debugPrint(
              '✅ MetadataService: Loaded from Aggregated Structure ($structDocId). Cats: ${categories.length}, Tags: ${tags.length}');
        }
        return {
          'categories': categories,
          'tags': tags,
        };
      }
    } catch (e) {
      debugPrint('⚠️ MetadataService: Structure load failed: $e');
    }

    // 1. Próbálkozás: Active Metadata dokumentum olvasása (Legacy Cloud Function)

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
  static Future<Map<String, dynamic>> getCategoryTagMapping(
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
        final tagCountsMap = <String, Map<String, int>>{};
        final hierarchicalCountsMap = <String, Map<String, int>>{};

        final rawCatToTags = data['catToTags'] as Map<String, dynamic>? ?? {};
        final rawTagToCats = data['tagToCats'] as Map<String, dynamic>? ?? {};
        final rawTagCounts = data['tagCounts'] as Map<String, dynamic>? ?? {};
        final rawHierarchicalCounts =
            data['hierarchicalCounts'] as Map<String, dynamic>? ?? {};

        rawCatToTags.forEach((key, value) {
          catToTagsMap[key] = Set<String>.from(value as List? ?? []);
        });

        rawTagToCats.forEach((key, value) {
          tagToCatsMap[key] = Set<String>.from(value as List? ?? []);
        });

        rawTagCounts.forEach((category, countsData) {
          final counts = <String, int>{};
          if (countsData is Map) {
            countsData.forEach((tag, count) {
              counts[tag.toString()] = count as int? ?? 0;
            });
          }
          tagCountsMap[category.toString()] = counts;
        });

        rawHierarchicalCounts.forEach((category, countsData) {
          final counts = <String, int>{};
          if (countsData is Map) {
            countsData.forEach((path, count) {
              counts[path.toString()] = count as int? ?? 0;
            });
          }
          hierarchicalCountsMap[category.toString()] = counts;
        });

        if (kDebugMode) {
          debugPrint('✅ MetadataService: Aggregated Structure loaded ($docId)');
        }

        return {
          'catToTags': catToTagsMap,
          'tagToCats': tagToCatsMap,
          'tagCounts': tagCountsMap,
          'hierarchicalCounts': hierarchicalCountsMap,
        };
      } else {
        if (kDebugMode) {
          debugPrint(
              '⚠️ MetadataService: Aggregated Structure ($docId) NOT found. Empty map returned.');
        }
        return {
          'catToTags': {},
          'tagToCats': {},
          'tagCounts': {},
          'hierarchicalCounts': {},
        };
      }
    } catch (e) {
      debugPrint('🔴 MetadataService: Error loading aggregated map: $e');
      return {
        'catToTags': {},
        'tagToCats': {},
        'tagCounts': {},
        'hierarchicalCounts': {},
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
      // Tag counts tárolása kategóriánként (első szintű címkék)
      final tagCounts = <String, Map<String, int>>{};
      // ÚJ: Hierarchikus tag counts - kategória > tag path > count
      // Formátum: hierarchicalCounts['Alkotmányjog']['Alaptörvény'] = 39
      //           hierarchicalCounts['Alkotmányjog']['Alaptörvény/1. Nemzeti hitvallás'] = 5
      final hierarchicalCounts = <String, Map<String, int>>{};
      int docCount = 0;

      // Segédfüggvény egy kollekció feldolgozására
      Future<void> processCollection(String collectionName) async {
        try {
          Query query = FirebaseConfig.firestore
              .collection(collectionName)
              .where('science', isEqualTo: science);

          query =
              query.where('status', whereIn: ['Published', 'Draft', 'Public']);

          final snapshot = await query.get();
          docCount += snapshot.docs.length;

          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            var category = data['category'] as String?;

            List<String> tags = [];
            final rawTags = data['tags'];
            if (rawTags is List) {
              tags = rawTags.map((e) => e.toString()).toList();
            }

            // Dialogus fájlok speciális kezelése
            if (collectionName == 'dialogus_fajlok') {
              category = 'Dialogus tags';
            }

            if (category != null && category.isNotEmpty) {
              if (!catToTags.containsKey(category)) {
                catToTags[category] = {};
              }
              // JAVÍTVA: Csak az első szintű címkét (tags[0]) tároljuk a catToTags-ban
              // Így a CategoryTagsScreen csak az első szintű címkéket jeleníti meg
              if (tags.isNotEmpty) {
                catToTags[category]!.add(tags[0]);
              }

              // Tag counts inicializálása kategóriánként
              if (!tagCounts.containsKey(category)) {
                tagCounts[category] = {};
              }

              // Hierarchikus counts inicializálása
              if (!hierarchicalCounts.containsKey(category)) {
                hierarchicalCounts[category] = {};
              }

              // JAVÍTVA: MINDEN címke számolása, nem csak az első!
              // Így a "3. Szabadság és felelősség" is megjelenik, ha tags[0] az
              if (tags.isNotEmpty) {
                // Első szintű címke (tags[0]) - ez jelenik meg a CategoryTagsScreen-en
                final firstTag = tags[0];
                tagCounts[category]![firstTag] =
                    (tagCounts[category]![firstTag] ?? 0) + 1;

                // Hierarchikus count - minden útvonalhoz
                // Példa: ['Alaptörvény', '1. Nemzeti hitvallás']
                // Számoljuk: 'Alaptörvény', 'Alaptörvény/1. Nemzeti hitvallás'
                String currentPath = '';
                for (int i = 0; i < tags.length; i++) {
                  if (i == 0) {
                    currentPath = tags[i];
                  } else {
                    currentPath = '$currentPath/${tags[i]}';
                  }

                  hierarchicalCounts[category]![currentPath] =
                      (hierarchicalCounts[category]![currentPath] ?? 0) + 1;
                }
              }

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
      final catToTagsExport = <String, List<String>>{};
      final tagToCatsExport = <String, List<String>>{};
      final tagCountsExport = <String, Map<String, int>>{};
      final hierarchicalCountsExport = <String, Map<String, int>>{};

      catToTags.forEach((k, v) => catToTagsExport[k] = v.toList()..sort());
      tagToCats.forEach((k, v) => tagToCatsExport[k] = v.toList()..sort());
      tagCounts.forEach((k, v) => tagCountsExport[k] = v);
      hierarchicalCounts.forEach((k, v) => hierarchicalCountsExport[k] = v);

      final docId = '${science.toLowerCase().replaceAll('á', 'a')}_structure';
      await FirebaseConfig.firestore.collection('metadata').doc(docId).set({
        'catToTags': catToTagsExport,
        'tagToCats': tagToCatsExport,
        'tagCounts': tagCountsExport, // Első szintű címkék count-ja
        'hierarchicalCounts':
            hierarchicalCountsExport, // ÚJ: Hierarchikus counts
        'updatedAt': FieldValue.serverTimestamp(),
        'docCount': docCount,
      });

      if (kDebugMode) {
        debugPrint(
            '✅ Metadata Aggregation COMPLETED. Processed $docCount docs (Total).');
        debugPrint(
            '   Hierarchical paths stored: ${hierarchicalCounts.values.fold(0, (sum, map) => sum + map.length)}');
      }

      // Értesítjük a UI-t, hogy frissült a metadata
      refreshNotifier.value++;

      return docCount;
    } catch (e) {
      debugPrint('🔴 Metadata Aggregation FAILED: $e');
      rethrow;
    }
  }
}
