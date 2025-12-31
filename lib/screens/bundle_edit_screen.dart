import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

/// Köteg (bundle) szerkesztő képernyő.
///
/// Ez a képernyő szolgál új köteg létrehozására és meglévő köteg szerkesztésére.
/// A kötegbe csak azonos kategóriájú és címkéjű jegyzetek adhatók hozzá.
/// Az első hozzáadott jegyzet határozza meg a köteg kategóriáját és címkéit.
class BundleEditScreen extends StatefulWidget {
  final String? bundleId; // null esetén új köteg létrehozása

  const BundleEditScreen({super.key, this.bundleId});

  @override
  State<BundleEditScreen> createState() => _BundleEditScreenState();
}

class _BundleEditScreenState extends State<BundleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<String> _selectedNoteIds = [];
  Map<String, Map<String, dynamic>> _notesData = {};
  String? _bundleCategory;
  List<String> _bundleTags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBundle();
  }

  /// Betölti a meglévő köteg adatait vagy inicializálja az új köteget
  Future<void> _loadBundle() async {
    if (widget.bundleId != null) {
      final doc = await FirebaseFirestore.instance
          .collection('bundles')
          .doc(widget.bundleId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _nameController.text = data['name'] ?? '';
        _descriptionController.text = data['description'] ?? '';
        _selectedNoteIds = List<String>.from(data['noteIds'] ?? []);
        _bundleCategory = data['category'];
        _bundleTags = List<String>.from(data['tags'] ?? []);

        // Betöltjük a kiválasztott jegyzetek adatait
        await _loadNotesData(_selectedNoteIds);
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// Betölti a megadott jegyzetek adatait
  Future<void> _loadNotesData(List<String> noteIds) async {
    final notes = await FirebaseFirestore.instance
        .collection('notes')
        .where(FieldPath.documentId, whereIn: noteIds.isEmpty ? [''] : noteIds)
        .get();

    _notesData = {for (var doc in notes.docs) doc.id: doc.data()};
  }

  /// Jegyzetek hozzáadása dialógus megnyitása
  Future<void> _showAddNotesDialog() async {
    // Lekérjük az összes jegyzetet
    Query query = FirebaseFirestore.instance.collection('notes');

    // Ha már van kategória és címke beállítva, szűrjük a jegyzeteket
    if (_bundleCategory != null) {
      query = query.where('category', isEqualTo: _bundleCategory);
    }

    final snapshot = await query.get();
    var availableNotes = snapshot.docs.where((doc) {
      // Kiszűrjük a már hozzáadott jegyzeteket
      if (_selectedNoteIds.contains(doc.id)) return false;

      final data = doc.data() as Map<String, dynamic>;

      // Ha van már címke beállítva, ellenőrizzük hogy megegyezik-e
      if (_bundleTags.isNotEmpty) {
        final noteTags = List<String>.from(data['tags'] ?? []);
        // Ellenőrizzük hogy a jegyzet összes címkéje megegyezik-e
        if (noteTags.length != _bundleTags.length) return false;
        for (var tag in _bundleTags) {
          if (!noteTags.contains(tag)) return false;
        }
      }

      return true;
    }).toList();

    if (!mounted) return;

    if (availableNotes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _bundleCategory == null
                ? 'Nincs elérhető jegyzet'
                : 'Nincs több azonos kategóriájú és címkéjű jegyzet',
          ),
        ),
      );
      return;
    }

    // Dialógus megjelenítése a jegyzetek kiválasztásához
    final selectedIds = await showDialog<List<String>>(
      context: context,
      builder: (context) => _NoteSelectionDialog(
        availableNotes: availableNotes,
        bundleCategory: _bundleCategory,
        bundleTags: _bundleTags,
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty) {
      setState(() {
        _selectedNoteIds.addAll(selectedIds);

        // Ha ez az első jegyzet, beállítjuk a kategóriát és címkéket
        if (_bundleCategory == null && selectedIds.isNotEmpty) {
          final firstNoteData = availableNotes
              .firstWhere((doc) => doc.id == selectedIds.first)
              .data() as Map<String, dynamic>;
          _bundleCategory = firstNoteData['category'];
          _bundleTags = List<String>.from(firstNoteData['tags'] ?? []);
        }
      });

      // Betöltjük az új jegyzetek adatait és frissítjük a státuszukat
      await _loadNotesData(_selectedNoteIds);
      final batch = FirebaseFirestore.instance.batch();
      for (final noteId in selectedIds) {
        final noteRef =
            FirebaseFirestore.instance.collection('notes').doc(noteId);
        batch.update(noteRef, {'status': 'Archived'});
      }
      await batch.commit();

      setState(() {});
    }
  }

  /// Jegyzet eltávolítása a kötegből megerősítéssel
  Future<void> _removeNote(String noteId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Törlés megerősítése'),
        content: const Text('Biztosan eltávolítod ezt a jegyzetet a kötegből?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Mégse'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eltávolítás'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Frissítjük a jegyzet státuszát 'Draft'-ra
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId)
          .update({'status': 'Draft', 'bundleId': FieldValue.delete()});

      setState(() {
        _selectedNoteIds.remove(noteId);
        _notesData.remove(noteId);

        // Ha ez volt az utolsó jegyzet, reseteljük a kategóriát és címkéket
        if (_selectedNoteIds.isEmpty) {
          _bundleCategory = null;
          _bundleTags = [];
        }
      });
    }
  }

  /// Köteg mentése
  Future<void> _saveBundle() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedNoteIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Legalább egy jegyzetet hozzá kell adni!')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final bundleData = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'noteIds': _selectedNoteIds,
        'category': _bundleCategory,
        'tags': _bundleTags,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      String bundleId;
      if (widget.bundleId == null) {
        // Új köteg létrehozása
        bundleData['createdAt'] = FieldValue.serverTimestamp();
        final docRef = await FirebaseFirestore.instance
            .collection('bundles')
            .add(bundleData);
        bundleId = docRef.id;
      } else {
        // Meglévő köteg frissítése
        bundleId = widget.bundleId!;
        await FirebaseFirestore.instance
            .collection('bundles')
            .doc(bundleId)
            .update(bundleData);
      }

      // Jegyzetek bundleId mezőjének frissítése
      final batch = FirebaseFirestore.instance.batch();
      for (final noteId in _selectedNoteIds) {
        final noteRef =
            FirebaseFirestore.instance.collection('notes').doc(noteId);
        batch.update(noteRef, {'bundleId': bundleId});
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.bundleId == null
                  ? 'Köteg sikeresen létrehozva!'
                  : 'Köteg sikeresen frissítve!',
            ),
          ),
        );
        context.go('/bundles');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba történt: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Betöltés...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.bundleId == null ? 'Új köteg' : 'Köteg szerkesztése'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/bundles'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alapadatok - kisebb kártyában, egymás mellett
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Név és leírás oszlop
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Alapadatok',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Köteg neve',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'A név megadása kötelező';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _descriptionController,
                              decoration: const InputDecoration(
                                labelText: 'Leírás',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Kategória és címkék info oszlop
                  if (_bundleCategory != null || _bundleTags.isNotEmpty)
                    Expanded(
                      flex: 1,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Köteg tulajdonságai',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_bundleCategory != null) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(Icons.category, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _bundleCategory!,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (_bundleTags.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.label, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: _bundleTags
                                            .map((tag) => Chip(
                                                  label: Text(tag),
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ))
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Jegyzetek fejléc
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Jegyzetek (${_selectedNoteIds.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _showAddNotesDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Jegyzet hozzáadása'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              // Jegyzetek lista
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectedNoteIds.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Icon(
                                Icons.note_add,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Még nincs jegyzet hozzáadva',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Kattints a "Jegyzet hozzáadása" gombra!',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            itemCount: _selectedNoteIds.length,
                            proxyDecorator: (child, index, animation) {
                              return Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(6),
                                child: child,
                              );
                            },
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) {
                                  newIndex -= 1;
                                }
                                final noteId =
                                    _selectedNoteIds.removeAt(oldIndex);
                                _selectedNoteIds.insert(newIndex, noteId);
                              });
                            },
                            itemBuilder: (context, index) {
                              final noteId = _selectedNoteIds[index];
                              final noteData = _notesData[noteId];
                              final title =
                                  noteData?['title'] ?? 'Ismeretlen jegyzet';
                              final tags = (noteData?['tags'] as List?)
                                      ?.take(2)
                                      .join(', ') ??
                                  '';

                              return ReorderableDragStartListener(
                                key: ValueKey(noteId),
                                index: index,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        // Törlés gomb - bal szélén
                                        Material(
                                          color: Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: InkWell(
                                            onTap: () => _removeNote(noteId),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Icon(
                                                Icons.delete_forever,
                                                size: 18,
                                                color: Colors.red.shade600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Sorszám
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .primaryColor
                                                .withAlpha(26),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${index + 1}',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .primaryColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Tartalom
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                title,
                                                style: const TextStyle(
                                                    fontSize: 14),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (tags.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  tags,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),

                                        // Előnézet gomb
                                        IconButton(
                                          icon: const Icon(Icons.visibility),
                                          iconSize: 22.0,
                                          tooltip: 'Előnézet',
                                          onPressed: () {
                                            final noteType =
                                                noteData?['type'] as String? ??
                                                    'standard';
                                            final returnPath =
                                                '/bundles/edit/${widget.bundleId}';
                                            if (noteType == 'interactive') {
                                              context.go(
                                                  '/interactive-note/$noteId?from=${Uri.encodeComponent(returnPath)}');
                                            } else {
                                              context.go(
                                                  '/note/$noteId?from=${Uri.encodeComponent(returnPath)}');
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          iconSize: 22.0,
                                          tooltip: 'Szerkesztés',
                                          onPressed: () {
                                            final noteType =
                                                noteData?['type'] as String? ??
                                                    'standard';
                                            String editPath;
                                            if (noteType == 'dynamic_quiz') {
                                              editPath = '/quiz/edit/$noteId';
                                            } else if (noteType ==
                                                'dynamic_quiz_dual') {
                                              editPath =
                                                  '/quiz-dual/edit/$noteId';
                                            } else {
                                              editPath = '/note/edit/$noteId';
                                            }
                                            final returnPath = widget
                                                        .bundleId ==
                                                    null
                                                ? '/bundles/create'
                                                : '/bundles/edit/${widget.bundleId}';
                                            context.go(
                                                '$editPath?from=${Uri.encodeComponent(returnPath)}');
                                          },
                                        ),
                                        const SizedBox(width: 24),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Mentés gombok
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => context.go('/bundles'),
                    child: const Text('Mégse'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _saveBundle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child:
                        Text(widget.bundleId == null ? 'Létrehozás' : 'Mentés'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

/// Jegyzetek kiválasztása dialógus
class _NoteSelectionDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot> availableNotes;
  final String? bundleCategory;
  final List<String> bundleTags;

  const _NoteSelectionDialog({
    required this.availableNotes,
    this.bundleCategory,
    required this.bundleTags,
  });

  @override
  State<_NoteSelectionDialog> createState() => _NoteSelectionDialogState();
}

class _NoteSelectionDialogState extends State<_NoteSelectionDialog> {
  final Set<String> _selectedIds = {};
  String _searchText = '';

  @override
  Widget build(BuildContext context) {
    final filteredNotes = widget.availableNotes.where((doc) {
      if (_searchText.isEmpty) return true;
      final data = doc.data() as Map<String, dynamic>;
      final title = data['title']?.toString().toLowerCase() ?? '';
      return title.contains(_searchText.toLowerCase());
    }).toList();

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Jegyzetek kiválasztása'),
          if (widget.bundleCategory != null) ...[
            const SizedBox(height: 8),
            Text(
              'Csak "${widget.bundleCategory}" kategóriájú jegyzetek',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (widget.bundleTags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Címkék: ${widget.bundleTags.join(', ')}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Keresés',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchText = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filteredNotes.isEmpty
                  ? const Center(
                      child: Text('Nincs elérhető jegyzet'),
                    )
                  : ListView.builder(
                      itemCount: filteredNotes.length,
                      itemBuilder: (context, index) {
                        final doc = filteredNotes[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final title = data['title'] ?? 'Névtelen';
                        final category = data['category'] ?? 'N/A';
                        final tags =
                            (data['tags'] as List?)?.join(', ') ?? 'N/A';

                        return CheckboxListTile(
                          value: _selectedIds.contains(doc.id),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedIds.add(doc.id);
                              } else {
                                _selectedIds.remove(doc.id);
                              }
                            });
                          },
                          title: Text(title),
                          subtitle:
                              Text('Kategória: $category | Címkék: $tags'),
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
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selectedIds.toList()),
          child: Text('Kiválasztás (${_selectedIds.length})'),
        ),
      ],
    );
  }
}
