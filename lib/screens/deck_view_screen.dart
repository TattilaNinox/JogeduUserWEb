import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import '../widgets/sidebar.dart';

class DeckViewScreen extends StatefulWidget {
  final String deckId;
  const DeckViewScreen({super.key, required this.deckId});

  @override
  State<DeckViewScreen> createState() => _DeckViewScreenState();
}

class _DeckViewScreenState extends State<DeckViewScreen> {
  DocumentSnapshot? _deck;
  List<DocumentSnapshot> _cards = [];
  bool _isLoading = true;
  int _currentPage = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final deckDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.deckId)
          .get();

      if (!deckDoc.exists) {
        if (mounted) {
          _showAccessDeniedAndGoBack();
          setState(() => _isLoading = false);
        }
        return;
      }

      final data = deckDoc.data() as Map<String, dynamic>;
      final cardIds = List<String>.from(data['card_ids'] ?? []);

      if (cardIds.isNotEmpty) {
        final cardDocs = await FirebaseFirestore.instance
            .collection('notes')
            .where(FieldPath.documentId, whereIn: cardIds)
            .get();
        // Sorba rendezés a card_ids lista alapján
        _cards = cardDocs.docs
          ..sort(
              (a, b) => cardIds.indexOf(a.id).compareTo(cardIds.indexOf(b.id)));
      }

      if (mounted) {
        setState(() {
          _deck = deckDoc;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Firestore permission denied hiba (zárt jegyzet)
      if (mounted) {
        _showAccessDeniedAndGoBack();
      }
    }
  }

  void _showAccessDeniedAndGoBack() {
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
        // Ellenőrizzük, van-e 'from' query paraméter
        try {
          final uri = GoRouterState.of(context).uri;
          final fromParam = uri.queryParameters['from'];

          if (fromParam != null && fromParam.isNotEmpty) {
            final decodedFrom = Uri.decodeComponent(fromParam);
            context.go(decodedFrom);
          } else {
            context.go('/notes');
          }
        } catch (e) {
          context.go('/notes');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_deck == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('A köteg nem található.')));
    }

    final deckData = _deck!.data() as Map<String, dynamic>;
    final title = deckData['title'] ?? 'Névtelen köteg';
    final category = deckData['category'] as String? ?? '';
    final tags = (deckData['tags'] as List<dynamic>? ?? []).cast<String>();

    // Ellenőrizzük, van-e 'from' query paraméter
    final uri = GoRouterState.of(context).uri;
    final fromParam = uri.queryParameters['from'];

    // Breadcrumb építése
    Widget buildBreadcrumb() {
      final items = <Widget>[];

      // Kategória
      if (category.isNotEmpty) {
        items.add(
          InkWell(
            onTap: () {
              // Vissza a főoldalra, kategória szűrővel
              context.go('/notes?category=$category');
            },
            child: Text(
              category,
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue[700],
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        );
      }

      // Tags
      for (int i = 0; i < tags.length; i++) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.chevron_right, size: 16, color: Colors.grey[600]),
          ),
        );
        items.add(
          InkWell(
            onTap: () {
              // Vissza a főoldalra, kategória és tag szűrővel
              context.go('/notes?category=$category&tag=${tags[i]}');
            },
            child: Text(
              tags[i],
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue[700],
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        );
      }

      // Deck címe (nem kattintható)
      if (items.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.chevron_right, size: 16, color: Colors.grey[600]),
          ),
        );
      }
      items.add(
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      );

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            const SizedBox(height: 4),
            buildBreadcrumb(),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (fromParam != null && fromParam.isNotEmpty) {
              // Ha van from paraméter, oda navigálunk vissza
              try {
                final decodedFrom = Uri.decodeComponent(fromParam);
                context.go(decodedFrom);
              } catch (e) {
                // Ha nem sikerül dekódolni, akkor Navigator.pop vagy /notes
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  context.go('/notes');
                }
              }
            } else {
              // Ha nincs from paraméter, próbáljuk a Navigator.pop-ot
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                context.go('/notes');
              }
            }
          },
        ),
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'decks'),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _cards.isEmpty
                      ? const Center(
                          child: Text('Nincsenek kártyák ebben a kötegben.'))
                      : PageView.builder(
                          controller: _pageController,
                          itemCount: _cards.length,
                          onPageChanged: (index) =>
                              setState(() => _currentPage = index),
                          itemBuilder: (context, index) {
                            final cardData =
                                _cards[index].data() as Map<String, dynamic>;
                            final htmlContent =
                                cardData['html'] ?? 'Nincs tartalom.';
                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: SingleChildScrollView(
                                  child: Html(data: htmlContent)),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios),
                        onPressed: _currentPage > 0
                            ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.ease,
                                );
                              }
                            : null,
                      ),
                      Text(
                        'Kártya ${_currentPage + 1} / ${_cards.length}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios),
                        onPressed: _currentPage < _cards.length - 1
                            ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.ease,
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
