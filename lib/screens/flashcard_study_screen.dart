import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../services/learning_service.dart';
import '../services/learning_session_service.dart';
import '../models/flashcard_learning_data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_html/flutter_html.dart';

class FlashcardStudyScreen extends StatefulWidget {
  final String deckId;
  const FlashcardStudyScreen({super.key, required this.deckId});

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen> {
  DocumentSnapshot? _deckData;
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _showAnswer = false;
  bool _isProcessing = false; // Rate limiting flag
  Object? _error;

  // Evaluation counters
  int _againCount = 0;
  int _hardCount = 0;
  int _goodCount = 0;
  int _easyCount = 0;

  // Megjelenjen-e a nullázó ikon?
  bool get _hasProgress =>
      _againCount + _hardCount + _goodCount + _easyCount > 0;

  // Learning data
  List<int> _dueCardIndices = [];
  String? _categoryId;

  // J3: Learning data cache for session batching
  final Map<String, FlashcardLearningData> _learningDataCache = {};

  @override
  void initState() {
    super.initState();
    _loadDeckData();
  }

  @override
  void dispose() {
    // J3: Commit any pending evaluations before disposing
    LearningSessionService.instance.commitSession();
    super.dispose();
  }

  Future<void> _loadDeckData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.deckId)
          .get();

      if (mounted) {
        final data = doc.data();
        final categoryId = data?['category'] as String? ?? 'default';
        final flashcards =
            List<Map<String, dynamic>>.from(data?['flashcards'] ?? []);

        // Esedékes kártyák lekérése
        final dueIndices =
            await LearningService.getDueFlashcardIndicesForDeck(widget.deckId);
        // Valós időben számolt statisztikák a kártyák aktuális értékelései alapján - OPTIMALIZÁLT
        final user = FirebaseAuth.instance.currentUser;
        int again = 0, hard = 0, good = 0, easy = 0;
        if (user != null && flashcards.isNotEmpty) {
          // Batch lekérdezés a tanulási adatokhoz (30-as blokkokban, PÁRHUZAMOSAN)
          final allCardIds =
              List.generate(flashcards.length, (i) => '${widget.deckId}#$i');
          const chunkSize = 30; // Firestore whereIn limit

          // Párhuzamos query-k Future.wait()-tel
          final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
          for (var i = 0; i < allCardIds.length; i += chunkSize) {
            final chunk = allCardIds.sublist(
                i, (i + chunkSize).clamp(0, allCardIds.length));
            final queryFuture = FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('categories')
                .doc(categoryId)
                .collection('learning')
                .where(FieldPath.documentId, whereIn: chunk)
                .get();
            futures.add(queryFuture);
          }

          // PÁRHUZAMOS végrehajtás
          final results = await Future.wait(futures);
          final learningDocs =
              results.expand((snapshot) => snapshot.docs).toList();

          // Számlálók számítása az utolsó értékelések alapján
          for (final doc in learningDocs) {
            final data = doc.data() as Map<String, dynamic>?;
            final lastRating = data?['lastRating'] as String? ?? 'Again';

            switch (lastRating) {
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
          }
        }

        setState(() {
          _deckData = doc;
          _categoryId = categoryId;
          _dueCardIndices = dueIndices;
          _againCount = again;
          _hardCount = hard;
          _goodCount = good;
          _easyCount = easy;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e;
        });
        debugPrint('Error loading deck: $e');
      }
    }
  }

  void _showAnswerPressed() {
    setState(() {
      _showAnswer = true;
    });
  }

  Future<void> _evaluateCard(String evaluation) async {
    if (_isProcessing) return; // Debounce védelem
    _isProcessing = true;

    try {
      final currentCardIndex = _dueCardIndices[_currentIndex];
      final cardId =
          '${widget.deckId}#$currentCardIndex'; // deckId#index formátum

      // Optimista UI frissítés
      setState(() {
        switch (evaluation) {
          case 'Again':
            _againCount++;
            break;
          case 'Hard':
            _hardCount++;
            break;
          case 'Good':
            _goodCount++;
            break;
          case 'Easy':
            _easyCount++;
            break;
        }
      });

      // J3: Get current learning data (from cache or default)
      final currentData = _learningDataCache[cardId] ??
          FlashcardLearningData(
            state: 'NEW',
            interval: 0,
            easeFactor: 2.5,
            repetitions: 0,
            lastReview: Timestamp.now(),
            nextReview: Timestamp.now(),
            lastRating: 'Again',
          );

      // J3: Record to session service (NO Firestore write yet!)
      final newData = LearningSessionService.instance.recordEvaluation(
        cardId: cardId,
        rating: evaluation,
        categoryId: _categoryId!,
        currentData: currentData,
      );

      // Update local cache
      _learningDataCache[cardId] = newData;

      // "Újra" esetén a kártya visszakerül a sor végére
      if (evaluation == 'Again') {
        // A kártya marad a sorban, de a következőre lépünk
        if (_currentIndex < _dueCardIndices.length - 1) {
          setState(() {
            _currentIndex++;
            _showAnswer = false;
          });
        } else {
          _showCompletionDialog();
        }
      } else {
        // "Jó" vagy "Könnyű" esetén a kártya kikerül a sorból
        setState(() {
          _dueCardIndices.removeAt(_currentIndex);
          if (_currentIndex >= _dueCardIndices.length) {
            _currentIndex = 0;
          }
          _showAnswer = false;
        });

        // Ha nincs több kártya, befejezés
        if (_dueCardIndices.isEmpty) {
          _showCompletionDialog();
        }
      }
    } catch (e) {
      // Hibakezelés - UI visszaállítása
      setState(() {
        switch (evaluation) {
          case 'Again':
            _againCount--;
            break;
          case 'Hard':
            _hardCount--;
            break;
          case 'Good':
            _goodCount--;
            break;
          case 'Easy':
            _easyCount--;
            break;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba a mentés közben: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 500ms késleltetés a véletlen dupla kattintások ellen
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _isProcessing = false;
      }
    }
  }

  void _showCompletionDialog() {
    // J3: Commit session before showing dialog
    LearningSessionService.instance.commitSession();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Gratulálok!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sikeresen elvégezted a tanulást!'),
            const SizedBox(height: 16),
            Text('Újra: $_againCount'),
            Text('Nehéz: $_hardCount'),
            Text('Jó: $_goodCount'),
            Text('Könnyű: $_easyCount'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              final state = GoRouterState.of(context);
              final bundleId = state.uri.queryParameters['bundleId'];
              if (bundleId != null && bundleId.isNotEmpty) {
                context.go('/my-bundles/view/$bundleId');
              } else {
                context.go('/notes');
              }
            },
            child: const Text('Vissza'),
          ),
        ],
      ),
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Újrakezdés'),
        content: const Text(
          'Biztosan törölni szeretnéd a pakli tanulási előzményeit? '
          'Ez a művelet nem vonható vissza.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mégse'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _resetDeckProgress();
            },
            child: const Text('Törlés', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _resetDeckProgress() async {
    try {
      final flashcards = _getFlashcards();
      await LearningService.resetDeckProgress(widget.deckId, flashcards.length);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A pakli tanulási adatai törölve.'),
            backgroundColor: Colors.green,
          ),
        );
        final state = GoRouterState.of(context);
        final bundleId = state.uri.queryParameters['bundleId'];
        context.go(
            '/deck/${widget.deckId}/view${bundleId != null ? "?bundleId=$bundleId" : ""}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba a törlés közben: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getFlashcards() {
    if (_deckData == null || !_deckData!.exists) return [];
    final data = _deckData!.data() as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['flashcards'] ?? []);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Hiba', style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Nem sikerült betölteni a tanulási adatokat.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$_error',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadDeckData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Próbáld újra'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Tanulás',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E3A8A)),
              ),
              SizedBox(height: 16),
              Text(
                'Tanulási adatok betöltése...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_deckData == null || !_deckData!.exists) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Hiba'),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('A pakli nem található.')),
      );
    }

    final flashcards = _getFlashcards();
    if (flashcards.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Tanulás'),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Ez a pakli üres.')),
      );
    }

    final data = _deckData!.data() as Map<String, dynamic>;
    final deckTitle = data['title'] as String? ?? 'Névtelen pakli';

    // Ha nincs esedékes kártya
    if (_dueCardIndices.isEmpty) {
      final screenWidth = MediaQuery.of(context).size.width;
      final isMobile = screenWidth < 600;

      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            deckTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            overflow: isMobile ? TextOverflow.visible : TextOverflow.ellipsis,
            maxLines: isMobile ? null : 2,
            textAlign: TextAlign.center,
            softWrap: true,
          ),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            'Nincs esedékes kártya a tanuláshoz!',
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    final currentCardIndex = _dueCardIndices[_currentIndex];
    final currentCard = flashcards[currentCardIndex];
    final totalCards = _dueCardIndices.length;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final state = GoRouterState.of(context);
    final bundleId = state.uri.queryParameters['bundleId'];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          deckTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          overflow: isMobile ? TextOverflow.visible : TextOverflow.ellipsis,
          maxLines: isMobile ? null : 2,
          textAlign: TextAlign.center,
          softWrap: true,
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            context.go(
                '/deck/${widget.deckId}/view${bundleId != null ? '?bundleId=$bundleId' : ''}');
          },
        ),
        actions: [
          if (_hasProgress)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Újrakezdés',
              onPressed: _showResetDialog,
            ),
        ],
        elevation: 0,
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Text(
              '${_currentIndex + 1} / $totalCards',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Evaluation counters
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCounter('Újra', _againCount, Colors.red),
                _buildCounter('Nehéz', _hardCount, Colors.orange),
                _buildCounter('Jó', _goodCount, Colors.green),
                _buildCounter('Könnyű', _easyCount, Colors.blue),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Main card content
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Question section
                      const Text(
                        'Kérdés:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currentCard['front'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      if (_showAnswer) ...[
                        const SizedBox(height: 16),
                        const Divider(
                          color: Colors.grey,
                          thickness: 1,
                          indent: 8,
                          endIndent: 8,
                        ),
                        const SizedBox(height: 16),

                        // Answer section
                        const Text(
                          'Válasz:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentCard['back'] ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        // Explanation section (if exists)
                        // Prioritize processed_explanation over explanation (pre-hyphenated content)
                        if ((currentCard['processed_explanation'] != null &&
                                (currentCard['processed_explanation'] as String)
                                    .isNotEmpty) ||
                            (currentCard['explanation'] != null &&
                                (currentCard['explanation'] as String)
                                    .isNotEmpty)) ...[
                          const SizedBox(height: 16),
                          const Divider(
                            color: Colors.grey,
                            thickness: 1,
                            indent: 8,
                            endIndent: 8,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Magyarázat:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Html(
                                // Use processed_explanation if available, otherwise fall back to explanation
                                data: (currentCard['processed_explanation']
                                                as String?)
                                            ?.isNotEmpty ==
                                        true
                                    ? currentCard['processed_explanation']
                                    : currentCard['explanation'] ?? '',
                                style: {
                                  "body": Style(
                                    margin: Margins.zero,
                                    padding: HtmlPaddings.zero,
                                    textAlign: TextAlign.justify,
                                  ),
                                  "p": Style(
                                    fontSize: FontSize(12),
                                    color: Colors.black87,
                                    lineHeight: const LineHeight(1.4),
                                    textAlign: TextAlign.justify,
                                    margin: Margins.only(bottom: 8),
                                  ),
                                },
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        const SizedBox(height: 24),
                        // Show answer button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _showAnswerPressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Válasz megtekintése',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Evaluation buttons (only show when answer is visible)
          if (_showAnswer) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildEvaluationButton(
                          'Újra',
                          Colors.red,
                          () => _evaluateCard('Again'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildEvaluationButton(
                          'Nehéz',
                          Colors.orange,
                          () => _evaluateCard('Hard'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildEvaluationButton(
                          'Jó',
                          Colors.green,
                          () => _evaluateCard('Good'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildEvaluationButton(
                          'Könnyű',
                          Colors.blue,
                          () => _evaluateCard('Easy'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildCounter(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEvaluationButton(
      String text, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
