import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/sidebar.dart';
import '../widgets/learning_status_badge.dart';
import '../utils/filter_storage.dart';
import 'package:orlomed_admin_web/widgets/flippable_card.dart';

class FlashcardDeckViewScreen extends StatefulWidget {
  final String deckId;
  const FlashcardDeckViewScreen({super.key, required this.deckId});

  @override
  State<FlashcardDeckViewScreen> createState() =>
      _FlashcardDeckViewScreenState();
}

class _FlashcardDeckViewScreenState extends State<FlashcardDeckViewScreen> {
  DocumentSnapshot? _deckData;
  bool _isLoading = true;
  Map<int, Map<String, dynamic>> _learningData = {};

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

      if (!doc.exists) {
        if (mounted) {
          _showAccessDeniedAndGoBack();
        }
        return;
      }

      if (mounted) {
        final data = doc.data();
        final categoryId = data?['category'] as String? ?? 'default';
        final flashcards =
            List<Map<String, dynamic>>.from(data?['flashcards'] ?? []);

        // Tanulási adatok betöltése - OPTIMALIZÁLT párhuzamos query-kkel
        Map<int, Map<String, dynamic>> learningData = {};
        if (flashcards.isNotEmpty) {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              // Batch lekérdezés a tanulási adatokhoz (30-as blokkokban, PÁRHUZAMOSAN)
              final allCardIds = List.generate(
                  flashcards.length, (i) => '${widget.deckId}#$i');
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

              // PÁRHUZAMOS végrehajtás - akár 10x gyorsabb!
              final results = await Future.wait(futures);
              final learningDocs =
                  results.expand((snapshot) => snapshot.docs).toList();

              final now = Timestamp.now();
              for (final doc in learningDocs) {
                final cardId = doc.id;
                final index = int.tryParse(cardId.split('#').last) ?? -1;
                if (index >= 0) {
                  final docData = doc.data() as Map<String, dynamic>?;
                  final state = docData?['state'] as String? ?? 'NEW';
                  final lastRating =
                      docData?['lastRating'] as String? ?? 'Again';
                  final nextReview = docData?['nextReview'] as Timestamp?;
                  final isDue = state == 'NEW' ||
                      (nextReview != null && nextReview.seconds <= now.seconds);

                  learningData[index] = {
                    'state': state,
                    'lastRating': lastRating,
                    'isDue': isDue,
                  };
                }
              }
            }
          } catch (e) {
            debugPrint('Error loading learning data: $e');
          }
        }

        setState(() {
          _deckData = doc;
          _learningData = learningData;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Firestore permission denied hiba ellenőrzése
      if (e.toString().contains('permission-denied') ||
          e.toString().contains('PERMISSION_DENIED')) {
        if (mounted) {
          _showAccessDeniedAndGoBack();
        }
      } else {
        debugPrint('Error loading deck data: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Hiba a pakli betöltése közben: $e'),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  void _showAccessDeniedAndGoBack() {
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            'Ez a tartalom csak előfizetőknek érhető el. Vásárolj előfizetést a teljes hozzáféréshez!'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Előfizetés',
          onPressed: () {
            context.go('/account');
          },
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        context.go('/notes');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_deckData == null || !_deckData!.exists) {
      final screenWidth = MediaQuery.of(context).size.width;
      final isMobile = screenWidth < 600;

      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Hiba',
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
              // Egy szinttel visszalépés, ha van előző oldal a veremben
              if (context.canPop()) {
                context.pop();
              } else {
                // Ha nincs előző oldal, akkor a főoldalra navigálunk szűrőkkel
                final uri = Uri(
                  path: '/notes',
                  queryParameters: {
                    if (FilterStorage.searchText != null &&
                        FilterStorage.searchText!.isNotEmpty)
                      'q': FilterStorage.searchText!,
                    if (FilterStorage.status != null)
                      'status': FilterStorage.status!,
                    if (FilterStorage.category != null)
                      'category': FilterStorage.category!,
                    if (FilterStorage.science != null)
                      'science': FilterStorage.science!,
                    if (FilterStorage.tag != null) 'tag': FilterStorage.tag!,
                    if (FilterStorage.type != null) 'type': FilterStorage.type!,
                  },
                );
                context.go(uri.toString());
              }
            },
          ),
        ),
        body: const Center(child: Text('A pakli nem található.')),
      );
    }

    final data = _deckData!.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? 'Névtelen pakli';
    final flashcards =
        List<Map<String, dynamic>>.from(data['flashcards'] ?? []);

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 1200;
      final screenWidth = MediaQuery.of(context).size.width;
      final isMobile = screenWidth < 600;

      final content = flashcards.isEmpty
          ? const Center(child: Text('Ez a pakli üres.'))
          : GridView.builder(
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
              itemCount: flashcards.length,
              itemBuilder: (context, index) {
                final learningInfo = _learningData[index];
                return Stack(
                  children: [
                    FlippableCard(
                      frontText: flashcards[index]['front'] ?? '',
                      backText: flashcards[index]['back'] ?? '',
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
            );

      if (isWide) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              title,
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: isMobile ? TextOverflow.visible : TextOverflow.ellipsis,
              maxLines: isMobile ? null : 2,
              textAlign: TextAlign.center,
              softWrap: true,
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
                // URL paraméterekkel vissza navigálás a szűrők megőrzéséhez
                final uri = Uri(
                  path: '/notes',
                  queryParameters: {
                    if (FilterStorage.searchText != null &&
                        FilterStorage.searchText!.isNotEmpty)
                      'q': FilterStorage.searchText!,
                    if (FilterStorage.status != null)
                      'status': FilterStorage.status!,
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
            actions: [
              if (flashcards.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.school,
                    color: Color(0xFF1E3A8A), // Bíborkék
                  ),
                  tooltip: 'Tanulás',
                  onPressed: () {
                    context.go('/deck/${widget.deckId}/study');
                  },
                ),
            ],
          ),
          body: Row(
            children: [
              const Sidebar(selectedMenu: 'notes'),
              Expanded(child: content),
            ],
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.w600,
            ),
            overflow: isMobile ? TextOverflow.visible : TextOverflow.ellipsis,
            maxLines: isMobile ? null : 2,
            textAlign: TextAlign.center,
            softWrap: true,
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
              // Egy szinttel visszalépés, ha van előző oldal a veremben
              if (context.canPop()) {
                context.pop();
              } else {
                // Ha nincs előző oldal, akkor a főoldalra navigálunk szűrőkkel
                final uri = Uri(
                  path: '/notes',
                  queryParameters: {
                    if (FilterStorage.searchText != null &&
                        FilterStorage.searchText!.isNotEmpty)
                      'q': FilterStorage.searchText!,
                    if (FilterStorage.status != null)
                      'status': FilterStorage.status!,
                    if (FilterStorage.category != null)
                      'category': FilterStorage.category!,
                    if (FilterStorage.science != null)
                      'science': FilterStorage.science!,
                    if (FilterStorage.tag != null) 'tag': FilterStorage.tag!,
                    if (FilterStorage.type != null) 'type': FilterStorage.type!,
                  },
                );
                context.go(uri.toString());
              }
            },
          ),
          actions: [
            if (flashcards.isNotEmpty)
              IconButton(
                icon: const Icon(
                  Icons.school,
                  color: Color(0xFF1E3A8A), // Bíborkék
                ),
                tooltip: 'Tanulás',
                onPressed: () {
                  context.go('/deck/${widget.deckId}/study');
                },
              ),
          ],
        ),
        drawer: const Drawer(
          child: SafeArea(
            child: Sidebar(selectedMenu: 'notes'),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: content,
        ),
      );
    });
  }
}
