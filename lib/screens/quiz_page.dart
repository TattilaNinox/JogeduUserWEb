import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/quiz_models.dart';
import '../services/question_bank_service.dart';
import '../widgets/quiz_viewer_dual.dart';

class QuizPage extends StatefulWidget {
  final String noteId;
  final List<String> questionBankIds;
  final String quizType;

  const QuizPage({
    super.key,
    required this.noteId,
    required this.questionBankIds,
    required this.quizType,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  List<Question> _questions = [];
  bool _isLoading = true;
  String? _error;
  bool _showFallbackWarning = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _showFallbackWarning = false;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Nincs bejelentkezve felhasználó';
          _isLoading = false;
        });
        return;
      }

      // Try to get personalized questions first
      final questions =
          await QuestionBankService.getQuizSessionFromMultipleBanks(
        widget.questionBankIds,
        user.uid,
        sessionSize: 10,
        cacheSize: 50,
      );

      if (questions.isEmpty) {
        // Fallback to direct fetch
        final fallbackQuestions =
            await QuestionBankService.getQuizSessionFromMultipleBanks(
          widget.questionBankIds,
          user.uid,
          sessionSize: 10,
          cacheSize: 50,
        );

        if (fallbackQuestions.isEmpty) {
          setState(() {
            _error = 'Nem sikerült betölteni a kérdéseket';
            _isLoading = false;
          });
          return;
        }

        setState(() {
          _questions = fallbackQuestions;
          _showFallbackWarning = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _questions = questions;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Hiba a kérdések betöltése közben: $e';
        _isLoading = false;
      });
    }
  }

  void _handleQuizComplete(QuizResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kvíz Eredménye'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pontszám: ${result.score} / ${result.totalQuestions}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Százalék: ${result.percentage.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: result.percentage / 100,
              backgroundColor: Colors.grey.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                result.percentage >= 70 ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Close quiz page
            },
            child: const Text('Bezárás'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _restartQuiz();
            },
            child: const Text('Újra'),
          ),
        ],
      ),
    );
  }

  void _restartQuiz() {
    _loadQuestions();
  }

  void _showFallbackWarningSnackbar() {
    if (_showFallbackWarning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'A kérdések személyre szabása nem elérhető, véletlenszerű kérdések jelennek meg'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kvíz Betöltése'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Kérdések betöltése...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Hiba'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadQuestions,
                child: const Text('Újrapróbálás'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Vissza'),
              ),
            ],
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Nincs Kérdés'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.quiz_outlined,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'Nincs elérhető kérdés',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Show fallback warning if needed
    _showFallbackWarningSnackbar();

    // Determine quiz type and show appropriate viewer
    if (widget.quizType.contains('dual')) {
      return QuizViewerDual(
        questions: _questions,
        onQuizComplete: _handleQuizComplete,
        onClose: () => Navigator.of(context).pop(),
      );
    } else {
      // For other quiz types, we could add more viewers here
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kvíz'),
        ),
        body: const Center(
          child: Text('Ez a kvíz típus még nem támogatott'),
        ),
      );
    }
  }
}
