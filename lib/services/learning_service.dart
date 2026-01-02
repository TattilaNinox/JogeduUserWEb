import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/flashcard_learning_data.dart';
import '../core/learning_algorithm.dart';

class LearningService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache a deck esedékes kártyáinak indexeire
  static final Map<String, List<int>> _dueCardsCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheValidity = Duration(minutes: 15);

  /// Egy kártya tanulási adatainak frissítése értékelés alapján
  static Future<void> updateUserLearningData(
    String cardId, // deckId#index formátum
    String rating, // "Again" | "Hard" | "Good" | "Easy"
    String categoryId,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('LearningService: No authenticated user');
        return;
      }

      debugPrint(
          'LearningService: Updating learning data for cardId: $cardId, rating: $rating, categoryId: $categoryId');

      // Jelenlegi adatok lekérése
      final currentData = await _getCurrentLearningData(cardId, categoryId);
      debugPrint(
          'LearningService: Current data - state: ${currentData.state}, interval: ${currentData.interval}, easeFactor: ${currentData.easeFactor}');

      // Új állapot kalkulálása az új LearningAlgorithm osztállyal
      final newData = LearningAlgorithm.calculateNextState(currentData, rating);
      debugPrint(
          'LearningService: New data - state: ${newData.state}, interval: ${newData.interval}, easeFactor: ${newData.easeFactor}');

      // Mentés az új útvonalra (users/{uid}/categories/{categoryId}/learning/{cardId})
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('categories')
          .doc(categoryId)
          .collection('learning')
          .doc(cardId)
          .set(newData.toMap());

      debugPrint(
          'LearningService: Successfully saved learning data to Firestore');

      // Deck és kategória statisztikák frissítése
      final cardIndex = cardId.split('#')[1]; // String index formátumban
      await _updateDeckSnapshot(
          cardId.split('#')[0], cardIndex, rating, currentData.lastRating);
      await _updateCategoryStats(categoryId, rating, currentData.lastRating);

      // Cache invalidálása
      _invalidateDeckCache(cardId.split('#')[0]);
    } catch (e) {
      debugPrint('Error updating learning data: $e');
      rethrow;
    }
  }

  /// Esedékes kártyák indexeinek lekérése egy deck-hez
  static Future<List<int>> getDueFlashcardIndicesForDeck(String deckId) async {
    // Cache ellenőrzése
    if (_dueCardsCache.containsKey(deckId) &&
        _cacheTimestamps.containsKey(deckId) &&
        DateTime.now().difference(_cacheTimestamps[deckId]!) < _cacheValidity) {
      return _dueCardsCache[deckId]!;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      // Deck adatok lekérése
      final deckDoc = await _firestore.collection('notes').doc(deckId).get();
      if (!deckDoc.exists) return [];

      final deckData = deckDoc.data() as Map<String, dynamic>;
      final flashcards =
          List<Map<String, dynamic>>.from(deckData['flashcards'] ?? []);
      final categoryId = deckData['category'] as String? ?? 'default';

      // Ne hagyjuk ki a Firestore lekérdezést kis pakliknál sem,
      // mert így a kliens nem kapná meg a tanulási állapotot és
      // minden belépéskor úgy tűnne, hogy az összes kártya esedékes.

      // Batch lekérdezés timeout-tal
      final learningDataMap = await _getBatchLearningDataWithTimeout(
        deckId,
        flashcards.length,
        categoryId,
        const Duration(seconds: 30),
      );

      final dueIndices = <int>[];
      final now = Timestamp.now();

      // LEARNING és REVIEW állapotú esedékes kártyák
      for (int i = 0; i < flashcards.length; i++) {
        final learningData = learningDataMap[i];
        if (learningData != null &&
            learningData.state != 'NEW' &&
            learningData.nextReview.seconds <= now.seconds) {
          dueIndices.add(i);
        }
      }

      // NEW kártyák (legfeljebb newCardLimit)
      int newCardCount = 0;
      for (int i = 0;
          i < flashcards.length &&
              newCardCount < SpacedRepetitionConfig.newCardLimit;
          i++) {
        final learningData = learningDataMap[i];
        if (learningData != null && learningData.state == 'NEW') {
          dueIndices.add(i);
          newCardCount++;
        }
      }

      // Cache mentése
      _dueCardsCache[deckId] = dueIndices;
      _cacheTimestamps[deckId] = DateTime.now();

      return dueIndices;
    } catch (e) {
      debugPrint('Error getting due cards: $e');
      // Hiba esetén visszaadjuk az első 20 kártyát
      final deckDoc = await _firestore.collection('notes').doc(deckId).get();
      if (deckDoc.exists) {
        final deckData = deckDoc.data() as Map<String, dynamic>;
        final flashcards =
            List<Map<String, dynamic>>.from(deckData['flashcards'] ?? []);
        return List.generate(flashcards.length.clamp(0, 20), (i) => i);
      }
      return [];
    }
  }

  /// Batch lekérdezés timeout-tal
  static Future<Map<int, FlashcardLearningData>>
      _getBatchLearningDataWithTimeout(
    String deckId,
    int cardCount,
    String categoryId,
    Duration timeout,
  ) async {
    try {
      return await _getBatchLearningData(deckId, cardCount, categoryId)
          .timeout(timeout);
    } catch (e) {
      debugPrint('Batch query timeout, falling back to default data: $e');
      // Timeout esetén alapértelmezett adatokkal térünk vissza
      final defaultData = <int, FlashcardLearningData>{};
      for (int i = 0; i < cardCount; i++) {
        defaultData[i] = _getDefaultLearningData();
      }
      return defaultData;
    }
  }

  /// Batch lekérdezés az összes kártya tanulási adatainak lekéréséhez
  static Future<Map<int, FlashcardLearningData>> _getBatchLearningData(
    String deckId,
    int cardCount,
    String categoryId,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};

      final learningDataMap = <int, FlashcardLearningData>{};

      // Először az új útvonalról próbáljuk lekérni batch-ben
      // Firestore whereIn filter maximum 30 elemű listát engedélyez.
      // Nagyobb pakli esetén daraboljuk a lekérdezéseket 30-as blokkokra.
      final allCardIds = List.generate(cardCount, (i) => '$deckId#$i');
      const chunkSize = 30;
      final learningFutures = <Future>[];
      for (var i = 0; i < allCardIds.length; i += chunkSize) {
        final chunk =
            allCardIds.sublist(i, (i + chunkSize).clamp(0, allCardIds.length));
        learningFutures.add(_firestore
            .collection('users')
            .doc(user.uid)
            .collection('categories')
            .doc(categoryId)
            .collection('learning')
            .where(FieldPath.documentId, whereIn: chunk)
            .get());
      }

      final querySnaps = await Future.wait(learningFutures);
      for (final querySnap in querySnaps) {
        for (final doc in querySnap.docs) {
          final cardId = doc.id;
          final index = int.tryParse(cardId.split('#').last) ?? -1;
          if (index >= 0) {
            learningDataMap[index] = FlashcardLearningData.fromMap(doc.data());
          }
        }
      }

      // Hiányzó kártyák esetén alapértelmezett adatok
      for (int i = 0; i < cardCount; i++) {
        if (!learningDataMap.containsKey(i)) {
          learningDataMap[i] = _getDefaultLearningData();
        }
      }

      return learningDataMap;
    } catch (e) {
      debugPrint('Error getting batch learning data: $e');
      // Hiba esetén alapértelmezett adatokkal térünk vissza
      final defaultData = <int, FlashcardLearningData>{};
      for (int i = 0; i < cardCount; i++) {
        defaultData[i] = _getDefaultLearningData();
      }
      return defaultData;
    }
  }

  /// Pakli tanulási előzményeinek törlése
  static Future<void> resetDeckProgress(String deckId, int cardCount) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Deck kategóriájának lekérése
      final deckDoc = await _firestore.collection('notes').doc(deckId).get();
      if (!deckDoc.exists) return;

      final deckData = deckDoc.data() as Map<String, dynamic>;
      final categoryId = deckData['category'] as String? ?? 'default';

      // WriteBatch használata atomi művelethez
      final batch = _firestore.batch();

      // Kártya dokumentumok törlése
      for (int i = 0; i < cardCount; i++) {
        final cardId = '$deckId#$i';

        // Új útvonal törlése
        final newPathRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('categories')
            .doc(categoryId)
            .collection('learning')
            .doc(cardId);
        batch.delete(newPathRef);
      }

      // Kategória statisztikák törlése
      final categoryStatsRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('category_stats')
          .doc(categoryId);
      batch.delete(categoryStatsRef);

      // Deck snapshot törlése
      final deckStatsRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('deck_stats')
          .doc(deckId);
      batch.delete(deckStatsRef);

      // Atomis művelet végrehajtása
      await batch.commit();

      // Cache invalidálása
      _invalidateDeckCache(deckId);

      debugPrint('Successfully reset deck progress for deck: $deckId');
    } catch (e) {
      debugPrint('Error resetting deck progress: $e');
      rethrow;
    }
  }

  /// Jelenlegi tanulási adatok lekérése
  static Future<FlashcardLearningData> _getCurrentLearningData(
      String cardId, String categoryId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return _getDefaultLearningData();
      }

      // Új útvonal ellenőrzése
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('categories')
          .doc(categoryId)
          .collection('learning')
          .doc(cardId)
          .get();

      if (doc.exists) {
        return FlashcardLearningData.fromMap(doc.data()!);
      }

      // Legacy útvonal ellenőrzése
      final legacyDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('user_learning_data')
          .doc(cardId)
          .get();

      if (legacyDoc.exists) {
        return FlashcardLearningData.fromMap(legacyDoc.data()!);
      }

      return _getDefaultLearningData();
    } catch (e) {
      debugPrint('Error getting current learning data: $e');
      return _getDefaultLearningData();
    }
  }

  /// Alapértelmezett tanulási adatok
  static FlashcardLearningData _getDefaultLearningData() {
    final now = Timestamp.now();
    return FlashcardLearningData(
      state: 'NEW',
      interval: 0,
      easeFactor: 2.5,
      repetitions: 0,
      lastReview: now,
      nextReview: now,
      lastRating: 'Again',
    );
  }

  /// Deck snapshot frissítése
  static Future<void> _updateDeckSnapshot(
    String deckId,
    String cardIndex,
    String newRating,
    String oldRating,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('deck_stats')
          .doc(deckId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        final current = doc.exists
            ? DeckStats.fromMap(doc.data()!)
            : DeckStats(
                again: 0,
                hard: 0,
                good: 0,
                easy: 0,
                ratings: {},
                updatedAt: Timestamp.now(),
              );

        // Előző rating kivonása
        final updatedRatings = Map<String, String>.from(current.ratings);
        if (oldRating != 'Again' && updatedRatings.containsKey(cardIndex)) {
          updatedRatings.remove(cardIndex);
        }

        // Új rating hozzáadása (string index formátumban)
        if (newRating != 'Again') {
          updatedRatings[cardIndex] = newRating;
        }

        // Számlálók frissítése - előző rating levonása, új hozzáadása
        int again = current.again;
        int hard = current.hard;
        int good = current.good;
        int easy = current.easy;

        // Előző rating kivonása
        switch (oldRating) {
          case 'Again':
            again = (again - 1).clamp(0, double.infinity).toInt();
            break;
          case 'Hard':
            hard = (hard - 1).clamp(0, double.infinity).toInt();
            break;
          case 'Good':
            good = (good - 1).clamp(0, double.infinity).toInt();
            break;
          case 'Easy':
            easy = (easy - 1).clamp(0, double.infinity).toInt();
            break;
        }

        // Új rating hozzáadása
        switch (newRating) {
          case 'Again':
            again++;
            break;
          case 'Hard':
            hard++;
            break;
          case 'Good':
            good++;
            break;
          case 'Easy':
            easy++;
            break;
        }

        final updatedStats = DeckStats(
          again: again,
          hard: hard,
          good: good,
          easy: easy,
          ratings: updatedRatings,
          updatedAt: Timestamp.now(),
        );

        transaction.set(docRef, updatedStats.toMap());
      });
    } catch (e) {
      debugPrint('Error updating deck snapshot: $e');
    }
  }

  /// Kategória statisztikák frissítése
  static Future<void> _updateCategoryStats(
    String categoryId,
    String newRating,
    String oldRating,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Csak akkor frissítjük, ha változás történt
      if (newRating == oldRating) return;

      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('category_stats')
          .doc(categoryId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        final current = doc.exists
            ? CategoryStats.fromMap(doc.data()!)
            : CategoryStats(
                againCount: 0,
                hardCount: 0,
                updatedAt: Timestamp.now(),
              );

        int againCount = current.againCount;
        int hardCount = current.hardCount;

        // Előző rating kivonása
        switch (oldRating) {
          case 'Again':
            againCount = (againCount - 1).clamp(0, double.infinity).toInt();
            break;
          case 'Hard':
            hardCount = (hardCount - 1).clamp(0, double.infinity).toInt();
            break;
        }

        // Új rating hozzáadása
        switch (newRating) {
          case 'Again':
            againCount++;
            break;
          case 'Hard':
            hardCount++;
            break;
        }

        final updatedStats = CategoryStats(
          againCount: againCount,
          hardCount: hardCount,
          updatedAt: Timestamp.now(),
        );

        transaction.set(docRef, updatedStats.toMap());
      });
    } catch (e) {
      debugPrint('Error updating category stats: $e');
    }
  }

  /// Deck cache invalidálása
  static void _invalidateDeckCache(String deckId) {
    _dueCardsCache.remove(deckId);
    _cacheTimestamps.remove(deckId);
  }

  /// Deck statisztikák lekérése - kártyák állapota szerint
  static Future<Map<String, int>> getDeckStats(String deckId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};

      // Deck adatok lekérése
      final deckDoc = await _firestore.collection('notes').doc(deckId).get();
      if (!deckDoc.exists) return {};

      final deckData = deckDoc.data() as Map<String, dynamic>;
      final flashcards =
          List<Map<String, dynamic>>.from(deckData['flashcards'] ?? []);
      final categoryId = deckData['category'] as String? ?? 'default';
      final totalCards = flashcards.length;

      if (totalCards == 0) {
        return {
          'total': 0,
          'new': 0,
          'learning': 0,
          'review': 0,
          'due': 0,
        };
      }

      // Batch lekérdezés a tanulási adatokhoz
      final learningDataMap = await _getBatchLearningDataWithTimeout(
        deckId,
        totalCards,
        categoryId,
        const Duration(seconds: 30),
      );

      int newCount = 0;
      int learningCount = 0;
      int reviewCount = 0;
      int dueCount = 0;
      final now = Timestamp.now();

      for (int i = 0; i < totalCards; i++) {
        final learningData = learningDataMap[i];
        if (learningData == null) {
          newCount++;
          dueCount++; // NEW kártyák mindig esedékesek
          continue;
        }

        switch (learningData.state) {
          case 'NEW':
            newCount++;
            dueCount++;
            break;
          case 'LEARNING':
            learningCount++;
            if (learningData.nextReview.seconds <= now.seconds) {
              dueCount++;
            }
            break;
          case 'REVIEW':
            reviewCount++;
            if (learningData.nextReview.seconds <= now.seconds) {
              dueCount++;
            }
            break;
        }
      }

      return {
        'total': totalCards,
        'new': newCount,
        'learning': learningCount,
        'review': reviewCount,
        'due': dueCount,
      };
    } catch (e) {
      debugPrint('Error getting deck stats: $e');
      return {};
    }
  }
}
