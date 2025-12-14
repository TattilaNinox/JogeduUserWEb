import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import '../widgets/header.dart';

class CategoryManagerScreen extends StatefulWidget {
  const CategoryManagerScreen({super.key});

  @override
  State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen> {
  final _categoryController = TextEditingController();
  // Szűréshez
  String? _filterScience;

  List<String> _sciences = [];
  String? _selectedScience;
  Map<String, int> _noteUsageCount = {};
  Map<String, int> _bankUsageCount = {};

  @override
  void initState() {
    super.initState();
    _loadSciences();
    _loadUsageCounts();
  }

  Future<void> _loadSciences() async {
    final snap = await FirebaseFirestore.instance.collection('sciences').get();
    setState(() {
      _sciences = snap.docs.map((d) => d['name'] as String).toList();
    });
  }

  Future<void> _loadUsageCounts() async {
    // Jegyzetek számának lekérése
    final notesSnap =
        await FirebaseFirestore.instance.collection('notes').get();
    final tempNoteCounts = <String, int>{};
    for (var doc in notesSnap.docs) {
      final category = doc.data()['category'] as String?;
      if (category != null) {
        tempNoteCounts[category] = (tempNoteCounts[category] ?? 0) + 1;
      }
    }

    // Kérdésbankok számának lekérése
    final banksSnap =
        await FirebaseFirestore.instance.collection('question_banks').get();
    final tempBankCounts = <String, int>{};
    for (var doc in banksSnap.docs) {
      final category = doc.data()['category'] as String?;
      if (category != null) {
        tempBankCounts[category] = (tempBankCounts[category] ?? 0) + 1;
      }
    }

    if (mounted) {
      setState(() {
        _noteUsageCount = tempNoteCounts;
        _bankUsageCount = tempBankCounts;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addCategory() async {
    final name = _categoryController.text.trim();
    if (name.isEmpty || _selectedScience == null) return;

    final existing = await FirebaseFirestore.instance
        .collection('categories')
        .where('name', isEqualTo: name)
        .where('science', isEqualTo: _selectedScience)
        .get();

    if (existing.docs.isNotEmpty) {
      _showSnackBar('Ez a kategória már létezik.');
      return;
    }

    await FirebaseFirestore.instance
        .collection('categories')
        .add({'name': name, 'science': _selectedScience});
    _categoryController.clear();
    _showSnackBar('Kategória sikeresen hozzáadva.');
  }

  void _confirmDeleteCategory(String docId, String categoryName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Megerősítés'),
        content: Text('Biztosan törlöd a(z) "$categoryName" kategóriát?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();

              final relatedNotes = await FirebaseFirestore.instance
                  .collection('notes')
                  .where('category', isEqualTo: categoryName)
                  .get();

              if (relatedNotes.docs.isNotEmpty) {
                _showSnackBar('Nem törölhető, mert van hozzárendelt jegyzet.');
                return;
              }

              await FirebaseFirestore.instance
                  .collection('categories')
                  .doc(docId)
                  .delete();
              _showSnackBar('Kategória sikeresen törölve.');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Törlés', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(
      String docId, String currentName, String currentScience) {
    final editController = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategória átnevezése'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: currentScience,
              items: _sciences
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => currentScience = v ?? currentScience,
              decoration: const InputDecoration(labelText: 'Tudomány'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: editController,
              decoration: const InputDecoration(labelText: 'Új név'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = editController.text.trim();
              if (newName.isEmpty) return;

              final existing = await FirebaseFirestore.instance
                  .collection('categories')
                  .where('name', isEqualTo: newName)
                  .where('science', isEqualTo: currentScience)
                  .get();

              if (existing.docs.isNotEmpty && existing.docs.first.id != docId) {
                _showSnackBar('Ez a kategória már létezik.');
                return;
              }

              await FirebaseFirestore.instance
                  .collection('categories')
                  .doc(docId)
                  .update({'name': newName, 'science': currentScience});
              if (!context.mounted) return;
              Navigator.of(context).pop();
              _showSnackBar('Kategória sikeresen átnevezve.');
            },
            child: const Text('Mentés'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 249, 250, 251),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'categories'),
          Expanded(
            child: Column(
              children: [
                Header(onSearchChanged: (_) {}),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Kategóriák kezelése',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedScience,
                                items: _sciences
                                    .map((s) => DropdownMenuItem(
                                        value: s, child: Text(s)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _selectedScience = v),
                                decoration: const InputDecoration(
                                    labelText: 'Tudomány'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: _categoryController,
                                decoration: const InputDecoration(
                                    labelText: 'Új kategória neve'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _addCategory,
                              child: const Text('Hozzáadás'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text('Kategóriák:',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        DropdownButton<String?>(
                          value: _filterScience,
                          hint: const Text('Tudomány szűrő (Összes)'),
                          items: [null, ..._sciences]
                              .map((s) => DropdownMenuItem(
                                  value: s, child: Text(s ?? 'Összes')))
                              .toList(),
                          onChanged: (v) => setState(() => _filterScience = v),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('categories')
                                .orderBy('name')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              if (!snapshot.hasData ||
                                  snapshot.data!.docs.isEmpty) {
                                return const Text('Nincs elérhető kategória.');
                              }

                              final allCategories = snapshot.data!.docs;

                              final filteredCategories =
                                  allCategories.where((doc) {
                                if (_filterScience != null) {
                                  return doc['science'] == _filterScience;
                                }
                                return true;
                              }).toList();

                              if (filteredCategories.isEmpty) {
                                return const Text('Nincs találat a keresésre.');
                              }

                              return ListView.builder(
                                itemCount: filteredCategories.length,
                                itemBuilder: (context, index) {
                                  final doc = filteredCategories[index];
                                  final name = doc['name'] as String;
                                  final science =
                                      doc['science'] as String? ?? '';
                                  final noteCount = _noteUsageCount[name] ?? 0;
                                  final bankCount = _bankUsageCount[name] ?? 0;
                                  final isUsed = noteCount > 0 || bankCount > 0;

                                  return ListTile(
                                    title: Text(name),
                                    subtitle: Text(
                                        '$science  •  Jegyzetek: $noteCount, Kérdésbankok: $bankCount'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          color: isUsed
                                              ? Colors.grey
                                              : Colors.blue,
                                          tooltip: isUsed
                                              ? 'Használatban lévő kategória nem szerkeszthető'
                                              : 'Szerkesztés',
                                          onPressed: isUsed
                                              ? null
                                              : () => _showEditCategoryDialog(
                                                  doc.id, name, science),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete),
                                          color:
                                              isUsed ? Colors.grey : Colors.red,
                                          tooltip: isUsed
                                              ? 'Használatban lévő kategória nem törölhető'
                                              : 'Törlés',
                                          onPressed: isUsed
                                              ? null
                                              : () => _confirmDeleteCategory(
                                                  doc.id, name),
                                        ),
                                      ],
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
