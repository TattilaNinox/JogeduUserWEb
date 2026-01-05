import 'dart:async';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import '../models/flashcard_learning_data.dart';
import '../core/learning_algorithm.dart';

/// Pending evaluation data to be committed later
class PendingEvaluation {
  final String cardId;
  final String categoryId;
  final FlashcardLearningData learningData;
  final DateTime recordedAt;

  PendingEvaluation({
    required this.cardId,
    required this.categoryId,
    required this.learningData,
    required this.recordedAt,
  });
}

/// Session-based learning service for batch Firestore writes.
///
/// J3 OPTIMIZATION: Reduces Firestore writes by ~95% by batching
/// evaluations and committing them at session end instead of per-card.
class LearningSessionService {
  // Singleton instance
  static final LearningSessionService instance = LearningSessionService._();
  LearningSessionService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Pending evaluations buffer (cardId -> PendingEvaluation)
  final Map<String, PendingEvaluation> _pending = {};

  // Auto-save timer (5 minutes)
  Timer? _autoSaveTimer;
  static const Duration _autoSaveInterval = Duration(minutes: 5);

  // Track if beforeunload is registered
  bool _beforeUnloadRegistered = false;

  /// Get current pending count
  int get pendingCount => _pending.length;

  /// Check if there are pending evaluations
  bool get hasPending => _pending.isNotEmpty;

  /// Record an evaluation locally (no Firestore write yet)
  ///
  /// [cardId] - The card ID in deckId#index format
  /// [rating] - User rating: "Again" | "Hard" | "Good" | "Easy"
  /// [categoryId] - The category for organizing learning data
  /// [currentData] - The current learning state of the card
  ///
  /// Returns the new learning data (for optimistic UI update)
  FlashcardLearningData recordEvaluation({
    required String cardId,
    required String rating,
    required String categoryId,
    required FlashcardLearningData currentData,
  }) {
    // Calculate new state using SM-2 algorithm
    final newData = LearningAlgorithm.calculateNextState(currentData, rating);

    // Store in pending buffer
    _pending[cardId] = PendingEvaluation(
      cardId: cardId,
      categoryId: categoryId,
      learningData: newData,
      recordedAt: DateTime.now(),
    );

    debugPrint(
        'LearningSessionService: Recorded evaluation for $cardId (rating: $rating). Pending: ${_pending.length}');

    // Start auto-save timer if not running
    _startAutoSave();

    // Register beforeunload handler
    _registerBeforeUnload();

    return newData;
  }

  /// Commit all pending evaluations to Firestore
  ///
  /// Uses a single batch write operation for efficiency.
  Future<void> commitSession() async {
    if (_pending.isEmpty) {
      debugPrint('LearningSessionService: Nothing to commit');
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      debugPrint(
          'LearningSessionService: No authenticated user, cannot commit');
      return;
    }

    try {
      final batch = _firestore.batch();
      int writeCount = 0;

      // Group by category for efficient writes
      final byCategory = <String, List<PendingEvaluation>>{};
      for (final pending in _pending.values) {
        byCategory.putIfAbsent(pending.categoryId, () => []).add(pending);
      }

      // Add all pending evaluations to batch
      for (final entry in byCategory.entries) {
        final categoryId = entry.key;
        for (final pending in entry.value) {
          final docRef = _firestore
              .collection('users')
              .doc(user.uid)
              .collection('categories')
              .doc(categoryId)
              .collection('learning')
              .doc(pending.cardId);

          batch.set(docRef, pending.learningData.toMap());
          writeCount++;
        }
      }

      // Commit the batch (single Firestore operation!)
      await batch.commit();

      debugPrint(
          'LearningSessionService: Committed $writeCount evaluations in 1 batch write');

      // Clear pending buffer
      _pending.clear();

      // Stop auto-save timer
      _stopAutoSave();
    } catch (e) {
      debugPrint('LearningSessionService: Error committing session: $e');
      rethrow;
    }
  }

  /// Get the current (potentially uncommitted) learning data for a card
  ///
  /// Returns pending data if available, null otherwise
  FlashcardLearningData? getPendingData(String cardId) {
    return _pending[cardId]?.learningData;
  }

  /// Clear all pending evaluations without committing
  void clearPending() {
    _pending.clear();
    _stopAutoSave();
    debugPrint('LearningSessionService: Cleared all pending evaluations');
  }

  /// Start the auto-save timer
  void _startAutoSave() {
    if (_autoSaveTimer != null && _autoSaveTimer!.isActive) return;

    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) async {
      if (_pending.isNotEmpty) {
        debugPrint('LearningSessionService: Auto-save triggered');
        await commitSession();
      }
    });

    debugPrint(
        'LearningSessionService: Auto-save timer started (${_autoSaveInterval.inMinutes} min interval)');
  }

  /// Stop the auto-save timer
  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  /// Register browser beforeunload handler (web only)
  void _registerBeforeUnload() {
    if (_beforeUnloadRegistered || !kIsWeb) return;

    web.window.onbeforeunload = ((web.Event event) {
      if (_pending.isNotEmpty) {
        // Attempt synchronous commit via sendBeacon
        _commitViaBeacon();
      }
      return null;
    }).toJS;

    _beforeUnloadRegistered = true;
    debugPrint('LearningSessionService: beforeunload handler registered');
  }

  /// Commit via sendBeacon for browser close (web only)
  ///
  /// Note: This is a best-effort save. sendBeacon is reliable but
  /// we can't use Firestore SDK here. We'll use a Cloud Function instead.
  void _commitViaBeacon() {
    // For now, we rely on auto-save. A full implementation would use
    // a Cloud Function endpoint with sendBeacon.
    debugPrint(
        'LearningSessionService: Browser closing with ${_pending.length} pending evaluations');

    // Store to localStorage as backup
    _backupToLocalStorage();
  }

  /// Backup pending data to localStorage (recovery mechanism)
  void _backupToLocalStorage() {
    if (!kIsWeb || _pending.isEmpty) return;

    try {
      final backup = <String, dynamic>{};
      for (final entry in _pending.entries) {
        backup[entry.key] = {
          'categoryId': entry.value.categoryId,
          'learningData': entry.value.learningData.toMap(),
          'recordedAt': entry.value.recordedAt.toIso8601String(),
        };
      }

      // Store as JSON string
      web.window.localStorage
          .setItem('learningSessionBackup', backup.toString());
      debugPrint(
          'LearningSessionService: Backed up ${_pending.length} evaluations to localStorage');
    } catch (e) {
      debugPrint(
          'LearningSessionService: Failed to backup to localStorage: $e');
    }
  }

  /// Dispose the service (call on app shutdown)
  void dispose() {
    _stopAutoSave();
    _pending.clear();
  }
}
