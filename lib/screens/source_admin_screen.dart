import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/header.dart';
import '../widgets/sidebar.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

/// Admin felület a források / irodalmi hivatkozások kezeléséhez.
/// A forrásokat mostantól ugyanabban a `notes` gyűjteményben tároljuk
/// mint a többi jegyzetet, de egy új `type = "source"` mezővel.
/// Így a mobil-/webalkalmazás jegyzetlistájában automatikusan
/// megjelennek, a címeknél pedig engedjük a duplikációt.
class SourceAdminScreen extends StatefulWidget {
  const SourceAdminScreen({super.key});

  @override
  State<SourceAdminScreen> createState() => _SourceAdminScreenState();
}

class _SourceAdminScreenState extends State<SourceAdminScreen> {
  // ─────────────────────── Controllers & State ────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();

  // Kategóriák
  List<String> _categories = [];
  String? _selectedCategory;

  // Címkék
  final List<String> _tags = [];
  final _tagController = TextEditingController();

  // Egyéb állapotok
  String? _editingDocId; // Ha null → új forrás
  String _searchText = '';

  // ───────────────────────── Lifecycle ───────────────────────────────
  bool _initializedFromQuery = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedFromQuery) return;
    final uri = GoRouterState.of(context).uri;
    final editId = uri.queryParameters['edit'];
    if (editId != null && editId.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('notes')
          .doc(editId)
          .get()
          .then((doc) {
        if (doc.exists && mounted) {
          _startEdit(doc);
        }
      });
    }
    _initializedFromQuery = true;
  }

  Future<void> _loadCategories() async {
    final snap =
        await FirebaseFirestore.instance.collection('categories').get();
    if (mounted) {
      setState(() {
        _categories = snap.docs.map((d) => d['name'] as String).toList();
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _descCtrl.dispose();
    _orderCtrl.dispose();
    _tagController.dispose();
    super.dispose();
  }

  // ────────────────────────── Actions ────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Mentse el globális címke-listába is, hogy autocomplete-nél elérhető legyen.
    for (final tag in _tags) {
      FirebaseFirestore.instance.collection('tags').doc(tag).set({'name': tag});
    }

    final data = {
      'title': _titleCtrl.text.trim(),
      'url': _urlCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'order': int.tryParse(_orderCtrl.text.trim()) ?? 0,
      'category': _selectedCategory,
      'tags': _tags,
      'type': 'source', // ← Új jegyzettípus
      'status': 'Draft', // induláskor még nem publikus
      'isFree': false, // zárolt, amíg publikálva nincs
      'modified': FieldValue.serverTimestamp(),
      'pages': <String>[], // a jelenlegi struktúra miatt üres lista
    };

    final notesColl = FirebaseFirestore.instance.collection('notes');
    final docId = _editingDocId ?? notesColl.doc().id;

    if (_editingDocId == null) {
      await notesColl.doc(docId).set(data);
    } else {
      await notesColl.doc(docId).update(data);
    }

    _clearForm();
  }

  void _startEdit(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    setState(() {
      _titleCtrl.text = d['title'] ?? '';
      _urlCtrl.text = d['url'] ?? '';
      _descCtrl.text = d['description'] ?? '';
      _orderCtrl.text = (d['order'] ?? '').toString();
      _selectedCategory = d['category'];
      _tags
        ..clear()
        ..addAll(List<String>.from(d['tags'] ?? []));
      _tagController.clear();
      _editingDocId = doc.id;
    });
  }

  Future<void> _delete(String docId) async {
    await FirebaseFirestore.instance.collection('notes').doc(docId).delete();
    if (_editingDocId == docId) _clearForm();
  }

  void _clearForm() {
    setState(() {
      _titleCtrl.clear();
      _urlCtrl.clear();
      _descCtrl.clear();
      _orderCtrl.clear();
      _selectedCategory = null;
      _tags.clear();
      _tagController.clear();
      _editingDocId = null;
    });
  }

  void _onSearchChanged(String value) => setState(() => _searchText = value);

  // ─────────────────────────── Build ─────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFFF9FAFB);
    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'sources_admin'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Header(onSearchChanged: _onSearchChanged),
                Expanded(
                  child: Row(
                    children: [
                      // Lista
                      Expanded(
                        flex: 2,
                        child: Container(
                          margin: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withAlpha(20),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          child: _buildSourceList(),
                        ),
                      ),
                      // Űrlap
                      Expanded(
                        flex: 1,
                        child: Container(
                          margin: const EdgeInsets.only(
                              top: 24, right: 24, bottom: 24),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withAlpha(20),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          child: _buildForm(),
                        ),
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

  // ───────────────────────── List & Table ────────────────────────────
  Widget _buildSourceList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notes')
          .where('type', isEqualTo: 'source')
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Hiba: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snapshot.data!.docs;
        // Keresőfilter
        if (_searchText.isNotEmpty) {
          final lower = _searchText.toLowerCase();
          docs = docs.where((d) {
            final data = d.data();
            return (data['title'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(lower) ||
                (data['description'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(lower) ||
                (data['category'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(lower) ||
                (data['tags'] ?? []).toString().toLowerCase().contains(lower);
          }).toList();
        }
        if (docs.isEmpty) {
          return const Center(child: Text('Nincs megjeleníthető forrás.'));
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            const minW = 1000.0;
            final table = Column(
              children: [
                _buildHeaderRow(),
                Expanded(
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) =>
                        _buildDataRow(index, docs[index]),
                  ),
                ),
              ],
            );
            if (constraints.maxWidth < minW) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: minW, child: table),
              );
            }
            return table;
          },
        );
      },
    );
  }

  Widget _buildHeaderRow() {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 13);
    Widget cell(String t, int flex) =>
        Expanded(flex: flex, child: Text(t, style: style));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F5F7),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          cell('#', 1),
          cell('Cím', 3),
          cell('URL', 3),
          cell('Kategória', 2),
          cell('Címkék', 3),
          cell('Sorrend', 1),
          cell('Művelet', 2),
        ],
      ),
    );
  }

  Widget _buildDataRow(int index, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    const style = TextStyle(fontSize: 12);
    Widget textCell(String t, int flex) => Expanded(
          flex: flex,
          child: Text(t,
              style: style,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false),
        );
    final tagsList =
        (d['tags'] is List) ? (d['tags'] as List).cast<String>() : <String>[];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB)))),
      child: Row(
        children: [
          textCell('${index + 1}', 1),
          textCell(d['title'] ?? '', 3),
          textCell(d['url'] ?? '', 3),
          textCell(d['category'] ?? '', 2),
          textCell(tagsList.join(', '), 3),
          textCell('${d['order'] ?? ''}', 1),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: AppTheme.primaryColor),
                  tooltip: 'Szerkesztés',
                  onPressed: () => _startEdit(doc),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Törlés',
                  onPressed: () => _delete(doc.id),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── Form ────────────────────────────────
  Widget _buildForm() {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_editingDocId == null ? 'Új forrás' : 'Forrás szerkesztése',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Cím *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Kötelező' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Leírás'),
            ),
            const SizedBox(height: 16),
            _buildCategoryDropdown(),
            const SizedBox(height: 16),
            _buildTagsSection(),
            const SizedBox(height: 16),
            TextFormField(
              controller: _orderCtrl,
              decoration: const InputDecoration(labelText: 'Sorrend'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Mentés'),
              ),
            ),
            if (_editingDocId != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _clearForm,
                  child: const Text('Mégse'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      items: _categories
          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
          .toList(),
      onChanged: (val) => setState(() => _selectedCategory = val),
      decoration: const InputDecoration(labelText: 'Kategória'),
    );
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
                  onDeleted: () => setState(() => _tags.remove(tag))))
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
                    _tags.add(_tagController.text.trim());
                    _tagController.clear();
                  });
                }
              },
            ),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty && !_tags.contains(value)) {
              setState(() {
                _tags.add(value.trim());
                _tagController.clear();
              });
            }
          },
        ),
      ],
    );
  }
}
