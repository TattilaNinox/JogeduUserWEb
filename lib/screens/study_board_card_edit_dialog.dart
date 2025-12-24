import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/study_board_models.dart';
import '../services/study_board_service.dart';
import 'study_board_content_picker_dialog.dart';

Future<void> showStudyBoardCardEditDialog({
  required BuildContext context,
  required String boardId,
  required String cardId,
  required String initialTitle,
  required String? initialDescription,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _StudyBoardCardEditDialog(
      boardId: boardId,
      cardId: cardId,
      initialTitle: initialTitle,
      initialDescription: initialDescription,
    ),
  );
}

class _StudyBoardCardEditDialog extends StatefulWidget {
  final String boardId;
  final String cardId;
  final String initialTitle;
  final String? initialDescription;

  const _StudyBoardCardEditDialog({
    required this.boardId,
    required this.cardId,
    required this.initialTitle,
    required this.initialDescription,
  });

  @override
  State<_StudyBoardCardEditDialog> createState() =>
      _StudyBoardCardEditDialogState();
}

class _StudyBoardCardEditDialogState extends State<_StudyBoardCardEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descController = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _titleController.text.trim();
    if (t.isEmpty) return;
    await StudyBoardService.updateCard(
      boardId: widget.boardId,
      cardId: widget.cardId,
      title: t,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteCard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tétel törlése'),
        content: const Text('Biztosan törlöd ezt a tételt?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await StudyBoardService.deleteCard(
      boardId: widget.boardId,
      cardId: widget.cardId,
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _openContent(BuildContext context, StudyItemRef ref) {
    // Mirrors NoteListTile routing for main content types.
    final type = ref.contentType;
    final id = ref.contentId;
    if (type == 'interactive') {
      context.go('/interactive-note/$id');
    } else if (type == 'dynamic_quiz' || type == 'dynamic_quiz_dual') {
      context.go('/quiz/$id');
    } else if (type == 'deck') {
      context.go('/deck/$id/view');
    } else if (type == 'memoriapalota_allomasok') {
      context.go('/memoriapalota-allomas/$id');
    } else if (type == 'jogeset') {
      context.go('/jogeset/$id');
    } else if (type == 'dialogus_fajlok') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dialogus audio megnyitás itt még nem támogatott.'),
        ),
      );
    } else {
      // default: standard note
      context.go('/note/$id');
    }
  }

  Future<void> _addItems() async {
    final picked = await showStudyBoardContentPickerDialog(context);
    if (picked == null || picked.isEmpty) return;
    for (final p in picked) {
      await StudyBoardService.addItem(
        boardId: widget.boardId,
        cardId: widget.cardId,
        contentType: p.ref.contentType,
        contentId: p.ref.contentId,
        titleSnapshot: p.titleSnapshot,
        categorySnapshot: p.categorySnapshot,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final dialogWidth = w > 720 ? 720.0 : w * 0.95;

    return AlertDialog(
      title: const Text('Tétel szerkesztése'),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Tétel címe'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              decoration:
                  const InputDecoration(labelText: 'Megjegyzés (opcionális)'),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tételben lévő tartalmak',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addItems,
                  icon: const Icon(Icons.add),
                  label: const Text('Hozzáadás'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: StudyBoardService.itemsStream(
                  boardId: widget.boardId,
                  cardId: widget.cardId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Hiba a tartalmak betöltésekor.');
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items =
                      snapshot.data!.docs.map(StudyCardItem.fromDoc).toList();
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Még nincs tartalom a tételben.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    );
                  }

                  return ReorderableListView.builder(
                    shrinkWrap: true,
                    onReorder: (oldIndex, newIndex) async {
                      final ids = items.map((e) => e.id).toList();
                      if (newIndex > oldIndex) newIndex -= 1;
                      final moved = ids.removeAt(oldIndex);
                      ids.insert(newIndex, moved);
                      await StudyBoardService.setItemOrders(
                        boardId: widget.boardId,
                        cardId: widget.cardId,
                        orderedItemIds: ids,
                      );
                    },
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final it = items[i];
                      final title = it.titleSnapshot?.trim().isNotEmpty == true
                          ? it.titleSnapshot!.trim()
                          : it.ref.toString();
                      final subtitleParts = <String>[
                        it.ref.contentType,
                        if (it.categorySnapshot != null &&
                            it.categorySnapshot!.trim().isNotEmpty)
                          it.categorySnapshot!.trim(),
                      ];
                      return ListTile(
                        key: ValueKey(it.id),
                        title: Text(title),
                        subtitle: Text(subtitleParts.join(' · ')),
                        onTap: () => _openContent(context, it.ref),
                        trailing: IconButton(
                          tooltip: 'Eltávolítás',
                          icon: const Icon(Icons.close),
                          onPressed: () => StudyBoardService.removeItem(
                            boardId: widget.boardId,
                            cardId: widget.cardId,
                            itemId: it.id,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleteCard,
          child: const Text('Tétel törlése'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Bezárás'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Mentés'),
        ),
      ],
    );
  }
}
