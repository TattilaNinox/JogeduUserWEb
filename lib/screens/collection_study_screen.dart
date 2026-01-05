import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';
import '../models/deck_collection.dart';
import '../services/deck_collection_service.dart';
import '../services/learning_service.dart';

/// Összevont tanulás képernyő - több pakli kártyái egyként.
/// UI PONTOSAN MEGEGYEZIK a FlashcardStudyScreen-nel!
class CollectionStudyScreen extends StatefulWidget {
  final String collectionId;

  const CollectionStudyScreen({super.key, required this.collectionId});

  @override
  State<CollectionStudyScreen> createState() => _CollectionStudyScreenState();
}

class _CollectionStudyScreenState extends State<CollectionStudyScreen> {
  DeckCollection? _collection;
  List<Map<String, dynamic>> _dueCards = [];
  bool _isLoading = true;
  Object? _error;

  int _currentIndex = 0;
  bool _showAnswer = false;
  bool _isProcessing = false;

  // Evaluation counters
  int _againCount = 0;
  int _hardCount = 0;
  int _goodCount = 0;
  int _easyCount = 0;

  bool get _hasProgress =>
      _againCount + _hardCount + _goodCount + _easyCount > 0;

  @override
  void initState() {
    super.initState();
    _loadCollectionData();
  }

  @override
  void dispose() {
    // FONTOS: Kilépéskor flush-oljuk a batch writer-t,
    // hogy a függő tanulási adatok mentésre kerüljenek
    LearningService.batchWriter.flush();
    super.dispose();
  }

  Future<void> _loadCollectionData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final collection =
          await DeckCollectionService.getCollectionById(widget.collectionId);
      if (collection == null) {
        if (mounted) {
          setState(() {
            _error = 'A gyűjtemény nem található.';
            _isLoading = false;
          });
        }
        return;
      }

      // Összes kártya betöltése
      final allCards = await DeckCollectionService.loadAllCardsFromCollection(
        widget.collectionId,
        shuffle: false,
      );

      // Esedékes kártyák szűrése
      final dueCards = <Map<String, dynamic>>[];
      for (final card in allCards) {
        final deckId = card['deckId'] as String;
        final dueIndices =
            await LearningService.getDueFlashcardIndicesForDeck(deckId);
        final cardIndex = card['index'] as int;
        if (dueIndices.contains(cardIndex)) {
          dueCards.add(card);
        }
      }

      // Összekeverés
      dueCards.shuffle();

      if (mounted) {
        setState(() {
          _collection = collection;
          _dueCards = dueCards;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
    }
  }

  void _showAnswerPressed() {
    setState(() {
      _showAnswer = true;
    });
  }

  Future<void> _evaluateCard(String evaluation) async {
    if (_isProcessing || _dueCards.isEmpty) return;
    _isProcessing = true;

    try {
      final currentCard = _dueCards[_currentIndex];
      final cardId = currentCard['cardId'] as String;
      final categoryId = currentCard['categoryId'] as String;

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
        categoryId,
      );

      if (evaluation == 'Again') {
        if (_currentIndex < _dueCards.length - 1) {
          setState(() {
            _currentIndex++;
            _showAnswer = false;
          });
        } else {
          _showCompletionDialog();
        }
      } else {
        setState(() {
          _dueCards.removeAt(_currentIndex);
          if (_currentIndex >= _dueCards.length) {
            _currentIndex = 0;
          }
          _showAnswer = false;
        });

        if (_dueCards.isEmpty) {
          _showCompletionDialog();
        }
      }
    } catch (e) {
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
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _isProcessing = false;
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
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/deck-collections/${widget.collectionId}');
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
          'Biztosan törölni szeretnéd az összes tanulási előzményt ebben a gyűjteményben?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mégse'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _resetCollectionProgress();
            },
            child: const Text('Törlés'),
          ),
        ],
      ),
    );
  }

  /// Collection összes paklijának tanulási előzményeit törli
  Future<void> _resetCollectionProgress() async {
    try {
      // Összes pakli betöltése a gyűjteményből
      final allCards = await DeckCollectionService.loadAllCardsFromCollection(
        widget.collectionId,
        shuffle: false,
      );

      // Egyedi deckId-k és kártya számok gyűjtése
      final deckStats = <String, int>{};
      for (final card in allCards) {
        final deckId = card['deckId'] as String;
        deckStats[deckId] = (deckStats[deckId] ?? 0) + 1;
      }

      // Minden pakli tanulási előzményének törlése
      for (final entry in deckStats.entries) {
        await LearningService.resetDeckProgress(entry.key, entry.value);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A gyűjtemény tanulási adatai törölve.'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigálás vissza a collection view-ra (mint a FlashcardStudyScreen)
        context.go('/deck-collections/${widget.collectionId}');
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

  @override
  Widget build(BuildContext context) {
    final collectionTitle = _collection?.title ?? 'Gyűjtemény';
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

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
                  onPressed: _loadCollectionData,
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

    // Ha nincs esedékes kártya
    if (_dueCards.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            collectionTitle,
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
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/deck-collections/${widget.collectionId}');
              }
            },
          ),
        ),
        body: const Center(
          child: Text(
            'Nincs esedékes kártya a tanuláshoz!',
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    final currentCard = _dueCards[_currentIndex];
    final totalCards = _dueCards.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          collectionTitle,
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
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/deck-collections/${widget.collectionId}');
            }
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
                        // Explanation section
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
