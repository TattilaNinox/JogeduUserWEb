import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/deck_collection.dart';
import 'learning_service.dart';

/// Deck Collections szolgáltatás a pakli gyűjtemények kezelésére.
/// Optimalizált batch lekérdezésekkel és cache-eléssel a skálázhatóság érdekében.
class DeckCollectionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache a gyűjteményekhez
  static List<DeckCollection>? _collectionsCache;
  static DateTime? _collectionsCacheTimestamp;
  static const Duration _cacheValidity = Duration(minutes: 15);

  // Cache a gyűjtemény statisztikákhoz
  static final Map<String, Map<String, int>> _collectionStatsCache = {};
  static final Map<String, DateTime> _statsCacheTimestamps = {};

  /// Összes gyűjtemény lekérése (cache-elve)
  static Future<List<DeckCollection>> getCollections({
    String science = 'Jogász',
    bool forceRefresh = false,
  }) async {
    // Cache ellenőrzése
    if (!forceRefresh &&
        _collectionsCache != null &&
        _collectionsCacheTimestamp != null &&
        DateTime.now().difference(_collectionsCacheTimestamp!) <
            _cacheValidity) {
      return _collectionsCache!;
    }

    try {
      final snapshot = await _firestore
          .collection('deck_collections')
          .where('science', isEqualTo: science)
          .orderBy('title')
          .get();

      final collections = snapshot.docs
          .map((doc) => DeckCollection.fromFirestore(doc))
          .toList();

      // Cache frissítése
      _collectionsCache = collections;
      _collectionsCacheTimestamp = DateTime.now();

      debugPrint(
          'DeckCollectionService: Loaded ${collections.length} collections');
      return collections;
    } catch (e) {
      debugPrint('Error loading deck collections: $e');
      rethrow;
    }
  }

  /// Egy gyűjtemény lekérése ID alapján
  static Future<DeckCollection?> getCollectionById(String collectionId) async {
    try {
      final doc = await _firestore
          .collection('deck_collections')
          .doc(collectionId)
          .get();

      if (!doc.exists) return null;
      return DeckCollection.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error loading deck collection $collectionId: $e');
      rethrow;
    }
  }

  /// Paklik betöltése gyűjteményből - BATCH optimalizálva
  /// Max 10 dokumentum/batch párhuzamosan
  static Future<List<Map<String, dynamic>>> loadDecksFromCollection(
    String collectionId,
  ) async {
    try {
      // Gyűjtemény lekérése
      final collection = await getCollectionById(collectionId);
      if (collection == null) return [];

      final deckIds = collection.deckIds;
      if (deckIds.isEmpty) return [];

      // Batch lekérdezés párhuzamosan (10-es chunk-okban)
      final List<Map<String, dynamic>> decks = [];
      const chunkSize = 10;

      final futures = <Future<List<DocumentSnapshot>>>[];
      for (var i = 0; i < deckIds.length; i += chunkSize) {
        final chunk =
            deckIds.sublist(i, (i + chunkSize).clamp(0, deckIds.length));
        futures.add(_fetchDecksBatch(chunk));
      }

      final results = await Future.wait(futures);
      for (final batch in results) {
        for (final doc in batch) {
          if (doc.exists) {
            decks.add({
              'id': doc.id,
              ...doc.data() as Map<String, dynamic>,
            });
          }
        }
      }

      debugPrint(
          'DeckCollectionService: Loaded ${decks.length} decks from collection $collectionId');
      return decks;
    } catch (e) {
      debugPrint('Error loading decks from collection: $e');
      rethrow;
    }
  }

  /// ÖSSZES kártya betöltése a gyűjtemény ÖSSZES paklijából
  /// A kártyák egyetlen listába kerülnek, összekeverve
  static Future<List<Map<String, dynamic>>> loadAllCardsFromCollection(
    String collectionId, {
    bool shuffle = true,
  }) async {
    try {
      final decks = await loadDecksFromCollection(collectionId);
      final allCards = <Map<String, dynamic>>[];

      for (final deck in decks) {
        final deckId = deck['id'] as String;
        final flashcards = deck['flashcards'] as List<dynamic>? ?? [];
        final categoryId = deck['category'] as String? ?? 'default';

        for (int i = 0; i < flashcards.length; i++) {
          final card = flashcards[i] as Map<String, dynamic>;
          allCards.add({
            'deckId': deckId,
            'index': i,
            'cardId': '$deckId#$i',
            'front': card['front'] ?? '',
            'back': card['back'] ?? '',
            'explanation': card['explanation'],
            'categoryId': categoryId,
          });
        }
      }

      if (shuffle) {
        allCards.shuffle();
      }

      debugPrint(
          'DeckCollectionService: Loaded ${allCards.length} cards from collection $collectionId');
      return allCards;
    } catch (e) {
      debugPrint('Error loading all cards from collection: $e');
      rethrow;
    }
  }

  /// Segéd: Batch lekérdezés adott deck ID-khoz
  static Future<List<DocumentSnapshot>> _fetchDecksBatch(
      List<String> deckIds) async {
    final futures = deckIds
        .map((id) => _firestore.collection('notes').doc(id).get())
        .toList();
    return Future.wait(futures);
  }

  /// Gyűjtemény aggregált statisztikái - CACHE-elve
  /// Lazy loading: csak a kért gyűjteményhez számoljuk
  static Future<Map<String, int>> getCollectionStats(
    String collectionId, {
    bool forceRefresh = false,
  }) async {
    // Cache ellenőrzése
    if (!forceRefresh &&
        _collectionStatsCache.containsKey(collectionId) &&
        _statsCacheTimestamps.containsKey(collectionId) &&
        DateTime.now().difference(_statsCacheTimestamps[collectionId]!) <
            _cacheValidity) {
      return _collectionStatsCache[collectionId]!;
    }

    try {
      final collection = await getCollectionById(collectionId);
      if (collection == null) {
        return {'total': 0, 'due': 0, 'new': 0, 'learning': 0, 'review': 0};
      }

      int totalCards = 0;
      int totalDue = 0;
      int totalNew = 0;
      int totalLearning = 0;
      int totalReview = 0;

      // Statisztikák lekérése minden paklihoz
      for (final deckId in collection.deckIds) {
        final stats = await LearningService.getDeckStats(deckId);
        totalCards += stats['total'] ?? 0;
        totalDue += stats['due'] ?? 0;
        totalNew += stats['new'] ?? 0;
        totalLearning += stats['learning'] ?? 0;
        totalReview += stats['review'] ?? 0;
      }

      final result = {
        'total': totalCards,
        'due': totalDue,
        'new': totalNew,
        'learning': totalLearning,
        'review': totalReview,
        'deckCount': collection.deckIds.length,
      };

      // Cache mentése
      _collectionStatsCache[collectionId] = result;
      _statsCacheTimestamps[collectionId] = DateTime.now();

      return result;
    } catch (e) {
      debugPrint('Error getting collection stats: $e');
      return {'total': 0, 'due': 0, 'new': 0, 'learning': 0, 'review': 0};
    }
  }

  /// Cache invalidálása (pl. tanulás után hívandó)
  static void invalidateCollectionCache(String collectionId) {
    _collectionStatsCache.remove(collectionId);
    _statsCacheTimestamps.remove(collectionId);
  }

  /// Teljes cache törlése
  static void clearAllCaches() {
    _collectionsCache = null;
    _collectionsCacheTimestamp = null;
    _collectionStatsCache.clear();
    _statsCacheTimestamps.clear();
  }
}
