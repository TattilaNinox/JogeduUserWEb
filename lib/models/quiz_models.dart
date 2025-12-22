class Option {
  final String text;
  final bool isCorrect;
  final String rationale;

  const Option({
    required this.text,
    required this.isCorrect,
    required this.rationale,
  });

  factory Option.fromMap(Map<String, dynamic> map) {
    return Option(
      text: map['text'] as String? ?? '',
      isCorrect: map['isCorrect'] as bool? ?? false,
      rationale: map['rationale'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'isCorrect': isCorrect,
      'rationale': rationale,
    };
  }
}

class Question {
  final String question;
  final List<Option> options;
  final String? tag;
  final String? noteId;
  final String? noteStatus;

  const Question({
    required this.question,
    required this.options,
    this.tag,
    this.noteId,
    this.noteStatus,
  });

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      question: map['question'] as String? ?? '',
      options: (map['options'] as List<dynamic>? ?? [])
          .map((option) => Option.fromMap(option as Map<String, dynamic>))
          .toList(),
      tag: map['tag'] as String?,
      noteId: map['noteId'] as String?,
      noteStatus: map['noteStatus'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'options': options.map((option) => option.toMap()).toList(),
      if (tag != null) 'tag': tag,
      if (noteId != null) 'noteId': noteId,
      if (noteStatus != null) 'noteStatus': noteStatus,
    };
  }

  /// Generate a hash for the question to use as document ID in served_questions
  String get hash => question.hashCode.toString();
}

class QuestionBank {
  final String id;
  final List<Question> questions;

  const QuestionBank({
    required this.id,
    required this.questions,
  });

  factory QuestionBank.fromMap(String id, Map<String, dynamic> map) {
    return QuestionBank(
      id: id,
      questions: (map['questions'] as List<dynamic>? ?? [])
          .map((question) => Question.fromMap(question as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'questions': questions.map((question) => question.toMap()).toList(),
    };
  }
}

class ServedQuestion {
  final String docId;
  final DateTime lastServed;
  final DateTime ttl;

  const ServedQuestion({
    required this.docId,
    required this.lastServed,
    required this.ttl,
  });

  factory ServedQuestion.fromMap(String docId, Map<String, dynamic> map) {
    return ServedQuestion(
      docId: docId,
      lastServed: (map['lastServed'] as dynamic).toDate(),
      ttl: (map['ttl'] as dynamic).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lastServed': lastServed,
      'ttl': ttl,
    };
  }

  bool get isExpired => DateTime.now().isAfter(ttl);
}

class QuizResult {
  final int score;
  final int totalQuestions;
  final List<QuestionResult> questionResults;

  const QuizResult({
    required this.score,
    required this.totalQuestions,
    required this.questionResults,
  });

  double get percentage =>
      totalQuestions > 0 ? (score / totalQuestions) * 100 : 0.0;
}

class QuestionResult {
  final Question question;
  final List<int> selectedIndices;
  final List<int> correctIndices;
  final bool isCorrect;

  const QuestionResult({
    required this.question,
    required this.selectedIndices,
    required this.correctIndices,
    required this.isCorrect,
  });
}
