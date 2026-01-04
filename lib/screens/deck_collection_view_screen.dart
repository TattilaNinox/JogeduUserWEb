import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/deck_collection.dart';
import '../services/deck_collection_service.dart';
import '../widgets/sidebar.dart';
import '../widgets/flippable_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/learning_status_badge.dart';

/// Gyűjtemény nézet - ÖSSZESÍTETT kártya megjelenítés.
/// A felhasználó egyetlen pakliként látja az összes kártyát.
class DeckCollectionViewScreen extends StatefulWidget {
  final String collectionId;

  const DeckCollectionViewScreen({super.key, required this.collectionId});

  @override
  State<DeckCollectionViewScreen> createState() =>
      _DeckCollectionViewScreenState();
}

class _DeckCollectionViewScreenState extends State<DeckCollectionViewScreen> {
  DeckCollection? _collection;
  List<Map<String, dynamic>> _allCards = [];
  Map<String, Map<String, dynamic>> _learningData = {};
  Map<String, int>? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCollectionData();
  }

  Future<void> _loadCollectionData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Gyűjtemény lekérése
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

      // Összes kártya betöltése (NEM összekeverve - sorrend megmarad)
      final allCards = await DeckCollectionService.loadAllCardsFromCollection(
        widget.collectionId,
        shuffle: false,
      );

      // Statisztikák lekérése
      final stats = await DeckCollectionService.getCollectionStats(
        widget.collectionId,
      );

      // Tanulási adatok betöltése
      final learningData = await _loadLearningData(allCards);

      if (mounted) {
        setState(() {
          _collection = collection;
          _allCards = allCards;
          _stats = stats;
          _learningData = learningData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadLearningData(
      List<Map<String, dynamic>> cards) async {
    final learningData = <String, Map<String, dynamic>>{};
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || cards.isEmpty) return learningData;

    try {
      // Csoportosítás kategória szerint a hatékony lekérdezéshez
      final cardsByCategory = <String, List<String>>{};
      for (final card in cards) {
        final catId = card['categoryId'] as String? ?? 'default';
        final cardId = card['cardId'] as String;
        cardsByCategory.putIfAbsent(catId, () => []).add(cardId);
      }

      final futures = <Future<void>>[];
      const chunkSize = 30; // Firestore whereIn limit

      for (final entry in cardsByCategory.entries) {
        final categoryId = entry.key;
        final cardIds = entry.value;

        for (var i = 0; i < cardIds.length; i += chunkSize) {
          final chunk =
              cardIds.sublist(i, (i + chunkSize).clamp(0, cardIds.length));

          futures.add(FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('categories')
              .doc(categoryId)
              .collection('learning')
              .where(FieldPath.documentId, whereIn: chunk)
              .get()
              .then((snapshot) {
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final state = data['state'] as String? ?? 'NEW';
              final lastRating = data['lastRating'] as String? ?? 'Again';
              final nextReview = data['nextReview'] as Timestamp?;
              final now = Timestamp.now();
              final isDue = state == 'NEW' ||
                  (nextReview != null && nextReview.seconds <= now.seconds);

              learningData[doc.id] = {
                'state': state,
                'lastRating': lastRating,
                'isDue': isDue,
              };
            }
          }));
        }
      }

      await Future.wait(futures);
    } catch (e) {
      debugPrint('Hiba a tanulási adatok betöltésekor: $e');
    }

    return learningData;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 1200;

      Widget content;
      if (_isLoading) {
        content = const Center(child: CircularProgressIndicator());
      } else if (_error != null) {
        content = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Hiba: $_error'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadCollectionData,
                icon: const Icon(Icons.refresh),
                label: const Text('Újratöltés'),
              ),
            ],
          ),
        );
      } else if (_allCards.isEmpty) {
        content = const Center(
          child: Text('Ez a gyűjtemény üres.'),
        );
      } else {
        content = Column(
          children: [
            // Statisztikák összefoglaló
            if (_stats != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                color: Colors.grey.shade100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatChip('Összes', _allCards.length, Colors.grey),
                    _buildStatChip(
                        'Esedékes', _stats!['due'] ?? 0, Colors.orange),
                    _buildStatChip('Új', _stats!['new'] ?? 0, Colors.blue),
                    _buildStatChip(
                        'Tanulásban', _stats!['learning'] ?? 0, Colors.purple),
                  ],
                ),
              ),
            // Kártyák grid
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.all(isMobile ? 8 : 16),
                gridDelegate: isWide
                    ? const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 400,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.6,
                      )
                    : SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 1,
                        mainAxisSpacing: isMobile ? 6 : 12,
                        crossAxisSpacing: isMobile ? 6 : 12,
                        childAspectRatio: isMobile ? 1.8 : 0.9,
                      ),
                itemCount: _allCards.length,
                itemBuilder: (context, index) {
                  final card = _allCards[index];
                  final front = card['front'] as String? ?? '';
                  final back = card['back'] as String? ?? '';
                  final cardId = card['cardId'] as String;
                  final learningInfo = _learningData[cardId];

                  return Stack(
                    children: [
                      FlippableCard(
                        frontText: front,
                        backText: back,
                      ),
                      if (learningInfo != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: LearningStatusBadge(
                            state: learningInfo['state'] as String,
                            lastRating: learningInfo['lastRating'] as String,
                            isDue: learningInfo['isDue'] as bool,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      }

      final appBar = _buildAppBar(isMobile);

      if (isWide) {
        return Scaffold(
          appBar: appBar,
          body: Row(
            children: [
              const Sidebar(selectedMenu: 'deck-collections'),
              Expanded(child: content),
            ],
          ),
        );
      }

      return Scaffold(
        appBar: appBar,
        drawer: const Drawer(
          child: SafeArea(
            child: Sidebar(selectedMenu: 'deck-collections'),
          ),
        ),
        body: content,
      );
    });
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    return AppBar(
      title: Text(
        _collection?.title ?? 'Gyűjtemény',
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
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/notes');
          }
        },
      ),
      actions: [
        if (_allCards.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.school, color: Color(0xFF1E3A8A)),
            tooltip: 'Tanulás',
            onPressed: () async {
              await context
                  .push('/deck-collections/${widget.collectionId}/study');
              // Visszatéréskor frissítjük a statisztikákat
              DeckCollectionService.invalidateCollectionCache(
                  widget.collectionId);
              if (mounted) {
                _loadCollectionData();
              }
            },
          ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Color(0xFF1E3A8A)),
          tooltip: 'Frissítés',
          onPressed: _loadCollectionData,
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
