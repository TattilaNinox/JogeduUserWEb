import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../core/firebase_config.dart';
import '../widgets/filters.dart';

/// Dokumentum kiválasztó képernyő (teljes képernyős, mobil-barát).
///
/// Logikája és szűrései megegyeznek a NoteCardGrid-del (Főoldal).
/// A struktúra hierarchikus (mappák), ExpansionTile-ok használatával.
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
  final TextEditingController _searchController = TextEditingController();

  // Szűrő állapotok (Összhangban a NoteCardGrid-del)
  String? _selectedCategory;
  String? _selectedStatus;
  String? _selectedTag;
  String? _selectedType;
  final String _selectedScience = 'Jogász'; // Fix
  final List<String> _sciences = const ['Jogász'];

  // Cache a streameknek (NoteCardGrid logika)
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>> _streamCache =
      {};

  Stream<QuerySnapshot<Map<String, dynamic>>> _cachedSnapshotsStream(
    String cacheKey,
    Query<Map<String, dynamic>> query,
  ) {
    return _streamCache.putIfAbsent(cacheKey, () => query.snapshots());
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectAll = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        for (var doc in docs) {
          _selectedIds.add(doc.id);
        }
      } else {
        _selectedIds.clear();
      }
    });
  }

  Future<void> _addSelectedDocuments() async {
    if (_selectedIds.isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String bundleId = widget.bundleId;
      final batch = FirebaseConfig.firestore.batch();

      if (bundleId == 'create') {
        final newBundleRef = FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .doc();

        batch.set(newBundleRef, {
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
        bundleId = newBundleRef.id;
      } else {
        final bundleRef = FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .doc(bundleId);

        final doc = await bundleRef.get();
        if (!doc.exists) return;

        final data = doc.data()!;
        final noteIds = List<String>.from(data['noteIds'] ?? []);
        final allomasIds = List<String>.from(data['allomasIds'] ?? []);
        final dialogusIds = List<String>.from(data['dialogusIds'] ?? []);

        for (final id in _selectedIds) {
          if (widget.documentType == 'notes') {
            if (!noteIds.contains(id)) noteIds.add(id);
          } else if (widget.documentType == 'allomasok') {
            if (!allomasIds.contains(id)) allomasIds.add(id);
          } else if (widget.documentType == 'dialogus') {
            if (!dialogusIds.contains(id)) dialogusIds.add(id);
          }
        }

        batch.update(bundleRef, {
          'noteIds': noteIds,
          'allomasIds': allomasIds,
          'dialogusIds': dialogusIds,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${_selectedIds.length} dokumentum hozzáadva!')),
        );
        context.go('/my-bundles/edit/$bundleId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      return const Scaffold(
          body: Center(child: Text('Kérjük, jelentkezzen be.')));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData)
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));

        final userData = userSnapshot.data?.data() ?? {};
        final userType = (userData['userType'] as String? ?? '').toLowerCase();
        final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
        final isAdminBool = userData['isAdmin'] == true;
        final bool isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;

        // --- Lekérdezés építése (NoteCardGrid logika szinkron) ---

        // 1. NOTES
        Query<Map<String, dynamic>> notesQuery = FirebaseConfig.firestore
            .collection('notes')
            .where('science', isEqualTo: _selectedScience);

        if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
          notesQuery = notesQuery.where('status', isEqualTo: _selectedStatus);
        } else {
          notesQuery = isAdmin
              ? notesQuery.where('status', whereIn: ['Published', 'Draft'])
              : notesQuery.where('status', isEqualTo: 'Published');
        }

        if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
          notesQuery =
              notesQuery.where('category', isEqualTo: _selectedCategory);
        }
        if (_selectedTag != null && _selectedTag!.isNotEmpty) {
          notesQuery = notesQuery.where('tags', arrayContains: _selectedTag);
        }
        if (_selectedType != null && _selectedType!.isNotEmpty) {
          notesQuery = notesQuery.where('type', isEqualTo: _selectedType);
        }

        // 2. ALLOMASOK
        Query<Map<String, dynamic>>? allomasQuery;
        if (widget.documentType == 'allomasok') {
          allomasQuery = FirebaseConfig.firestore
              .collection('memoriapalota_allomasok')
              .where('science', isEqualTo: _selectedScience);

          if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
            allomasQuery =
                allomasQuery.where('category', isEqualTo: _selectedCategory);
          }
          if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
            allomasQuery =
                allomasQuery.where('status', isEqualTo: _selectedStatus);
          } else {
            allomasQuery = isAdmin
                ? allomasQuery.where('status', whereIn: ['Published', 'Draft'])
                : allomasQuery.where('status', isEqualTo: 'Published');
          }
          if (_selectedTag != null && _selectedTag!.isNotEmpty) {
            allomasQuery =
                allomasQuery.where('tags', arrayContains: _selectedTag);
          }
        }

        // 3. DIALOGUS
        Query<Map<String, dynamic>>? dialogusQuery;
        if (widget.documentType == 'dialogus') {
          dialogusQuery = FirebaseConfig.firestore
              .collection('dialogus_fajlok')
              .where('science', isEqualTo: _selectedScience);

          if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
            dialogusQuery =
                dialogusQuery.where('status', isEqualTo: _selectedStatus);
          } else {
            dialogusQuery = isAdmin
                ? dialogusQuery.where('status', whereIn: ['Published', 'Draft'])
                : dialogusQuery.where('status', isEqualTo: 'Published');
          }
          if (_selectedTag != null && _selectedTag!.isNotEmpty) {
            dialogusQuery =
                dialogusQuery.where('tags', arrayContains: _selectedTag);
          }
        }

        // Stream kulcsok a cache-eléshez
        final notesKey =
            'notes|admin=$isAdmin|s=$_selectedScience|st=$_selectedStatus|c=$_selectedCategory|t=$_selectedTag|type=$_selectedType';
        final allomasKey =
            'allomas|admin=$isAdmin|s=$_selectedScience|st=$_selectedStatus|c=$_selectedCategory|t=$_selectedTag';
        final dialogusKey =
            'dialogus|admin=$isAdmin|s=$_selectedScience|st=$_selectedStatus|t=$_selectedTag';

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.documentType == 'notes'
              ? _cachedSnapshotsStream(notesKey, notesQuery)
              : const Stream.empty(),
          builder: (context, notesSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: widget.documentType == 'allomasok' && allomasQuery != null
                  ? _cachedSnapshotsStream(allomasKey, allomasQuery)
                  : const Stream.empty(),
              builder: (context, mpSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      widget.documentType == 'dialogus' && dialogusQuery != null
                          ? _cachedSnapshotsStream(dialogusKey, dialogusQuery)
                          : const Stream.empty(),
                  builder: (context, dSnap) {
                    // Adatok összefésülése és szűrése (NoteCardGrid logika verbatim)
                    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs =
                        [];

                    if (widget.documentType == 'notes' && notesSnap.hasData) {
                      allDocs.addAll(notesSnap.data!.docs
                          .where((d) => d.data()['deletedAt'] == null));
                    } else if (widget.documentType == 'allomasok' &&
                        mpSnap.hasData) {
                      allDocs.addAll(mpSnap.data!.docs);
                    } else if (widget.documentType == 'dialogus' &&
                        dSnap.hasData) {
                      allDocs.addAll(dSnap.data!.docs.where((d) {
                        final audioUrl = d.data()['audioUrl'] as String?;
                        return audioUrl != null && audioUrl.isNotEmpty;
                      }));
                    }

                    // Keresőszöveg szerinti szűrés
                    final filteredDocs = allDocs.where((d) {
                      final data = d.data();
                      final title = (data['title'] ??
                              data['name'] ??
                              data['utvonalNev'] ??
                              data['cim'] ??
                              '')
                          .toString()
                          .toLowerCase();
                      final category =
                          (data['category'] ?? '').toString().toLowerCase();
                      final search = _searchText.toLowerCase();
                      return title.contains(search) ||
                          category.contains(search);
                    }).toList();

                    // Hierarchikus csoportosítás (NoteCardGrid-hez hasonlóan)
                    final Map<String,
                            List<QueryDocumentSnapshot<Map<String, dynamic>>>>
                        hierarchical = {};
                    for (var doc in filteredDocs) {
                      final isDialogus =
                          doc.reference.path.contains('dialogus_fajlok');
                      final category = isDialogus
                          ? 'Dialogus tags'
                          : (doc.data()['category'] as String? ?? 'Egyéb');
                      hierarchical.putIfAbsent(category, () => []).add(doc);
                    }

                    // Kategóriák és címkék kinyerése a szűrőkhöz (NoteCardGrid nem így csinálja, de mi itt kinyerjük a dinamizmushoz)
                    final availableCats = hierarchical.keys.toList()..sort();
                    final Set<String> availableTags = {};
                    for (var doc in allDocs) {
                      final tags = doc.data()['tags'] as List<dynamic>?;
                      if (tags != null)
                        availableTags.addAll(tags.cast<String>());
                    }

                    return Scaffold(
                      appBar: AppBar(
                        title: Text(widget.documentType == 'notes'
                            ? 'Jegyzetek kiválasztása'
                            : (widget.documentType == 'allomasok'
                                ? 'Állomások kiválasztása'
                                : 'Dialógusok kiválasztása')),
                        leading: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () =>
                              context.go('/my-bundles/edit/${widget.bundleId}'),
                        ),
                      ),
                      body: Column(
                        children: [
                          // Szűrők
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            color: Colors.white,
                            child: Filters(
                              categories: availableCats,
                              sciences: _sciences,
                              selectedCategory: _selectedCategory,
                              selectedScience: _selectedScience,
                              selectedStatus: _selectedStatus,
                              selectedTag: _selectedTag,
                              selectedType: _selectedType,
                              vertical: MediaQuery.of(context).size.width < 600,
                              showStatus: isAdmin,
                              showType: widget.documentType == 'notes',
                              tags: availableTags.toList()..sort(),
                              onCategoryChanged: (v) =>
                                  setState(() => _selectedCategory = v),
                              onScienceChanged: (v) {},
                              onStatusChanged: (v) =>
                                  setState(() => _selectedStatus = v),
                              onTagChanged: (v) =>
                                  setState(() => _selectedTag = v),
                              onTypeChanged: (v) =>
                                  setState(() => _selectedType = v),
                              onClearFilters: () => setState(() {
                                _selectedCategory = null;
                                _selectedStatus = null;
                                _selectedTag = null;
                                _selectedType = null;
                                _searchController.clear();
                                _searchText = '';
                              }),
                            ),
                          ),

                          // Kereső
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Keresés...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchText.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchText = '');
                                        })
                                    : null,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                              ),
                              onChanged: (v) => setState(() => _searchText = v),
                            ),
                          ),

                          // Mind kiválasztása vezérlő
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            color: Colors.grey.shade50,
                            child: Row(
                              children: [
                                Checkbox(
                                    value: _selectAll,
                                    onChanged: (_) =>
                                        _toggleSelectAll(filteredDocs)),
                                Text(
                                    'Mind kiválasztása (${filteredDocs.length})',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),

                          // Hierarchikus lista (Folders)
                          Expanded(
                            child: filteredDocs.isEmpty
                                ? const Center(child: Text('Nincs találat.'))
                                : ListView(
                                    children: hierarchical.entries.map((entry) {
                                      final category = entry.key;
                                      final docs = entry.value;
                                      docs.sort((a, b) {
                                        final titleA = (a.data()['title'] ??
                                                a.data()['name'] ??
                                                a.data()['cim'] ??
                                                '')
                                            .toString();
                                        final titleB = (b.data()['title'] ??
                                                b.data()['name'] ??
                                                b.data()['cim'] ??
                                                '')
                                            .toString();
                                        return titleA.compareTo(titleB);
                                      });

                                      return ExpansionTile(
                                        leading: const Icon(Icons.folder,
                                            color: Color(0xFF1976D2)),
                                        title: Text(
                                            '$category (${docs.length})',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        initiallyExpanded:
                                            true, // Könnyebb használat érdekében alapból nyitva
                                        children: docs.map((doc) {
                                          final data = doc.data();
                                          final title = (data['title'] ??
                                                  data['name'] ??
                                                  data['cim'] ??
                                                  'Névtelen')
                                              .toString();
                                          final isSelected =
                                              _selectedIds.contains(doc.id);

                                          return CheckboxListTile(
                                            value: isSelected,
                                            onChanged: (_) =>
                                                _toggleSelection(doc.id),
                                            title: Text(title),
                                            secondary: Icon(_getIcon(data),
                                                color: Theme.of(context)
                                                    .primaryColor),
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                          );
                                        }).toList(),
                                      );
                                    }).toList(),
                                  ),
                          ),

                          // Akció gomb
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, -2))
                              ],
                            ),
                            child: SafeArea(
                              child: SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: _selectedIds.isEmpty
                                      ? null
                                      : _addSelectedDocuments,
                                  icon: const Icon(Icons.check),
                                  label: Text(
                                      'Hozzáadás (${_selectedIds.length})'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
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
}
