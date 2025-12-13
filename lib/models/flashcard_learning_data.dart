import 'package:cloud_firestore/cloud_firestore.dart';

class FlashcardLearningData {
  final String state; // "NEW" | "LEARNING" | "REVIEW"
  final int interval; // percben tárolt időköz
  final double easeFactor; // intervallum növekedésének üteme
  final int repetitions; // egymás utáni sikeres felidézések száma
  final Timestamp lastReview; // utolsó értékelés időpontja
  final Timestamp nextReview; // következő ismétlés időpontja
  final String lastRating; // utolsó minősítés (Again/Hard/Good/Easy)

  const FlashcardLearningData({
    required this.state,
    required this.interval,
    required this.easeFactor,
    required this.repetitions,
    required this.lastReview,
    required this.nextReview,
    required this.lastRating,
  });

  factory FlashcardLearningData.fromMap(Map<String, dynamic> data) {
    return FlashcardLearningData(
      state: data['state'] as String? ?? 'NEW',
      interval: data['interval'] as int? ?? 0,
      easeFactor: (data['easeFactor'] as num?)?.toDouble() ?? 2.5,
      repetitions: data['repetitions'] as int? ?? 0,
      lastReview: data['lastReview'] as Timestamp? ?? Timestamp.now(),
      nextReview: data['nextReview'] as Timestamp? ?? Timestamp.now(),
      lastRating: data['lastRating'] as String? ?? 'Again',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'state': state,
      'interval': interval,
      'easeFactor': easeFactor,
      'repetitions': repetitions,
      'lastReview': lastReview,
      'nextReview': nextReview,
      'lastRating': lastRating,
    };
  }

  FlashcardLearningData copyWith({
    String? state,
    int? interval,
    double? easeFactor,
    int? repetitions,
    Timestamp? lastReview,
    Timestamp? nextReview,
    String? lastRating,
  }) {
    return FlashcardLearningData(
      state: state ?? this.state,
      interval: interval ?? this.interval,
      easeFactor: easeFactor ?? this.easeFactor,
      repetitions: repetitions ?? this.repetitions,
      lastReview: lastReview ?? this.lastReview,
      nextReview: nextReview ?? this.nextReview,
      lastRating: lastRating ?? this.lastRating,
    );
  }
}

class SpacedRepetitionConfig {
  static const List<int> learningSteps = [1, 10, 1440]; // 1p, 10p, 1 nap
  static const List<int> lapseSteps = [10]; // REVIEW fázisban felejtett kártya
  static const double easyBonus = 1.3;
  static const int newCardLimit = 20;
  static const double minEaseFactor = 1.3;
  static const double maxEaseFactor = 2.5;
  static const int maxInterval = 60 * 24 * 60; // 60 nap percben
}

class DeckStats {
  final int again;
  final int hard;
  final int good;
  final int easy;
  final Map<String, String> ratings; // index -> rating
  final Timestamp updatedAt;

  const DeckStats({
    required this.again,
    required this.hard,
    required this.good,
    required this.easy,
    required this.ratings,
    required this.updatedAt,
  });

  factory DeckStats.fromMap(Map<String, dynamic> data) {
    return DeckStats(
      again: data['again'] as int? ?? 0,
      hard: data['hard'] as int? ?? 0,
      good: data['good'] as int? ?? 0,
      easy: data['easy'] as int? ?? 0,
      ratings: Map<String, String>.from(data['ratings'] as Map? ?? {}),
      updatedAt: data['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'again': again,
      'hard': hard,
      'good': good,
      'easy': easy,
      'ratings': ratings,
      'updatedAt': updatedAt,
    };
  }
}

class CategoryStats {
  final int againCount;
  final int hardCount;
  final Timestamp updatedAt;

  const CategoryStats({
    required this.againCount,
    required this.hardCount,
    required this.updatedAt,
  });

  factory CategoryStats.fromMap(Map<String, dynamic> data) {
    return CategoryStats(
      againCount: data['againCount'] as int? ?? 0,
      hardCount: data['hardCount'] as int? ?? 0,
      updatedAt: data['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'againCount': againCount,
      'hardCount': hardCount,
      'updatedAt': updatedAt,
    };
  }
}
