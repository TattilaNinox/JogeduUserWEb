import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/flashcard_learning_data.dart';

/// Tiszta SM-2 (Spaced Repetition) algoritmus implementáció.
/// Ez az osztály NEM tartalmaz adatbázis műveleteket, csak matematikai logikát.
/// Felelőssége: kiszámolni a következő tanulási állapotot egy értékelés alapján.
class LearningAlgorithm {
  /// SM-2 algoritmus alapú következő állapot kalkulálása
  ///
  /// [current] - A jelenlegi tanulási állapot
  /// [rating] - A felhasználó értékelése: "Again" | "Hard" | "Good" | "Easy"
  ///
  /// Visszatér az új tanulási állapottal (interval, easeFactor, stb.)
  static FlashcardLearningData calculateNextState(
    FlashcardLearningData current,
    String rating,
  ) {
    final now = Timestamp.now();
    double newEaseFactor = current.easeFactor;
    int newInterval = current.interval;
    int newRepetitions = current.repetitions;
    String newState = current.state;

    switch (rating) {
      case 'Again':
        // Again: kártya LEARNING állapotba kerül, repetitions nullázódik
        newEaseFactor = (current.easeFactor - 0.2).clamp(
          SpacedRepetitionConfig.minEaseFactor,
          SpacedRepetitionConfig.maxEaseFactor,
        );
        newRepetitions = 0;
        newState = 'LEARNING';

        if (current.state == 'REVIEW') {
          // REVIEW-ból visszaesés: lapse step (10 perc)
          newInterval = SpacedRepetitionConfig.lapseSteps.first;
        } else {
          // NEW/LEARNING-ből: első learning step (1 perc)
          newInterval = SpacedRepetitionConfig.learningSteps.first;
        }
        break;

      case 'Hard':
        newEaseFactor = (current.easeFactor - 0.15).clamp(
          SpacedRepetitionConfig.minEaseFactor,
          SpacedRepetitionConfig.maxEaseFactor,
        );

        if (current.state == 'NEW' || current.state == 'LEARNING') {
          // NEW/LEARNING: következő learning step (10 perc)
          newState = 'LEARNING';
          final currentStepIndex =
              SpacedRepetitionConfig.learningSteps.indexOf(current.interval);
          if (currentStepIndex >= 0 &&
              currentStepIndex <
                  SpacedRepetitionConfig.learningSteps.length - 1) {
            newInterval =
                SpacedRepetitionConfig.learningSteps[currentStepIndex + 1];
          } else {
            newInterval = SpacedRepetitionConfig.learningSteps.first;
          }
        } else {
          // REVIEW: kis növekedés (interval * 1.2, min 1 nap)
          newState = 'REVIEW';
          newInterval = (current.interval * 1.2)
              .clamp(1440, SpacedRepetitionConfig.maxInterval)
              .round();
        }
        break;

      case 'Good':
        if (current.state == 'NEW' || current.state == 'LEARNING') {
          // NEW/LEARNING: következő learning step vagy graduation
          final currentStepIndex =
              SpacedRepetitionConfig.learningSteps.indexOf(current.interval);
          if (currentStepIndex >= 0 &&
              currentStepIndex <
                  SpacedRepetitionConfig.learningSteps.length - 1) {
            // Van még learning step
            newState = 'LEARNING';
            newInterval =
                SpacedRepetitionConfig.learningSteps[currentStepIndex + 1];
          } else {
            // Utolsó learning step: graduation REVIEW-ba
            newState = 'REVIEW';
            newInterval = 4 * 24 * 60; // 4 nap
            newRepetitions = current.repetitions + 1;
          }
        } else {
          // REVIEW: standard számítás (interval * easeFactor)
          newState = 'REVIEW';
          newInterval = (current.interval * current.easeFactor).round();
          newRepetitions = current.repetitions + 1;
        }
        break;

      case 'Easy':
        newEaseFactor = (current.easeFactor + 0.15).clamp(
          SpacedRepetitionConfig.minEaseFactor,
          SpacedRepetitionConfig.maxEaseFactor,
        );

        if (current.state == 'NEW' || current.state == 'LEARNING') {
          // NEW/LEARNING: azonnali graduation REVIEW-ba bónusz intervallummal
          newState = 'REVIEW';
          newInterval = (4 * 24 * 60 * SpacedRepetitionConfig.easyBonus)
              .round(); // 4 nap * easyBonus
          newRepetitions = current.repetitions + 1;
        } else {
          // REVIEW: bónusz növekedés (interval * easeFactor * easyBonus)
          newState = 'REVIEW';
          newInterval = (current.interval *
                  current.easeFactor *
                  SpacedRepetitionConfig.easyBonus)
              .round();
          newRepetitions = current.repetitions + 1;
        }
        break;
    }

    // Intervallum korlát
    newInterval = newInterval.clamp(0, SpacedRepetitionConfig.maxInterval);

    final nextReview = Timestamp.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch + (newInterval * 60 * 1000),
    );

    return current.copyWith(
      state: newState,
      interval: newInterval,
      easeFactor: newEaseFactor,
      repetitions: newRepetitions,
      lastReview: now,
      nextReview: nextReview,
      lastRating: rating,
    );
  }
}
