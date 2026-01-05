import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/flashcard_learning_data.dart';
import '../core/learning_algorithm.dart';

/// Egy függő tanulási adat frissítés reprezentációja.
class PendingLearningUpdate {
  final String cardId;
  final String categoryId;
  final FlashcardLearningData newData;
  final DateTime queuedAt;

  PendingLearningUpdate({
    required this.cardId,
    required this.categoryId,
    required this.newData,
    required this.queuedAt,
  });

  Map<String, dynamic> toMap() => newData.toMap();
}

/// Tanulási adatok batch íróeszköze.
///
/// Az írásokat memóriában gyűjti és egyetlen batch műveletben küldi el:
/// - Session végén (explicit flush hívás)
/// - Debounce idő lejártakor (alapértelmezett: 5 másodperc)
/// - Maximális queue méret elérésekor (alapértelmezett: 50)
///
/// Használat:
/// ```dart
/// final writer = LearningBatchWriter();
/// await writer.queueUpdate(cardId, categoryId, newData);
/// // ... később ...
/// await writer.flush(); // Session végén
/// ```
class LearningBatchWriter {
  static final LearningBatchWriter _instance = LearningBatchWriter._internal();
  factory LearningBatchWriter() => _instance;
  LearningBatchWriter._internal();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Függő frissítések listája
  final List<PendingLearningUpdate> _pendingUpdates = [];

  /// Debounce timer
  Timer? _debounceTimer;

  /// Debounce időtartam (alapértelmezett: 5 másodperc)
  static const Duration debounceDelay = Duration(seconds: 5);

  /// Maximális queue méret mielőtt automatikus flush
  static const int maxQueueSize = 50;

  /// Jelzi, hogy éppen flush van folyamatban
  bool _isFlushing = false;

  /// Függő frissítések száma
  int get pendingCount => _pendingUpdates.length;

  /// Van-e függő frissítés
  bool get hasPendingUpdates => _pendingUpdates.isNotEmpty;

  /// Új tanulási adat frissítés hozzáadása a queue-hoz.
  ///
  /// A frissítés nem történik meg azonnal, hanem:
  /// - 5 másodperc tétlenség után, VAGY
  /// - Queue méret elérése esetén, VAGY
  /// - Explicit flush() hívásra
  Future<void> queueUpdate({
    required String cardId,
    required String categoryId,
    required FlashcardLearningData currentData,
    required String rating,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('LearningBatchWriter: No authenticated user');
      return;
    }

    // Új állapot kalkulálása
    final newData = LearningAlgorithm.calculateNextState(currentData, rating);

    // Hozzáadás a queue-hoz (ha már van ugyanazzal a cardId-val, felülírjuk)
    _pendingUpdates.removeWhere((u) => u.cardId == cardId);
    _pendingUpdates.add(PendingLearningUpdate(
      cardId: cardId,
      categoryId: categoryId,
      newData: newData,
      queuedAt: DateTime.now(),
    ));

    debugPrint(
        'LearningBatchWriter: Queued update for $cardId (total: ${_pendingUpdates.length})');

    // Debounce timer újraindítása
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () async {
      debugPrint('LearningBatchWriter: Debounce triggered, flushing...');
      await flush();
    });

    // Ha elértük a max queue méretet, azonnal flush
    if (_pendingUpdates.length >= maxQueueSize) {
      debugPrint('LearningBatchWriter: Max queue size reached, flushing...');
      await flush();
    }
  }

  /// Az összes függő frissítés elküldése egyetlen batch műveletben.
  ///
  /// Hívd meg session végén (pl. tanulás befejezése, képernyő elhagyása).
  Future<void> flush() async {
    if (_isFlushing || _pendingUpdates.isEmpty) {
      debugPrint(
          'LearningBatchWriter: Flush skipped (flushing: $_isFlushing, pending: ${_pendingUpdates.length})');
      return;
    }

    _isFlushing = true;
    _debounceTimer?.cancel();

    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('LearningBatchWriter: No user for flush');
      _isFlushing = false;
      return;
    }

    // Másolat a biztonságos iterációhoz
    final updatesToFlush = List<PendingLearningUpdate>.from(_pendingUpdates);
    _pendingUpdates.clear();

    debugPrint(
        'LearningBatchWriter: Flushing ${updatesToFlush.length} updates...');

    try {
      // Firestore batch maximum 500 művelet
      const batchLimit = 500;

      for (var i = 0; i < updatesToFlush.length; i += batchLimit) {
        final chunk = updatesToFlush.sublist(
          i,
          (i + batchLimit).clamp(0, updatesToFlush.length),
        );

        final batch = _firestore.batch();

        for (final update in chunk) {
          final docRef = _firestore
              .collection('users')
              .doc(user.uid)
              .collection('categories')
              .doc(update.categoryId)
              .collection('learning')
              .doc(update.cardId);

          batch.set(docRef, update.toMap());
        }

        await batch.commit();
        debugPrint(
            'LearningBatchWriter: Committed batch of ${chunk.length} updates');
      }

      debugPrint('LearningBatchWriter: Flush completed successfully');
    } catch (e) {
      // Hiba esetén visszatesszük a queue-ba
      debugPrint('LearningBatchWriter: Flush error: $e');
      _pendingUpdates.insertAll(0, updatesToFlush);
      rethrow;
    } finally {
      _isFlushing = false;
    }
  }

  /// Queue törlése mentés nélkül (pl. felhasználó logout esetén).
  void clear() {
    _debounceTimer?.cancel();
    _pendingUpdates.clear();
    debugPrint('LearningBatchWriter: Queue cleared');
  }

  /// Dispose: flush és cleanup.
  Future<void> dispose() async {
    await flush();
    clear();
  }
}
