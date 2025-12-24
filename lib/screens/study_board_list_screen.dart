import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/study_board_models.dart';
import '../services/study_board_service.dart';
import '../widgets/header.dart';
import '../widgets/sidebar.dart';

class StudyBoardListScreen extends StatefulWidget {
  const StudyBoardListScreen({super.key});

  @override
  State<StudyBoardListScreen> createState() => _StudyBoardListScreenState();
}

class _StudyBoardListScreenState extends State<StudyBoardListScreen> {
  String _search = '';

  void _onSearchChanged(String v) {
    setState(() {
      _search = v.trim().toLowerCase();
    });
  }

  Future<void> _createBoard() async {
    final controller = TextEditingController(text: '');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Új köteg'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Cím',
            hintText: 'pl. ELTE – Alkotmányjog köteg',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Létrehozás'),
          ),
        ],
      ),
    );
    if (title == null) return;
    final t = title.trim();
    if (t.isEmpty) return;

    final id = await StudyBoardService.createBoard(title: t);
    if (!mounted) return;
    context.go('/study-boards/$id');
  }

  Future<void> _renameBoard(String boardId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cím módosítása'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Cím'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Mentés'),
          ),
        ],
      ),
    );
    if (title == null) return;
    final t = title.trim();
    if (t.isEmpty) return;
    await StudyBoardService.renameBoard(boardId, t);
  }

  Future<void> _deleteBoard(String boardId, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tábla törlése'),
        content: Text('Biztosan törlöd a táblát?\n\n"$title"'),
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
    await StudyBoardService.deleteBoard(boardId);
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Saját kötegek',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      ElevatedButton.icon(
                        onPressed: _createBoard,
                        icon: const Icon(Icons.add),
                        label: const Text('Új köteg'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: StudyBoardService.myBoardsStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Hiba a táblák betöltésekor.'),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;
                      final boards = docs
                          .map(StudyBoard.fromDoc)
                          .where((b) =>
                              _search.isEmpty ||
                              b.title.toLowerCase().contains(_search))
                          .toList();

                      if (boards.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Még nincs köteged.\n\nHozz létre egyet az „Új köteg” gombbal.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: boards.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final b = boards[i];
                          return Card(
                            child: ListTile(
                              title: Text(b.title),
                              subtitle: Text(
                                'Létrehozva: ${b.createdAt.toLocal()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => context.go('/study-boards/${b.id}'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'rename') {
                                    await _renameBoard(b.id, b.title);
                                  } else if (v == 'delete') {
                                    await _deleteBoard(b.id, b.title);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Átnevezés'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Törlés'),
                                  ),
                                ],
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
        ],
      ),
    );
  }
}
