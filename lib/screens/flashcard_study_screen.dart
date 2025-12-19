import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../services/learning_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadDeckData();
  }

  Future<void> _loadDeckData() async {
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
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Hiba a pakli betöltése közben: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  void _showAnswerPressed() {
    setState(() {
      _showAnswer = true;
    });
  }

  Future<void> _evaluateCard(String evaluation) async {
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

      // Háttér mentés
      await LearningService.updateUserLearningData(
        cardId,
        evaluation,
        _categoryId!,
      );

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
    }
  }

  void _showCompletionDialog() {
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
              context.go('/notes');
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
        context.go('/deck/${widget.deckId}/view');
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
            context.go('/deck/${widget.deckId}/view');
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
                        if (currentCard['explanation'] != null &&
                            (currentCard['explanation'] as String)
                                .isNotEmpty) ...[
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
                                data: currentCard['explanation'] ?? '',
                                style: {
                                  "body": Style(
                                    margin: Margins.zero,
                                    padding: HtmlPaddings.zero,
                                    textAlign: TextAlign.justify,
                                  ),
                                  "p": Style(
                                    fontSize: FontSize(12),
                                    color: Colors.black87,
                                    lineHeight: LineHeight(1.4),
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
