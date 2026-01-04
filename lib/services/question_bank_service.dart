import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/quiz_models.dart';

class QuestionBankService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get a session of questions for the user.
  /// Uses a simplified "Session Metadata" approach:
  /// 1. Checks users/{uid}/quiz_sessions/{bankId} for cached questions.
  /// 2. If valid cache exists, returns a batch of questions from it.
  /// 3. If no cache, fetches the full bank, selects a larger batch (e.g. 50),
  ///    saves it to the session, and returns the first chunk.
  static Future<List<Question>> getQuizSession(
    String questionBankId,
    String userId, {
    int sessionSize = 10,
    int cacheSize = 50,
  }) async {
    try {
      // 1. Try to load existing session
      QuizSession? session = await _loadSession(userId, questionBankId);

      // 2. If session is empty or insufficient, replenish it from source
      if (session == null || session.batch.isEmpty) {
        session = await _generateNewSession(
            userId, questionBankId, cacheSize, sessionSize);
      }

      if (session == null || session.batch.isEmpty) {
        debugPrint('QuestionBankService: Failed to generate session.');
        return [];
      }

      // 3. Take questions for this run
      final takenQuestions = session.batch.take(sessionSize).toList();

      // 4. Update the session (remove taken questions)
      final remainingQuestions = session.batch.skip(sessionSize).toList();
      await _updateSessionBatch(userId, questionBankId, remainingQuestions);

      debugPrint(
          'QuestionBankService: Served ${takenQuestions.length} questions from session. Remaining: ${remainingQuestions.length}');
      return takenQuestions;
    } catch (e) {
      debugPrint('QuestionBankService: Error in getQuizSession: $e');
      // Fallback to legacy direct fetch if session logic fails
      return getPersonalizedQuestions(questionBankId, userId,
          maxQuestions: sessionSize);
    }
  }

  /// Get a session of questions from MULTIPLE banks.
  /// Collects questions from all specified banks, combines them, and applies
  /// the same shuffle/personalization logic as single-bank sessions.
  /// Uses a composite key (hash of bank IDs) for session caching.
  static Future<List<Question>> getQuizSessionFromMultipleBanks(
    List<String> bankIds,
    String userId, {
    int sessionSize = 10,
    int cacheSize = 50,
  }) async {
    if (bankIds.isEmpty) {
      debugPrint('QuestionBankService: No bank IDs provided.');
      return [];
    }

    // Single bank - use existing optimized method
    if (bankIds.length == 1) {
      return getQuizSession(bankIds.first, userId,
          sessionSize: sessionSize, cacheSize: cacheSize);
    }

    // Create composite key from sorted bank IDs
    final sortedIds = List<String>.from(bankIds)..sort();
    final compositeKey = sortedIds.join('_');

    try {
      // 1. Try to load existing session with composite key
      QuizSession? session = await _loadSession(userId, compositeKey);

      // 2. If session is empty or insufficient, generate from multiple banks
      if (session == null || session.batch.isEmpty) {
        session = await _generateNewSessionFromMultipleBanks(
            userId, bankIds, compositeKey, cacheSize, sessionSize);
      }

      if (session == null || session.batch.isEmpty) {
        debugPrint(
            'QuestionBankService: Failed to generate multi-bank session.');
        return [];
      }

      // 3. Take questions for this run
      final takenQuestions = session.batch.take(sessionSize).toList();

      // 4. Update the session (remove taken questions)
      final remainingQuestions = session.batch.skip(sessionSize).toList();
      await _updateSessionBatch(userId, compositeKey, remainingQuestions);

      debugPrint(
          'QuestionBankService: Served ${takenQuestions.length} questions from multi-bank session (${bankIds.length} banks). Remaining: ${remainingQuestions.length}');
      return takenQuestions;
    } catch (e) {
      debugPrint(
          'QuestionBankService: Error in getQuizSessionFromMultipleBanks: $e');
      // Fallback to direct fetch from multiple banks
      return _getPersonalizedQuestionsFromMultipleBanks(
          bankIds, userId, sessionSize);
    }
  }

  /// Generate a new session from multiple question banks
  static Future<QuizSession?> _generateNewSessionFromMultipleBanks(
      String userId,
      List<String> bankIds,
      String compositeKey,
      int targetSize,
      int minRequired) async {
    try {
      debugPrint(
          'QuestionBankService: Generating new multi-bank session for ${bankIds.length} banks');

      // 1. Fetch all banks in parallel (efficient!)
      final bankFutures = bankIds.map((id) => getQuestionBank(id));
      final banks = await Future.wait(bankFutures);

      // 2. Collect all questions from all banks
      final allQuestions = <Question>[];
      for (final bank in banks) {
        if (bank != null) {
          allQuestions.addAll(bank.questions);
        }
      }

      if (allQuestions.isEmpty) {
        debugPrint(
            'QuestionBankService: No questions found in any of the ${bankIds.length} banks');
        return null;
      }

      // 3. Filter out recently served questions
      final servedQuestions = await _getRecentlyServedQuestions(userId);
      final servedHashes = servedQuestions.map((sq) => sq.docId).toSet();

      final available =
          allQuestions.where((q) => !servedHashes.contains(q.hash)).toList();

      // 4. Shuffle (PRIORITY: preserve existing shuffle logic!)
      available.shuffle();

      // 5. Implement fallback if we ran out of "fresh" questions
      List<Question> selected;
      if (available.length < minRequired) {
        final fullShuffled = List<Question>.from(allQuestions)..shuffle();
        selected = fullShuffled.take(targetSize).toList();
      } else {
        selected = available.take(targetSize).toList();
      }

      final session = QuizSession(
          bankId: compositeKey, batch: selected, lastUpdated: DateTime.now());

      // Save entire batch to Firestore
      await _updateSessionBatch(userId, compositeKey, selected);

      debugPrint(
          'QuestionBankService: Generated session with ${selected.length} questions from ${bankIds.length} banks');
      return session;
    } catch (e) {
      debugPrint('Error generating new multi-bank session: $e');
      return null;
    }
  }

  /// Fallback: Get personalized questions from multiple banks
  static Future<List<Question>> _getPersonalizedQuestionsFromMultipleBanks(
      List<String> bankIds, String userId, int maxQuestions) async {
    try {
      // Fetch all banks in parallel
      final bankFutures = bankIds.map((id) => getQuestionBank(id));
      final banks = await Future.wait(bankFutures);

      // Collect all questions
      final allQuestions = <Question>[];
      for (final bank in banks) {
        if (bank != null) {
          allQuestions.addAll(bank.questions);
        }
      }

      if (allQuestions.isEmpty) return [];

      // Filter out recently served
      final servedQuestions = await _getRecentlyServedQuestions(userId);
      final servedHashes = servedQuestions.map((sq) => sq.docId).toSet();

      final available =
          allQuestions.where((q) => !servedHashes.contains(q.hash)).toList();

      // Shuffle and select
      available.shuffle();
      final selected = available.take(maxQuestions).toList();

      // Fill if needed
      if (selected.length < maxQuestions) {
        final remaining = maxQuestions - selected.length;
        final selectedHashes = selected.map((q) => q.hash).toSet();
        final additional = allQuestions
            .where((q) => !selectedHashes.contains(q.hash))
            .take(remaining)
            .toList();
        selected.addAll(additional);
      }

      // Record as served
      if (selected.isNotEmpty) {
        await _recordServedQuestions(userId, selected);
      }

      debugPrint(
          'QuestionBankService: Fallback selected ${selected.length} questions from ${bankIds.length} banks');
      return selected;
    } catch (e) {
      debugPrint('QuestionBankService: Error in multi-bank fallback: $e');
      return [];
    }
  }

  /// Load session metadata from Firestore
  static Future<QuizSession?> _loadSession(String userId, String bankId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('quiz_sessions')
          .doc(bankId)
          .get();

      if (doc.exists && doc.data() != null) {
        return QuizSession.fromMap(bankId, doc.data()!);
      }
    } catch (e) {
      debugPrint('Error loading session: $e');
    }
    return null;
  }

  /// Update the session with remaining questions
  static Future<void> _updateSessionBatch(
      String userId, String bankId, List<Question> remaining) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('quiz_sessions')
          .doc(bankId)
          .set({
        'batch': remaining.map((q) => q.toMap()).toList(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating session batch: $e');
    }
  }

  /// Generate a new session by fetching from source and filtering
  static Future<QuizSession?> _generateNewSession(
      String userId, String bankId, int targetSize, int minRequired) async {
    try {
      debugPrint('QuestionBankService: Generating new session for $bankId');

      // 1. Fetch source bank (The "heavy" lift)
      final bank = await getQuestionBank(bankId);
      if (bank == null) return null;

      // 2. Filter out history (only if we have enough questions to care)
      //    We can reuse the logic from getPersonalizedQuestions but for a larger batch
      final servedQuestions = await _getRecentlyServedQuestions(userId);
      final servedHashes = servedQuestions.map((sq) => sq.docId).toSet();

      final available =
          bank.questions.where((q) => !servedHashes.contains(q.hash)).toList();

      // Shuffle
      available.shuffle();

      // Implement fallback if we ran out of "fresh" questions
      List<Question> selected;
      if (available.length < minRequired) {
        // Not enough fresh questions, mix in some served ones (or reset history concept)
        // For now, simpler: just fill up from the full bank excluding duplicates in current selection if possible
        // But effectively we just shuffle the whole bank again.
        final fullShuffled = List<Question>.from(bank.questions)..shuffle();
        selected = fullShuffled.take(targetSize).toList();
      } else {
        selected = available.take(targetSize).toList();
      }

      // Record these as served?
      // STRICTLY SPEAKING: We record them as served when they are actually *taken* from the batch in `getQuizSession`.
      // recording them here would premptively mark 50 questions as served even if user quits after 10.
      // So we do NOT call _recordServedQuestions here. We rely on history filter for subsequent generations.

      final session = QuizSession(
          bankId: bankId, batch: selected, lastUpdated: DateTime.now());

      // Save entire batch to Firestore
      await _updateSessionBatch(userId, bankId, selected);

      return session;
    } catch (e) {
      debugPrint('Error generating new session: $e');
      return null;
    }
  }

  /// Fetch a question bank by ID
  static Future<QuestionBank?> getQuestionBank(String questionBankId) async {
    try {
      final doc = await _firestore
          .collection('question_banks')
          .doc(questionBankId)
          .get();

      if (!doc.exists) {
        debugPrint(
            'QuestionBankService: Question bank not found: $questionBankId');
        return null;
      }

      return QuestionBank.fromMap(questionBankId, doc.data()!);
    } catch (e) {
      debugPrint('QuestionBankService: Error fetching question bank: $e');
      return null;
    }
  }

  /// Get questions from a question bank with personalization (filter out recently served)
  static Future<List<Question>> getPersonalizedQuestions(
    String questionBankId,
    String userId, {
    int maxQuestions = 10,
  }) async {
    try {
      // Fetch question bank
      final questionBank = await getQuestionBank(questionBankId);
      if (questionBank == null) {
        debugPrint(
            'QuestionBankService: Question bank not found, returning empty list');
        return [];
      }

      // Get recently served questions (last 1 hour)
      final servedQuestions = await _getRecentlyServedQuestions(userId);
      final servedHashes = servedQuestions.map((sq) => sq.docId).toSet();

      // Filter out recently served questions
      final availableQuestions = questionBank.questions
          .where((question) => !servedHashes.contains(question.hash))
          .toList();

      // Shuffle and select up to maxQuestions
      availableQuestions.shuffle();
      final selectedQuestions = availableQuestions.take(maxQuestions).toList();

      // If we don't have enough questions, fill from the full bank
      if (selectedQuestions.length < maxQuestions) {
        final remainingNeeded = maxQuestions - selectedQuestions.length;
        final selectedHashes = selectedQuestions.map((q) => q.hash).toSet();

        final additionalQuestions = questionBank.questions
            .where((question) => !selectedHashes.contains(question.hash))
            .take(remainingNeeded)
            .toList();

        selectedQuestions.addAll(additionalQuestions);
      }

      // Record the selected questions as served
      if (selectedQuestions.isNotEmpty) {
        await _recordServedQuestions(userId, selectedQuestions);
      }

      debugPrint(
          'QuestionBankService: Selected ${selectedQuestions.length} questions for user $userId');
      return selectedQuestions;
    } catch (e) {
      debugPrint(
          'QuestionBankService: Error getting personalized questions: $e');
      // Fallback: return random questions from the full bank
      return await _getFallbackQuestions(questionBankId, maxQuestions);
    }
  }

  /// Get recently served questions (within last 1 hour)
  static Future<List<ServedQuestion>> _getRecentlyServedQuestions(
      String userId) async {
    try {
      final now = DateTime.now();
      final oneHourAgo = now.subtract(const Duration(hours: 1));

      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('served_questions')
          .where('lastServed', isGreaterThan: Timestamp.fromDate(oneHourAgo))
          .get();

      return querySnapshot.docs
          .map((doc) => ServedQuestion.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint(
          'QuestionBankService: Error getting recently served questions: $e');
      return [];
    }
  }

  /// Record questions as served with TTL
  static Future<void> _recordServedQuestions(
      String userId, List<Question> questions) async {
    try {
      final batch = _firestore.batch();
      final now = DateTime.now();
      final ttl = now.add(const Duration(hours: 1));

      for (final question in questions) {
        final docRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('served_questions')
            .doc(question.hash);

        batch.set(docRef, {
          'lastServed': FieldValue.serverTimestamp(),
          'ttl': Timestamp.fromDate(ttl),
        });
      }

      await batch.commit();
      debugPrint(
          'QuestionBankService: Recorded ${questions.length} questions as served');
    } catch (e) {
      debugPrint('QuestionBankService: Error recording served questions: $e');
    }
  }

  /// Fallback method to get random questions when personalization fails
  static Future<List<Question>> _getFallbackQuestions(
      String questionBankId, int maxQuestions) async {
    try {
      final questionBank = await getQuestionBank(questionBankId);
      if (questionBank == null) {
        return [];
      }

      final questions = List<Question>.from(questionBank.questions);
      questions.shuffle();
      return questions.take(maxQuestions).toList();
    } catch (e) {
      debugPrint('QuestionBankService: Error in fallback questions: $e');
      return [];
    }
  }

  /// Clear expired served questions (cleanup method)
  static Future<void> clearExpiredServedQuestions(String userId) async {
    try {
      final now = DateTime.now();

      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('served_questions')
          .where('ttl', isLessThan: Timestamp.fromDate(now))
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in querySnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        debugPrint(
            'QuestionBankService: Cleared ${querySnapshot.docs.length} expired served questions');
      }
    } catch (e) {
      debugPrint(
          'QuestionBankService: Error clearing expired served questions: $e');
    }
  }
}
