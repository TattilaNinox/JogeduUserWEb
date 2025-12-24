import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/study_board_models.dart';
import '../core/firebase_config.dart';

class PickedStudyContent {
  final StudyItemRef ref;
  final String? titleSnapshot;
  final String? categorySnapshot;

  const PickedStudyContent({
    required this.ref,
    required this.titleSnapshot,
    required this.categorySnapshot,
  });
}

enum _ContentSource { all, decks, quizzes, memoriaUtvonal, dialogus }

Future<List<PickedStudyContent>?> showStudyBoardContentPickerDialog(
    BuildContext context) {
  return showDialog<List<PickedStudyContent>>(
    context: context,
    builder: (context) => const _StudyBoardContentPickerDialog(),
  );
}

class _StudyBoardContentPickerDialog extends StatefulWidget {
  const _StudyBoardContentPickerDialog();

  @override
  State<_StudyBoardContentPickerDialog> createState() =>
      _StudyBoardContentPickerDialogState();
}

class _StudyBoardContentPickerDialogState
    extends State<_StudyBoardContentPickerDialog> {
  final TextEditingController _q = TextEditingController();
  _ContentSource _source = _ContentSource.all;
  bool _loading = false;
  List<PickedStudyContent> _results = const [];
  final Set<String> _selectedKeys = <String>{};

  static String _labelForContentType(String type) {
    switch (type) {
      case 'deck':
        return 'Tanulókártyák';
      case 'dynamic_quiz':
      case 'dynamic_quiz_dual':
        return 'Kvíz';
      case 'memoriapalota_allomasok':
        return 'Memória útvonal';
      case 'dialogus_fajlok':
        return 'Dialógus';
      default:
        return type;
    }
  }

  static bool _isQuizType(String t) =>
      t == 'dynamic_quiz' || t == 'dynamic_quiz_dual';

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<List<PickedStudyContent>> _queryNotes({
    required String prefix,
    String? typeEquals,
    List<String>? typeIn,
  }) async {
    const userScience = 'Jogász';
    Query<Map<String, dynamic>> q = FirebaseConfig.firestore
        .collection('notes')
        .where('science', isEqualTo: userScience)
        .where('status', isEqualTo: 'Published');

    // Optional type filtering (deck / quizzes). This may require extra indexes;
    // if it fails, we will fallback to client-side filtering in _runSearch().
    if (typeEquals != null && typeEquals.isNotEmpty) {
      q = q.where('type', isEqualTo: typeEquals);
    } else if (typeIn != null && typeIn.isNotEmpty) {
      q = q.where('type', whereIn: typeIn);
    }

    if (prefix.isNotEmpty) {
      q = q.orderBy('title').startAt([prefix]).endAt(['$prefix\uf8ff']);
    } else {
      q = q.orderBy('modified', descending: true);
    }
    final snap = await q.limit(50).get();
    return snap.docs.map((d) {
      final data = d.data();
      final type = (data['type'] as String? ?? 'standard');
      return PickedStudyContent(
        ref: StudyItemRef(contentType: type, contentId: d.id),
        titleSnapshot: data['title']?.toString(),
        categorySnapshot: data['category']?.toString(),
      );
    }).toList();
  }

  Future<List<PickedStudyContent>> _queryAllomasok(String prefix) async {
    const userScience = 'Jogász';
    Query<Map<String, dynamic>> q = FirebaseConfig.firestore
        .collection('memoriapalota_allomasok')
        .where('science', isEqualTo: userScience)
        .where('status', isEqualTo: 'Published');
    if (prefix.isNotEmpty) {
      q = q.orderBy('title').startAt([prefix]).endAt(['$prefix\uf8ff']);
    } else {
      q = q.orderBy('modified', descending: true);
    }
    final snap = await q.limit(50).get();
    return snap.docs.map((d) {
      final data = d.data();
      return PickedStudyContent(
        ref: StudyItemRef(
            contentType: 'memoriapalota_allomasok', contentId: d.id),
        titleSnapshot: data['title']?.toString(),
        categorySnapshot: data['category']?.toString(),
      );
    }).toList();
  }

  Future<List<PickedStudyContent>> _queryDialogus(String prefix) async {
    const userScience = 'Jogász';
    Query<Map<String, dynamic>> q = FirebaseConfig.firestore
        .collection('dialogus_fajlok')
        .where('science', isEqualTo: userScience)
        .where('status', isEqualTo: 'Published');
    if (prefix.isNotEmpty) {
      q = q.orderBy('title').startAt([prefix]).endAt(['$prefix\uf8ff']);
    } else {
      q = q.orderBy('modified', descending: true);
    }
    final snap = await q.limit(50).get();
    return snap.docs.map((d) {
      final data = d.data();
      return PickedStudyContent(
        ref: StudyItemRef(contentType: 'dialogus_fajlok', contentId: d.id),
        titleSnapshot: data['title']?.toString(),
        categorySnapshot: data['category']?.toString(),
      );
    }).toList();
  }

  Future<void> _runSearch() async {
    setState(() {
      _loading = true;
    });
    try {
      final prefix = _q.text.trim();
      final lowerPrefix = prefix.toLowerCase();

      final List<PickedStudyContent> out = [];
      final shouldDecks =
          _source == _ContentSource.all || _source == _ContentSource.decks;
      final shouldQuizzes =
          _source == _ContentSource.all || _source == _ContentSource.quizzes;
      final shouldMemoriaUtvonal = _source == _ContentSource.all ||
          _source == _ContentSource.memoriaUtvonal;
      final shouldDialogus =
          _source == _ContentSource.all || _source == _ContentSource.dialogus;

      if (shouldDecks) {
        try {
          out.addAll(await _queryNotes(prefix: prefix, typeEquals: 'deck'));
        } catch (_) {
          // Fallback: no type filter, client-side filter
          final all = await _queryNotes(prefix: prefix);
          out.addAll(all.where((e) => e.ref.contentType == 'deck'));
        }
      }

      if (shouldQuizzes) {
        try {
          out.addAll(await _queryNotes(
              prefix: prefix,
              typeIn: const ['dynamic_quiz', 'dynamic_quiz_dual']));
        } catch (_) {
          final all = await _queryNotes(prefix: prefix);
          out.addAll(all.where((e) => _isQuizType(e.ref.contentType)));
        }
      }

      if (shouldMemoriaUtvonal) out.addAll(await _queryAllomasok(prefix));
      if (shouldDialogus) out.addAll(await _queryDialogus(prefix));

      // extra contains filter (prefix search may be unsupported by indexes)
      final filtered = lowerPrefix.isEmpty
          ? out
          : out
              .where((e) =>
                  (e.titleSnapshot ?? '').toLowerCase().contains(lowerPrefix))
              .toList();

      filtered.sort(
          (a, b) => (a.titleSnapshot ?? '').compareTo(b.titleSnapshot ?? ''));

      setState(() {
        _results = filtered;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Keresési hiba: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final dialogWidth = w > 820 ? 820.0 : w * 0.95;

    return AlertDialog(
      title: const Text('Tartalom hozzáadása a tételhez'),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    decoration: const InputDecoration(
                      labelText: 'Keresés cím alapján',
                      hintText: 'pl. alapjogok, szerződés, …',
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _runSearch,
                  child: const Text('Keres'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Minden'),
                    selected: _source == _ContentSource.all,
                    onSelected: (_) {
                      setState(() => _source = _ContentSource.all);
                      _runSearch();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Tanulókártyák'),
                    selected: _source == _ContentSource.decks,
                    onSelected: (_) {
                      setState(() => _source = _ContentSource.decks);
                      _runSearch();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Kvízek'),
                    selected: _source == _ContentSource.quizzes,
                    onSelected: (_) {
                      setState(() => _source = _ContentSource.quizzes);
                      _runSearch();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Memória útvonal'),
                    selected: _source == _ContentSource.memoriaUtvonal,
                    onSelected: (_) {
                      setState(() => _source = _ContentSource.memoriaUtvonal);
                      _runSearch();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Dialogus'),
                    selected: _source == _ContentSource.dialogus,
                    onSelected: (_) {
                      setState(() => _source = _ContentSource.dialogus);
                      _runSearch();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Flexible(
              child: _results.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Nincs találat.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final r = _results[i];
                        final key = r.ref.toString();
                        final title = (r.titleSnapshot ?? key).trim();
                        final subtitle = [
                          _labelForContentType(r.ref.contentType),
                          if (r.categorySnapshot != null &&
                              r.categorySnapshot!.trim().isNotEmpty)
                            r.categorySnapshot!.trim(),
                        ].join(' · ');
                        return CheckboxListTile(
                          value: _selectedKeys.contains(key),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedKeys.add(key);
                              } else {
                                _selectedKeys.remove(key);
                              }
                            });
                          },
                          title: Text(title),
                          subtitle: Text(subtitle),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Mégse'),
        ),
        ElevatedButton(
          onPressed: _selectedKeys.isEmpty
              ? null
              : () {
                  final selected = _results
                      .where((r) => _selectedKeys.contains(r.ref.toString()))
                      .toList();
                  Navigator.of(context).pop(selected);
                },
          child: Text('Hozzáadás (${_selectedKeys.length})'),
        ),
      ],
    );
  }
}
