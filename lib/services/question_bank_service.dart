import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/quiz_models.dart';

class QuestionBankService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
