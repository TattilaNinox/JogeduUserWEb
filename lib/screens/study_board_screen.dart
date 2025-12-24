import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/study_board_models.dart';
import '../services/study_board_service.dart';
import '../widgets/header.dart';
import '../widgets/sidebar.dart';
import 'study_board_card_edit_dialog.dart';

class StudyBoardScreen extends StatefulWidget {
  final String boardId;

  const StudyBoardScreen({super.key, required this.boardId});

  @override
  State<StudyBoardScreen> createState() => _StudyBoardScreenState();
}

class _StudyBoardScreenState extends State<StudyBoardScreen> {
  String _search = '';

  void _onSearchChanged(String v) {
    setState(() {
      _search = v.trim().toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 249, 250, 251),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'study_boards'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Header(onSearchChanged: _onSearchChanged),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: StudyBoardService.boardStream(widget.boardId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                            child: Text('Hiba a tábla betöltésekor.'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final doc = snapshot.data!;
                      if (!doc.exists) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('A köteg nem található.'),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => context.go('/study-boards'),
                                child: const Text('Vissza a kötegekhez'),
                              )
                            ],
                          ),
                        );
                      }
                      final board = StudyBoard.fromDoc(doc);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Vissza',
                                  onPressed: () => context.go('/study-boards'),
                                  icon: const Icon(Icons.arrow_back),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    board.title,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _KanbanBoardView(
                              boardId: board.id,
                              columns: board.columns,
                              search: _search,
                            ),
                          ),
                        ],
                      );
                    },
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

class _DraggedCard {
  final String cardId;
  final String fromColumnId;

  const _DraggedCard({required this.cardId, required this.fromColumnId});
}

class _KanbanBoardView extends StatelessWidget {
  final String boardId;
  final List<StudyBoardColumn> columns;
  final String search;

  const _KanbanBoardView({
    required this.boardId,
    required this.columns,
    required this.search,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      // Mobilon: fülek az oszlopokhoz
      return DefaultTabController(
        length: columns.length,
        child: Column(
          children: [
            Material(
              color: Colors.white,
              child: TabBar(
                isScrollable: true,
                tabs: [
                  for (final c in columns) Tab(text: c.title),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final c in columns)
                    _KanbanColumn(
                      boardId: boardId,
                      column: c,
                      search: search,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in columns)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _KanbanColumn(
                boardId: boardId,
                column: c,
                search: search,
              ),
            ),
        ],
      ),
    );
  }
}

class _KanbanColumn extends StatefulWidget {
  final String boardId;
  final StudyBoardColumn column;
  final String search;

  const _KanbanColumn({
    required this.boardId,
    required this.column,
    required this.search,
  });

  @override
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  int _limit = 25;

  Future<void> _addCard() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text('Új tétel – ${widget.column.title}'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tétel címe',
              hintText: 'pl. Tétel 1 – Alapfogalmak',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Mégse'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text),
              child: const Text('Létrehozás'),
            ),
          ],
        );
      },
    );
    if (title == null) return;
    final t = title.trim();
    if (t.isEmpty) return;
    try {
      await StudyBoardService.addCard(
        boardId: widget.boardId,
        columnId: widget.column.id,
        title: t,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nem sikerült létrehozni a tételt: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = StudyBoardService.cardsCol(widget.boardId)
        .where('columnId', isEqualTo: widget.column.id)
        .orderBy('order')
        .limit(_limit);

    return Container(
      width: 320,
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.column.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Új tétel',
                  onPressed: _addCard,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: DragTarget<_DraggedCard>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) async {
                // drop to end of this column
                final dragged = details.data;
                await StudyBoardService.moveCard(
                  boardId: widget.boardId,
                  cardId: dragged.cardId,
                  toColumnId: widget.column.id,
                  // Use a timestamp-based order so this always goes to the end
                  // without requiring an index-dependent lookup.
                  newOrder: DateTime.now().microsecondsSinceEpoch.toDouble(),
                );
              },
              builder: (context, candidate, rejected) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('Hiba'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final cards = snapshot.data!.docs
                        .map(StudyCard.fromDoc)
                        .where((c) =>
                            widget.search.isEmpty ||
                            c.title.toLowerCase().contains(widget.search))
                        .toList();

                    if (cards.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Nincs tétel.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: cards.length + 1,
                      itemBuilder: (context, index) {
                        if (index == cards.length) {
                          final canLoadMore =
                              snapshot.data!.docs.length >= _limit;
                          if (!canLoadMore) return const SizedBox(height: 24);
                          return TextButton(
                            onPressed: () {
                              setState(() {
                                _limit += 25;
                              });
                            },
                            child: const Text('Továbbiak betöltése'),
                          );
                        }

                        final card = cards[index];
                        return _CardDropSlot(
                          boardId: widget.boardId,
                          columnId: widget.column.id,
                          beforeCard:
                              index < cards.length ? cards[index] : null,
                          cardsInColumn: cards,
                          child: _KanbanCardTile(
                            boardId: widget.boardId,
                            card: card,
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CardDropSlot extends StatelessWidget {
  final String boardId;
  final String columnId;
  final StudyCard? beforeCard;
  final List<StudyCard> cardsInColumn;
  final Widget child;

  const _CardDropSlot({
    required this.boardId,
    required this.columnId,
    required this.beforeCard,
    required this.cardsInColumn,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DraggedCard>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) async {
        final dragged = details.data;

        // If same column, renumber full column after reordering locally.
        if (dragged.fromColumnId == columnId) {
          final ids = cardsInColumn.map((c) => c.id).toList();
          ids.remove(dragged.cardId);
          final insertIndex = beforeCard == null
              ? ids.length
              : ids.indexOf(beforeCard!.id).clamp(0, ids.length);
          ids.insert(insertIndex, dragged.cardId);
          await StudyBoardService.setCardOrders(
            boardId: boardId,
            columnId: columnId,
            orderedCardIds: ids,
          );
          return;
        }

        // Different column: compute an order between neighbors (or end).
        final insertIndex = beforeCard == null
            ? cardsInColumn.length
            : cardsInColumn.indexWhere((c) => c.id == beforeCard!.id);
        final prevOrder =
            insertIndex <= 0 ? 0.0 : cardsInColumn[insertIndex - 1].order;
        final nextOrder = insertIndex >= cardsInColumn.length
            ? prevOrder + 1000.0
            : cardsInColumn[insertIndex].order;
        final newOrder = (prevOrder + nextOrder) / 2.0;
        await StudyBoardService.moveCard(
          boardId: boardId,
          cardId: dragged.cardId,
          toColumnId: columnId,
          newOrder: newOrder,
        );
      },
      builder: (context, cand, rej) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: child,
        );
      },
    );
  }
}

class _KanbanCardTile extends StatelessWidget {
  final String boardId;
  final StudyCard card;

  const _KanbanCardTile({required this.boardId, required this.card});

  @override
  Widget build(BuildContext context) {
    final useLongPress = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final data = _DraggedCard(cardId: card.id, fromColumnId: card.columnId);

    final visual = InkWell(
      onTap: () => showStudyBoardCardEditDialog(
        context: context,
        boardId: boardId,
        cardId: card.id,
        initialTitle: card.title,
        initialDescription: card.description,
      ),
      child: _CardVisual(card: card),
    );

    final feedback = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: _CardVisual(card: card),
      ),
    );

    // Desktop/web: Draggable (mouse drag). Touch: LongPressDraggable.
    if (!useLongPress) {
      return Draggable<_DraggedCard>(
        data: data,
        feedback: feedback,
        childWhenDragging:
            Opacity(opacity: 0.3, child: _CardVisual(card: card)),
        child: visual,
      );
    }

    return LongPressDraggable<_DraggedCard>(
      data: data,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.3, child: _CardVisual(card: card)),
      child: visual,
    );
  }
}

class _CardVisual extends StatelessWidget {
  final StudyCard card;

  const _CardVisual({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (card.description != null && card.description!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                card.description!.trim(),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
