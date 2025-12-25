import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../core/firebase_config.dart';

/// Dokumentum kiválasztó képernyő (teljes képernyős, mobil-barát).
///
/// Három típusú dokumentumot támogat:
/// - notes: Jegyzetek (minden típus: standard, deck, quiz, stb.)
/// - allomasok: Memóriapalota állomások
/// - dialogus: Dialógus fájlok
class DocumentSelectionScreen extends StatefulWidget {
  final String bundleId;
  final String documentType;

  const DocumentSelectionScreen({
    super.key,
    required this.bundleId,
    required this.documentType,
  });

  @override
  State<DocumentSelectionScreen> createState() =>
      _DocumentSelectionScreenState();
}

class _DocumentSelectionScreenState extends State<DocumentSelectionScreen> {
  final Set<String> _selectedIds = {};
  String _searchText = '';
  bool _selectAll = false;
  List<QueryDocumentSnapshot> _allDocuments = [];
  List<QueryDocumentSnapshot> _filteredDocuments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Kollekció név meghatározása
      String collectionName;
      if (widget.documentType == 'notes') {
        collectionName = 'notes';
      } else if (widget.documentType == 'allomasok') {
        collectionName = 'memoriapalota_allomasok';
      } else if (widget.documentType == 'dialogus') {
        collectionName = 'dialogus_fajlok';
      } else {
        throw Exception('Ismeretlen dokumentum típus: ${widget.documentType}');
      }

      // Lekérdezés: Published státuszú dokumentumok
      Query query = FirebaseConfig.firestore
          .collection(collectionName)
          .where('science', isEqualTo: 'Jogász')
          .where('status', isEqualTo: 'Published');

      final snapshot = await query.get();

      setState(() {
        _allDocuments = snapshot.docs;
        _filteredDocuments = _allDocuments;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a dokumentumok betöltésekor: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _filterDocuments(String query) {
    setState(() {
      _searchText = query;
      if (query.isEmpty) {
        _filteredDocuments = _allDocuments;
      } else {
        _filteredDocuments = _allDocuments.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final title = data['title']?.toString().toLowerCase() ?? '';
          final name = data['name']?.toString().toLowerCase() ?? '';
          final category = data['category']?.toString().toLowerCase() ?? '';
          final searchLower = query.toLowerCase();
          return title.contains(searchLower) ||
              name.contains(searchLower) ||
              category.contains(searchLower);
        }).toList();
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedIds.addAll(_filteredDocuments.map((doc) => doc.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectAll = false;
      } else {
        _selectedIds.add(id);
        if (_selectedIds.length == _filteredDocuments.length) {
          _selectAll = true;
        }
      }
    });
  }

  Future<void> _addSelectedDocuments() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Válassz ki legalább egy dokumentumot!')),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Nincs bejelentkezett felhasználó');

      // Ha új köteg (bundleId == 'create'), először létrehozzuk
      String bundleId = widget.bundleId;
      if (bundleId == 'create') {
        final newBundle = await FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .add({
          'name': 'Új köteg',
          'description': '',
          'noteIds':
              widget.documentType == 'notes' ? _selectedIds.toList() : [],
          'allomasIds':
              widget.documentType == 'allomasok' ? _selectedIds.toList() : [],
          'dialogusIds':
              widget.documentType == 'dialogus' ? _selectedIds.toList() : [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        bundleId = newBundle.id;
      } else {
        // Meglévő köteg frissítése
        final bundleRef = FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .doc(bundleId);

        final doc = await bundleRef.get();
        if (!doc.exists) {
          throw Exception('Köteg nem található');
        }

        final data = doc.data()!;
        final noteIds = List<String>.from(data['noteIds'] ?? []);
        final allomasIds = List<String>.from(data['allomasIds'] ?? []);
        final dialogusIds = List<String>.from(data['dialogusIds'] ?? []);

        // Hozzáadjuk az új ID-kat (duplikáció elkerülése)
        if (widget.documentType == 'notes') {
          for (final id in _selectedIds) {
            if (!noteIds.contains(id)) noteIds.add(id);
          }
        } else if (widget.documentType == 'allomasok') {
          for (final id in _selectedIds) {
            if (!allomasIds.contains(id)) allomasIds.add(id);
          }
        } else if (widget.documentType == 'dialogus') {
          for (final id in _selectedIds) {
            if (!dialogusIds.contains(id)) dialogusIds.add(id);
          }
        }

        await bundleRef.update({
          'noteIds': noteIds,
          'allomasIds': allomasIds,
          'dialogusIds': dialogusIds,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedIds.length} dokumentum hozzáadva!'),
          ),
        );
        context.go('/my-bundles/edit/$bundleId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba történt: $e')),
        );
      }
    }
  }

  String _getTitle() {
    if (widget.documentType == 'notes') {
      return 'Jegyzetek kiválasztása';
    } else if (widget.documentType == 'allomasok') {
      return 'Állomások kiválasztása';
    } else {
      return 'Dialógusok kiválasztása';
    }
  }

  IconData _getIcon(Map<String, dynamic> data) {
    if (widget.documentType == 'notes') {
      final type = data['type'] as String?;
      switch (type) {
        case 'deck':
          return Icons.style;
        case 'interactive':
          return Icons.touch_app;
        case 'dynamic_quiz':
        case 'dynamic_quiz_dual':
          return Icons.quiz;
        default:
          return Icons.description;
      }
    } else if (widget.documentType == 'allomasok') {
      return Icons.train;
    } else {
      return Icons.chat_bubble_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/my-bundles/edit/${widget.bundleId}'),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Keresőmező (sticky)
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.white,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Keresés...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                    onChanged: _filterDocuments,
                  ),
                ),

                // "Mind kiválasztása" checkbox
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  color: Colors.grey.shade50,
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selectAll,
                        onChanged: (_) => _toggleSelectAll(),
                      ),
                      Text(
                        'Mind kiválasztása (${_filteredDocuments.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                // Dokumentumok listája
                Expanded(
                  child: _filteredDocuments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchText.isEmpty
                                    ? 'Nincs elérhető dokumentum'
                                    : 'Nincs találat a keresésre',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredDocuments.length,
                          itemBuilder: (context, index) {
                            final doc = _filteredDocuments[index];
                            final data = doc.data() as Map<String, dynamic>;
                            // Több mezőt is ellenőrzünk a cím megtalálásához
                            final title = data['title'] ??
                                data['name'] ??
                                data['utvonalNev'] ??
                                data['cím'] ??
                                'Névtelen';
                            final category = data['category'] ?? '';
                            final isSelected = _selectedIds.contains(doc.id);

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 4.0,
                              ),
                              child: InkWell(
                                onTap: () => _toggleSelection(doc.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      // Checkbox bal oldalon (hüvelykujj-barát)
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (_) =>
                                            _toggleSelection(doc.id),
                                      ),
                                      const SizedBox(width: 12),
                                      // Ikon
                                      Icon(
                                        _getIcon(data),
                                        color: Theme.of(context).primaryColor,
                                      ),
                                      const SizedBox(width: 12),
                                      // Tartalom
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (category.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                category,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Kiválasztott elemek számlálója és hozzáadás gomb
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedIds.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              'Kiválasztva: ${_selectedIds.length} dokumentum',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : _addSelectedDocuments,
                            icon: const Icon(Icons.check),
                            label: Text(
                              _selectedIds.isEmpty
                                  ? 'Válassz ki dokumentumokat'
                                  : 'Hozzáadás (${_selectedIds.length})',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              disabledForegroundColor: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
