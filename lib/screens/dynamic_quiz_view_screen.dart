import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../widgets/quiz_viewer.dart';
import '../widgets/quiz_viewer_dual.dart';
import '../models/quiz_models.dart';
import '../widgets/audio_preview_player.dart';
import '../utils/filter_storage.dart';

class DynamicQuizViewScreen extends StatefulWidget {
  final String noteId;

  const DynamicQuizViewScreen({super.key, required this.noteId});

  @override
  State<DynamicQuizViewScreen> createState() => _DynamicQuizViewScreenState();
}

class _DynamicQuizViewScreenState extends State<DynamicQuizViewScreen> {
  DocumentSnapshot? _noteSnapshot;
  List<Question> _questions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNote();
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
              final state = GoRouterState.of(context);
              final bundleId = state.uri.queryParameters['bundleId'];
              Navigator.of(context).pop(); // Dialog bezárása

              if (bundleId != null && bundleId.isNotEmpty) {
                context.go('/my-bundles/view/$bundleId');
              } else {
                context.go('/notes');
              }
            },
            child: const Text('Bezárás'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadNote(); // Restart quiz
            },
            child: const Text('Újra'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNote() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId)
          .get();

      if (!mounted) return;

      if (!snapshot.exists) {
        setState(() {
          _error = 'A kvíz jegyzet nem található.';
          _isLoading = false;
        });
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final questionBankId = data['questionBankId'] as String?;

      if (questionBankId == null || questionBankId.isEmpty) {
        setState(() {
          _error = 'Ehhez a kvízhez nincs társítva kérdésbank.';
          _isLoading = false;
        });
        return;
      }

      _noteSnapshot = snapshot;
      await _loadQuestions(questionBankId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Hiba a kvíz betöltésekor: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadQuestions(String questionBankId) async {
    try {
      final questionsSnapshot = await FirebaseFirestore.instance
          .collection('question_banks')
          .doc(questionBankId)
          .get();

      if (!mounted) return;

      if (!questionsSnapshot.exists) {
        setState(() {
          _error = 'A kérdésbank nem található.';
          _isLoading = false;
        });
        return;
      }

      final data = questionsSnapshot.data() as Map<String, dynamic>;
      final List<dynamic> raw = (data['questions'] ?? []) as List<dynamic>;
      final questions = raw
          .whereType<Map<String, dynamic>>()
          .map((q) => Question.fromMap(Map<String, dynamic>.from(q)))
          .toList();

      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Hiba a kérdések betöltésekor: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final state = GoRouterState.of(context);
    final bundleId = state.uri.queryParameters['bundleId'];

    final appBar = AppBar(
      title: Text(
        _noteSnapshot == null
            ? 'Betöltés...'
            : ((_noteSnapshot!.data() as Map<String, dynamic>)['title']
                    as String? ??
                'Cím nélkül'),
        style: TextStyle(
          fontSize: isMobile ? 16 : 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Colors.white,
      elevation: 1,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: Theme.of(context).primaryColor,
          size: isMobile ? 20 : 22,
        ),
        onPressed: () {
          // Ha kötegből jöttünk, oda megyünk vissza
          if (bundleId != null && bundleId.isNotEmpty) {
            context.go('/my-bundles/view/$bundleId');
            return;
          }

          final uri = Uri(
            path: '/notes',
            queryParameters: {
              if (FilterStorage.searchText != null &&
                  FilterStorage.searchText!.isNotEmpty)
                'q': FilterStorage.searchText!,
              if (FilterStorage.status != null) 'status': FilterStorage.status!,
              if (FilterStorage.category != null)
                'category': FilterStorage.category!,
              if (FilterStorage.science != null)
                'science': FilterStorage.science!,
              if (FilterStorage.tag != null) 'tag': FilterStorage.tag!,
              if (FilterStorage.type != null) 'type': FilterStorage.type!,
            },
          );
          context.go(uri.toString());
        },
      ),
    );

    if (_isLoading) {
      return Scaffold(
          appBar: appBar,
          body: const Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: isMobile ? 48 : 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(
                      fontSize: isMobile ? 16 : 18, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = _noteSnapshot!.data() as Map<String, dynamic>;
    final noteType = data['type'] as String? ?? 'dynamic_quiz';
    final isDualMode = noteType == 'dynamic_quiz_dual';

    return Scaffold(
      appBar: appBar,
      body: Container(
        color: const Color(0xFFF8F9FA),
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: EdgeInsets.all(isMobile ? 0 : 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(isMobile ? 0 : 16),
                  boxShadow: isMobile
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isMobile ? 0 : 16),
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 8 : 16),
                    child: _questions.isEmpty
                        ? Center(
                            child: Text(
                              'Nincsenek kérdések a kvízben.',
                              style: TextStyle(
                                fontSize: isMobile ? 16 : 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          )
                        : (isDualMode
                            ? QuizViewerDual(
                                questions: _questions,
                                onQuizComplete: _handleQuizComplete,
                              )
                            : QuizViewer(
                                questions:
                                    _questions.map((q) => q.toMap()).toList())),
                  ),
                ),
              ),
            ),
            if (data['audioUrl'] != null &&
                data['audioUrl'].toString().isNotEmpty)
              Container(
                margin: EdgeInsets.fromLTRB(
                    isMobile ? 0 : 16, 0, isMobile ? 0 : 16, isMobile ? 8 : 16),
                child: AudioPreviewPlayer(audioUrl: data['audioUrl']),
              ),
          ],
        ),
      ),
    );
  }
}
