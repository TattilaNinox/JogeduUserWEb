import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../widgets/sidebar.dart';
import 'package:web/web.dart' as web;
import 'package:file_selector/file_selector.dart';
import 'package:excel/excel.dart';
import '../widgets/flippable_card.dart';
import 'dart:convert';

class DeckEditScreen extends StatefulWidget {
  final String deckId;
  const DeckEditScreen({super.key, required this.deckId});

  @override
  State<DeckEditScreen> createState() => _DeckEditScreenState();
}

class _DeckEditScreenState extends State<DeckEditScreen> {
  final _titleController = TextEditingController();
  String? _selectedCategory;
  List<Map<String, dynamic>> _flashcards = [];
  bool _isLoading = true;
  Map<String, String> _categories = {};
  List<String> _sciences = [];
  String? _selectedScience;
  List<String> _tags = [];
  final _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Címkék',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _tags
              .map((tag) => Chip(
                    label: Text(tag),
                    onDeleted: () => setState(() => _tags.remove(tag)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tagController,
          decoration: InputDecoration(
            labelText: 'Új címke',
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                if (_tagController.text.isNotEmpty &&
                    !_tags.contains(_tagController.text)) {
                  setState(() {
                    _tags.add(_tagController.text);
                    _tagController.clear();
                  });
                }
              },
            ),
          ),
          onSubmitted: (val) {
            if (val.isNotEmpty && !_tags.contains(val)) {
              setState(() {
                _tags.add(val);
                _tagController.clear();
              });
            }
          },
        ),
      ],
    );
  }

  Future<void> _loadInitialData() async {
    await _loadSciences();
    // Először a pakli adatai (tudomány, kategória) töltsenek be
    await _loadDeckDetails();
    // Ezután a kiválasztott tudomány alapján töltsük a kategóriákat
    await _loadCategories();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDeckDetails() async {
    final doc = await FirebaseFirestore.instance
        .collection('notes')
        .doc(widget.deckId)
        .get();
    if (doc.exists && mounted) {
      final data = doc.data()!;
      _titleController.text = data['title'];
      _flashcards = List<Map<String, dynamic>>.from(data['flashcards'] ?? []);
      setState(() {
        _selectedScience = data['science'];
        _selectedCategory = data['category_id'];
        _tags = List<String>.from(data['tags'] ?? []);
      });
    }
  }

  Future<void> _saveDeck() async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (_titleController.text.trim().isEmpty ||
        _selectedScience == null ||
        _selectedCategory == null) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('A cím, tudomány és kategória kitöltése kötelező!')),
      );
      return;
    }

    // Címkék mentése a közös gyűjteménybe
    for (final tag in _tags) {
      FirebaseFirestore.instance.collection('tags').doc(tag).set({'name': tag});
    }

    try {
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.deckId)
          .update({
        'title': _titleController.text.trim(),
        'science': _selectedScience,
        'category_id': _selectedCategory,
        'category': _categories[_selectedCategory] ?? '',
        'flashcards': _flashcards,
        'tags': _tags,
        'modified': Timestamp.now(),
      });

      if (!mounted) return;

      messenger.showSnackBar(const SnackBar(content: Text('Pakli mentve!')));
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!mounted) return;
      router.go('/decks');
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Hiba a mentés során: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _exportToExcel() async {
    final excel = Excel.createExcel();
    final Sheet sheetObject = excel['Tanulókártyák'];
    final header = ['Előlap', 'Hátlap'];
    sheetObject.appendRow(header);

    for (final card in _flashcards) {
      final row = [
        card['front'] as String? ?? '',
        card['back'] as String? ?? '',
      ];
      sheetObject.appendRow(row);
    }
    final bytes = excel.save();
    if (bytes != null) {
      // Egyszerűbb megközelítés a fájl letöltéshez
      final dataUrl =
          'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,${base64Encode(bytes)}';
      web.HTMLAnchorElement()
        ..href = dataUrl
        ..setAttribute('download', '${_titleController.text.trim()}.xlsx')
        ..click();
    }
  }

  Future<void> _importFromExcel() async {
    const typeGroup = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hiba: Nem található munkalap.')));
      return;
    }
    final newFlashcards = <Map<String, dynamic>>[];
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every(
          (cell) => cell == null || cell.value.toString().trim().isEmpty)) {
        continue;
      }
      try {
        final frontText = row[0]?.value.toString().trim() ?? '';
        final backText = row[1]?.value.toString().trim() ?? '';
        if (frontText.isEmpty && backText.isEmpty) continue;

        newFlashcards.add({'front': frontText, 'back': backText});
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Hiba a(z) ${i + 1}. sor feldolgozásakor: $e')));
        return;
      }
    }
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importálás megerősítése'),
        content: Text(
            'A fájlban ${newFlashcards.length} kártya található. A jelenlegi pakliban ${_flashcards.length} kártya van. Mit szeretnél tenni?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Mégse')),
          TextButton(
              onPressed: () => Navigator.of(context).pop('append'),
              child: const Text('Hozzáfűzés')),
          TextButton(
              onPressed: () => Navigator.of(context).pop('replace'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Felülírás')),
        ],
      ),
    );
    if (action == 'append') {
      final existing = _flashcards
          .map((c) => ((c['front'] ?? '') as String).trim().toLowerCase())
          .toSet();
      final uniqueToAdd = newFlashcards
          .where((c) => !existing
              .contains(((c['front'] ?? '') as String).trim().toLowerCase()))
          .toList();
      final skipped = newFlashcards.length - uniqueToAdd.length;
      setState(() => _flashcards.addAll(uniqueToAdd));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Import sikeres: ${uniqueToAdd.length} új kártya hozzáadva${skipped > 0 ? ', $skipped duplikált kihagyva' : ''}. Ne felejts el menteni.')));
      }
    } else if (action == 'replace') {
      setState(() => _flashcards = newFlashcards);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Sikeres importálás: kártyák felülírva. Ne felejts el menteni.')));
      }
    }
  }

  void _addFlashcard() {
    setState(() {
      _flashcards.add({
        'front': 'Új kártya - Előlap',
        'back': 'Új kártya - Hátlap',
      });
    });
  }

  Future<void> _loadSciences() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('sciences').get();
    if (mounted) {
      setState(() {
        _sciences = snapshot.docs.map((doc) => doc['name'] as String).toList();
      });
    }
  }

  Future<void> _loadCategories() async {
    if (_selectedScience == null) {
      if (mounted) {
        setState(() {
          _categories = {};
        });
      }
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('categories')
        .where('science', isEqualTo: _selectedScience)
        .get();
    if (mounted) {
      setState(() {
        _categories = {
          for (var doc in snapshot.docs) doc.id: doc['name'] as String
        };
      });
    }
  }

  void _showCardPreview(Map<String, dynamic> card) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 350,
          height: 220,
          child: FlippableCard(
            frontText: card['front'] ?? '',
            backText: card['back'] ?? '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Bezárás')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Betöltés...')),
          body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tanulókártya pakli szerkesztése'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/decks'),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _exportToExcel,
              tooltip: 'Exportálás Excelbe'),
          IconButton(
              icon: const Icon(Icons.file_upload),
              onPressed: _importFromExcel,
              tooltip: 'Importálás Excelből'),
          IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveDeck,
              tooltip: 'Mentés'),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'decks'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          decoration:
                              const InputDecoration(labelText: 'Pakli címe'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedScience,
                          items: _sciences
                              .map((String science) => DropdownMenuItem<String>(
                                  value: science, child: Text(science)))
                              .toList(),
                          onChanged: (newValue) {
                            setState(() {
                              _selectedScience = newValue;
                              _selectedCategory = null;
                            });
                            _loadCategories();
                          },
                          decoration:
                              const InputDecoration(labelText: 'Tudomány'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              _categories.containsKey(_selectedCategory)
                                  ? _selectedCategory
                                  : null,
                          items: _categories.entries.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            );
                          }).toList(),
                          onChanged: _selectedScience == null
                              ? null
                              : (val) {
                                  setState(() => _selectedCategory = val);
                                },
                          decoration: InputDecoration(
                            labelText: 'Kategória',
                            fillColor: _selectedScience == null
                                ? Colors.grey[100]
                                : Colors.white,
                            filled: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildTagsSection(),
                  const SizedBox(height: 24),
                  const Text('Tanulókártyák',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(height: 24),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: _flashcards.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = _flashcards.removeAt(oldIndex);
                          _flashcards.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        return _buildFlashcardEditor(_flashcards[index], index,
                            key: ValueKey(index));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addFlashcard,
        tooltip: 'Új kártya hozzáadása',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFlashcardEditor(Map<String, dynamic> card, int index,
      {Key? key}) {
    final frontController =
        TextEditingController(text: card['front'] as String? ?? '');
    frontController
        .addListener(() => _flashcards[index]['front'] = frontController.text);

    final backController =
        TextEditingController(text: card['back'] as String? ?? '');
    backController
        .addListener(() => _flashcards[index]['back'] = backController.text);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kártya ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _flashcards.removeAt(index);
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.visibility, color: Colors.blue),
                  onPressed: () => _showCardPreview(card),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 32.0),
              child: TextField(
                controller: frontController,
                decoration: const InputDecoration(labelText: 'Előlap'),
                maxLines: null,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 32.0),
              child: TextField(
                controller: backController,
                decoration: const InputDecoration(labelText: 'Hátlap'),
                maxLines: null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
