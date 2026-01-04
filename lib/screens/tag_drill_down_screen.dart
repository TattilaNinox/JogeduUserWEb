import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../core/firebase_config.dart';
import '../widgets/note_list_tile.dart';
import '../utils/string_utils.dart';
import '../services/metadata_service.dart';

/// Drill-down navigációs képernyő a címkék hierarchikus böngészéséhez.
///
/// Logikája és szűrései megegyeznek a NoteCardGrid-del (Főoldal).
class TagDrillDownScreen extends StatefulWidget {
  final String category;
  final List<String> tagPath;

  const TagDrillDownScreen({
    super.key,
    required this.category,
    required this.tagPath,
  });

  @override
  State<TagDrillDownScreen> createState() => _TagDrillDownScreenState();
}

class _TagDrillDownScreenState extends State<TagDrillDownScreen> {
  bool _hasPremiumAccess = false;
  bool _isAdmin = false;

  // Infinite scroll és pagination állapot változók
  static const int _pageSize = 50;
  int _currentLimit = _pageSize;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allLoadedDocs = [];
  Map<String, DocumentSnapshot?> _lastDocuments =
      {}; // Kollekciónként az utolsó dokumentum
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _documentsFuture;

  final ScrollController _breadcrumbScrollController = ScrollController();
  final ScrollController _scrollController = ScrollController();

  // Színek a mappáknak (ciklikusan ismétlődnek) - ÉLÉNK SZÍNEK
  final List<Color> _folderColors = [
    const Color(0xFFE3F2FD), // Világoskék
    const Color(0xFFE8F5E9), // Világoszöld
    const Color(0xFFFFF3E0), // Világosnarancs
    const Color(0xFFF3E5F5), // Világoslila
    const Color(0xFFE0F7FA), // Ciánkék
    const Color(0xFFFFF8E1), // Sárga
  ];

  final List<Color> _folderIconColors = [
    const Color(0xFF1976D2), // Kék
    const Color(0xFF388E3C), // Zöld
    const Color(0xFFF57C00), // Narancs
    const Color(0xFF7B1FA2), // Lila
    const Color(0xFF0097A7), // Cián
    const Color(0xFFFBC02D), // Sárga
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Elindítjuk a premium access ellenőrzést, ami után betölti a dokumentumokat
    _checkPremiumAccess();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollBreadcrumbToEnd());
  }

  @override
  void dispose() {
    _breadcrumbScrollController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreDocuments();
      }
    }
  }

  void _scrollBreadcrumbToEnd() {
    if (_breadcrumbScrollController.hasClients) {
      _breadcrumbScrollController.animateTo(
        _breadcrumbScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _checkPremiumAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .get();
      if (!userDoc.exists) return;
      final userData = userDoc.data()!;
      final userType = (userData['userType'] as String? ?? '').toLowerCase();
      final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
      final isAdminBool = userData['isAdmin'] == true;
      final isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;

      setState(() {
        _isAdmin = isAdmin;
        if (isAdmin) {
          _hasPremiumAccess = true;
        } else {
          final subscriptionStatus =
              userData['subscriptionStatus'] as String? ?? 'inactive';
          final trialActive = userData['trialActive'] as bool? ?? false;
          _hasPremiumAccess = subscriptionStatus == 'active' || trialActive;
        }
        // Most, hogy az _isAdmin be van állítva, elindítjuk a dokumentumok betöltését
        _documentsFuture = _loadDocuments(refresh: true);
      });
    } catch (e) {
      debugPrint('Error checking premium access: $e');
    }
  }

  void _navigateToNextLevel(BuildContext context, String nextTag) {
    final screen = TagDrillDownScreen(
      category: widget.category,
      tagPath: [...widget.tagPath, nextTag],
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      Navigator.push(context, CupertinoPageRoute(builder: (context) => screen));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
    }
  }

  /// Betölti az összes kollekció dokumentumait szerver oldali parentTag szűréssel
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadDocuments(
      {bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentLimit = _pageSize;
        _hasMore = true;
        _allLoadedDocs = [];
        _lastDocuments = {};
      });
    }

    const String science = 'Jogász';
    final parentTag = widget.tagPath.isEmpty ? null : widget.tagPath.last;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs = [];

    // Status szűrés admin/nem-admin alapján
    final statusFilter = _isAdmin
        ? const ['Published', 'Public', 'Draft']
        : const ['Published', 'Public'];

    // ÚJ: Típus detektálás a metadata alapján
    // Ha az aktuális tag path csak egy típust tartalmaz, akkor csak azt töltjük be
    String? detectedType;
    try {
      final metadata = await MetadataService.getCategoryTagMapping(science);
      final tagPathToTypes =
          metadata['tagPathToTypes'] as Map<String, Map<String, Set<String>>>?;
      if (tagPathToTypes != null &&
          tagPathToTypes.containsKey(widget.category)) {
        final categoryTypes = tagPathToTypes[widget.category]!;
        final currentPath = widget.tagPath.join('/');
        if (kDebugMode) {
          debugPrint(
              '🔍 TagDrillDown: Looking for path "$currentPath" in tagPathToTypes');
          debugPrint(
              '🔍 TagDrillDown: Available paths: ${categoryTypes.keys.toList()}');
        }
        if (categoryTypes.containsKey(currentPath)) {
          final types = categoryTypes[currentPath]!;
          if (kDebugMode) {
            debugPrint('🔍 TagDrillDown: Found types for path: $types');
          }
          // Ha csak egy típus van ebben a path-ban, akkor arra szűrünk
          if (types.length == 1) {
            detectedType = types.first;
            if (kDebugMode) {
              debugPrint(
                  '✅ TagDrillDown: Detected single type "$detectedType" for path: $currentPath');
            }
          } else {
            if (kDebugMode) {
              debugPrint(
                  '⚠️ TagDrillDown: Multiple types found, no filtering: $types');
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Error detecting type from metadata: $e');
      }
    }

    // FONTOS: Kontextus alapú kollekció szűrés
    // Ha a tagPath-ban van "Memóriaútvonal" (bármilyen számozással), akkor csak memoriapalota_allomasok-ot töltünk
    // Ha a tagPath-ban van "Dialogus" vagy a kategória "Dialogus tags", akkor csak dialogus_fajlok-ot töltünk
    // Egyébként csak notes-t töltünk (a jogesetek mindig betöltődnek)
    final bool isMemoriaContext = widget.tagPath.any((tag) =>
        tag.toLowerCase().contains('memóriaútvonal') ||
        tag.toLowerCase().contains('memoriaútvonal') ||
        tag.toLowerCase().contains('memoriautvonal'));

    // 1. Notes kollekció - CSAK ha NEM memória kontextusban vagyunk
    if (!isMemoriaContext) {
      try {
        Query<Map<String, dynamic>> notesQuery = FirebaseConfig.firestore
            .collection('notes')
            .where('science', isEqualTo: science)
            .where('category', isEqualTo: widget.category)
            .where('status', whereIn: statusFilter);

        // ÚJ: Típus szűrő hozzáadása, ha detektáltunk egy egyedi típust
        if (detectedType != null) {
          notesQuery = notesQuery.where('type', isEqualTo: detectedType);
        }

        // FONTOS: parentTag szűrőt az orderBy ELŐTT kell hozzáadni!
        if (parentTag != null) {
          notesQuery = notesQuery.where('parentTag', isEqualTo: parentTag);
        } else {
          // Ha üres a tagPath, akkor a parentTag null vagy üres string lehet
          notesQuery = notesQuery.where('parentTag', isNull: true);
        }

        // orderBy és limit a végén
        notesQuery = notesQuery.orderBy('title').limit(_currentLimit);

        // Pagination: ha van lastDocument, használjuk startAfter-t
        if (_lastDocuments['notes'] != null && !refresh) {
          notesQuery = notesQuery.startAfterDocument(_lastDocuments['notes']!);
        }

        final notesSnapshot = await notesQuery.get();
        final notesDocs = notesSnapshot.docs
            .where((d) => d.data()['deletedAt'] == null)
            .toList();
        allDocs.addAll(notesDocs);

        if (notesSnapshot.docs.length < _currentLimit) {
          _lastDocuments['notes'] = null; // Nincs több adat
        } else if (notesDocs.isNotEmpty) {
          _lastDocuments['notes'] = notesDocs.last;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error loading notes: $e');
        }
      }
    }

    // 2. Jogesetek kollekció
    try {
      Query<Map<String, dynamic>> jogesetQuery = FirebaseConfig.firestore
          .collection('jogesetek')
          .where('science', isEqualTo: science)
          .where('category', isEqualTo: widget.category)
          .where('status', whereIn: statusFilter);

      // FONTOS: parentTag szűrőt az orderBy ELŐTT kell hozzáadni!
      if (parentTag != null) {
        jogesetQuery = jogesetQuery.where('parentTag', isEqualTo: parentTag);
      } else {
        jogesetQuery = jogesetQuery.where('parentTag', isNull: true);
      }

      // orderBy és limit a végén
      jogesetQuery =
          jogesetQuery.orderBy(FieldPath.documentId).limit(_currentLimit);

      if (_lastDocuments['jogesetek'] != null && !refresh) {
        jogesetQuery =
            jogesetQuery.startAfterDocument(_lastDocuments['jogesetek']!);
      }

      final jogesetSnapshot = await jogesetQuery.get();
      final jogesetDocs = jogesetSnapshot.docs
          .where((d) => d.data()['deletedAt'] == null)
          .toList();
      allDocs.addAll(jogesetDocs);

      if (jogesetSnapshot.docs.length < _currentLimit) {
        _lastDocuments['jogesetek'] = null;
      } else if (jogesetDocs.isNotEmpty) {
        _lastDocuments['jogesetek'] = jogesetDocs.last;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading jogesetek: $e');
      }
    }

    // 3. Memoriapalota állomások kollekció - CSAK ha memória kontextusban vagyunk
    if (isMemoriaContext) {
      try {
        Query<Map<String, dynamic>> allomasQuery = FirebaseConfig.firestore
            .collection('memoriapalota_allomasok')
            .where('science', isEqualTo: science)
            .where('category', isEqualTo: widget.category)
            .where('status', whereIn: statusFilter);

        // FONTOS: parentTag szűrőt az orderBy ELŐTT kell hozzáadni!
        if (parentTag != null) {
          allomasQuery = allomasQuery.where('parentTag', isEqualTo: parentTag);
        } else {
          allomasQuery = allomasQuery.where('parentTag', isNull: true);
        }

        // orderBy és limit a végén
        allomasQuery = allomasQuery.orderBy('title').limit(_currentLimit);

        if (_lastDocuments['memoriapalota_allomasok'] != null && !refresh) {
          allomasQuery = allomasQuery
              .startAfterDocument(_lastDocuments['memoriapalota_allomasok']!);
        }

        final allomasSnapshot = await allomasQuery.get();
        final allomasDocs = allomasSnapshot.docs
            .where((d) => d.data()['deletedAt'] == null)
            .toList();
        allDocs.addAll(allomasDocs);

        if (allomasSnapshot.docs.length < _currentLimit) {
          _lastDocuments['memoriapalota_allomasok'] = null;
        } else if (allomasDocs.isNotEmpty) {
          _lastDocuments['memoriapalota_allomasok'] = allomasDocs.last;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error loading memoriapalota_allomasok: $e');
        }
      }
    }

    // 4. Dialogus fájlok kollekció (csak ha Dialogus tags kategória)
    if (widget.category == 'Dialogus tags') {
      try {
        Query<Map<String, dynamic>> dialogusQuery = FirebaseConfig.firestore
            .collection('dialogus_fajlok')
            .where('science', isEqualTo: science)
            .where('status', whereIn: statusFilter);

        // FONTOS: parentTag szűrőt az orderBy ELŐTT kell hozzáadni!
        if (parentTag != null) {
          dialogusQuery =
              dialogusQuery.where('parentTag', isEqualTo: parentTag);
        } else {
          dialogusQuery = dialogusQuery.where('parentTag', isNull: true);
        }

        // orderBy és limit a végén
        dialogusQuery = dialogusQuery.orderBy('title').limit(_currentLimit);

        if (_lastDocuments['dialogus_fajlok'] != null && !refresh) {
          dialogusQuery = dialogusQuery
              .startAfterDocument(_lastDocuments['dialogus_fajlok']!);
        }

        final dialogusSnapshot = await dialogusQuery.get();
        final dialogusDocs = dialogusSnapshot.docs
            .where((d) => d.data()['deletedAt'] == null)
            .toList();
        allDocs.addAll(dialogusDocs);

        if (dialogusSnapshot.docs.length < _currentLimit) {
          _lastDocuments['dialogus_fajlok'] = null;
        } else if (dialogusDocs.isNotEmpty) {
          _lastDocuments['dialogus_fajlok'] = dialogusDocs.last;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error loading dialogus_fajlok: $e');
        }
      }
    }

    // 5. Deck Collections kollekció - pakli gyűjtemények
    if (!isMemoriaContext) {
      try {
        Query<Map<String, dynamic>> collectionQuery = FirebaseConfig.firestore
            .collection('deck_collections')
            .where('science', isEqualTo: science)
            .where('category', isEqualTo: widget.category);

        // FONTOS: parentTag szűrőt az orderBy ELŐTT kell hozzáadni!
        if (parentTag != null) {
          collectionQuery =
              collectionQuery.where('parentTag', isEqualTo: parentTag);
        } else {
          collectionQuery = collectionQuery.where('parentTag', isNull: true);
        }

        // Status szűrés szerver oldalon (Index: science + category + status + parentTag + title)
        collectionQuery =
            collectionQuery.where('status', whereIn: statusFilter);

        // orderBy és limit a végén
        collectionQuery = collectionQuery.orderBy('title').limit(_currentLimit);

        if (_lastDocuments['deck_collections'] != null && !refresh) {
          collectionQuery = collectionQuery
              .startAfterDocument(_lastDocuments['deck_collections']!);
        }

        final collectionSnapshot = await collectionQuery.get();

        final collectionDocs = collectionSnapshot.docs;
        allDocs.addAll(collectionDocs);

        if (collectionSnapshot.docs.length < _currentLimit) {
          _lastDocuments['deck_collections'] = null;
        } else if (collectionDocs.isNotEmpty) {
          _lastDocuments['deck_collections'] = collectionDocs.last;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error loading deck_collections: $e');
        }
      }
    }

    // Rendezés cím szerint
    allDocs.sort((a, b) {
      final dataA = a.data();
      final dataB = b.data();
      final titleA =
          (dataA['title'] ?? dataA['name'] ?? dataA['cim'] ?? '').toString();
      final titleB =
          (dataB['title'] ?? dataB['name'] ?? dataB['cim'] ?? '').toString();
      return StringUtils.naturalCompare(titleA, titleB);
    });

    if (refresh) {
      _allLoadedDocs = allDocs;
    } else {
      _allLoadedDocs.addAll(allDocs);
    }

    // Ellenőrizzük, hogy van-e még betöltendő adat
    final hasMoreNotes = _lastDocuments['notes'] != null;
    final hasMoreJogeset = _lastDocuments['jogesetek'] != null;
    final hasMoreAllomas = _lastDocuments['memoriapalota_allomasok'] != null;
    final hasMoreDialogus = widget.category == 'Dialogus tags'
        ? _lastDocuments['dialogus_fajlok'] != null
        : false;
    final hasMoreCollections = _lastDocuments['deck_collections'] != null;

    setState(() {
      _hasMore = hasMoreNotes ||
          hasMoreJogeset ||
          hasMoreAllomas ||
          hasMoreDialogus ||
          hasMoreCollections;
      _isLoadingMore = false;
    });

    return _allLoadedDocs;
  }

  /// Betölti a következő oldalt infinite scroll-hoz
  Future<void> _loadMoreDocuments() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    await _loadDocuments(refresh: false);
    // Frissítjük a future-t, hogy a FutureBuilder újraépüljön
    setState(() {
      _documentsFuture = Future.value(_allLoadedDocs);
    });
  }

  /// Pull-to-refresh kezelő
  Future<void> _refreshDocuments() async {
    setState(() {
      _documentsFuture = _loadDocuments(refresh: true);
    });
    await _documentsFuture;
  }

  Widget _buildBreadcrumb() {
    final items = <Widget>[];
    items.add(TextButton(
      onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
      child: const Text('Főoldal', style: TextStyle(fontSize: 14)),
    ));
    items.add(const Icon(Icons.chevron_right, size: 16, color: Colors.grey));
    items.add(TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(widget.category, style: const TextStyle(fontSize: 14)),
    ));

    for (int i = 0; i < widget.tagPath.length; i++) {
      items.add(const Icon(Icons.chevron_right, size: 16, color: Colors.grey));
      final isLast = i == widget.tagPath.length - 1;
      items.add(isLast
          ? Text(widget.tagPath[i],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))
          : TextButton(
              onPressed: () {
                final targetDepth = i + 1;
                final popCount = widget.tagPath.length - targetDepth;
                for (int j = 0; j < popCount; j++) {
                  Navigator.pop(context);
                }
              },
              child:
                  Text(widget.tagPath[i], style: const TextStyle(fontSize: 14)),
            ));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _breadcrumbScrollController,
      child: Row(children: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
          body: Center(child: Text('Kérjük, jelentkezzen be.')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
            widget.tagPath.isEmpty ? widget.category : widget.tagPath.last),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: _buildBreadcrumb(),
          ),
        ),
      ),
      body: FutureBuilder<List<String>>(
        // Mappák betöltése MetadataService-ből
        future: MetadataService.getSubTagsForPath(
            'Jogász', widget.category, widget.tagPath),
        builder: (context, subTagsSnapshot) {
          final subTags = subTagsSnapshot.data ?? [];
          final bool isLoadingFolders =
              subTagsSnapshot.connectionState == ConnectionState.waiting;

          // Dokumentumok betöltése FutureBuilder-rel
          return FutureBuilder<
              List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _documentsFuture,
            builder: (context, docsSnapshot) {
              if (docsSnapshot.connectionState == ConnectionState.waiting &&
                  _allLoadedDocs.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              final documents = docsSnapshot.data ?? _allLoadedDocs;
              final List<Widget> widgetsList = [];

              // 1. MAPPÁK (Színesen)
              for (int i = 0; i < subTags.length; i++) {
                final tag = subTags[i];
                final colorIndex = i % _folderColors.length;
                widgetsList.add(_buildFolderWidget(
                    tag, {'docs': [], 'hasChildren': true},
                    bgColor: _folderColors[colorIndex],
                    iconColor: _folderIconColors[colorIndex]));
              }

              // Elválasztó
              if (widgetsList.isNotEmpty && documents.isNotEmpty) {
                widgetsList.add(const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text('Dokumentumok',
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ));
              }

              // 2. DOKUMENTUMOK
              for (var doc in documents) {
                if (doc.reference.path.contains('jogesetek')) {
                  widgetsList.add(_buildJogesetWidget(doc));
                } else if (doc.reference.path.contains('deck_collections')) {
                  widgetsList.add(_buildDeckCollectionWidget(doc));
                } else {
                  widgetsList.add(_buildNoteWidget(doc));
                }
              }

              // Loading indicator infinite scroll-hoz
              if (_isLoadingMore) {
                widgetsList.add(const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                ));
              }

              // "Nincs több adat" üzenet
              if (!_hasMore && documents.isNotEmpty) {
                widgetsList.add(const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'Összes dokumentum betöltve',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                ));
              }

              if (widgetsList.isEmpty) {
                if (isLoadingFolders) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const Center(
                    child:
                        Text('Nincs megjeleníthető tartalom ezen a szinten.'));
              }

              // Összesítés
              final visibleCount = subTags.length + documents.length;

              return RefreshIndicator(
                onRefresh: _refreshDocuments,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      _onScroll();
                    }
                    return false;
                  },
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (isLoadingFolders) const LinearProgressIndicator(),
                      ...widgetsList,
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'Megjelenítve: $visibleCount elem',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNoteWidget(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final isMP = doc.reference.path.contains('memoriapalota_allomasok');
    final isDialogus = doc.reference.path.contains('dialogus_fajlok');

    final title =
        (data['title'] ?? data['name'] ?? data['cim'] ?? 'Névtelen').toString();
    final type = isMP
        ? 'memoriapalota_allomasok'
        : (isDialogus
            ? 'dialogus_fajlok'
            : (data['type'] as String? ?? 'standard'));
    final isFree = (data['isFree'] == true) ||
        (data['is_free'] == true) ||
        (data['isFree'] == 1) ||
        (data['is_free'] == 1);
    final isLocked = !isFree && !_hasPremiumAccess;

    return NoteListTile(
      id: doc.id,
      title: title,
      type: type,
      hasDoc: (data['docxUrl'] ?? '').toString().isNotEmpty,
      hasAudio: (data['audioUrl'] ?? '').toString().isNotEmpty,
      audioUrl: (data['audioUrl'] ?? '').toString(),
      hasVideo: (data['videoUrl'] ?? '').toString().isNotEmpty,
      deckCount:
          type == 'deck' ? (data['flashcards'] as List? ?? []).length : null,
      isLocked: isLocked,
      customFromUrl: '/notes',
    );
  }

  Widget _buildJogesetWidget(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = (data['title'] ?? 'Jogeset').toString();

    // Kiszámoljuk a jogesetek számát a tömbből
    final jogesetekList = data['jogesetek'] as List? ?? [];
    final int count = jogesetekList.length;

    return NoteListTile(
      id: doc.id,
      title: title,
      type: 'jogeset',
      hasDoc: false,
      hasAudio: false,
      hasVideo: false,
      isLocked: !_hasPremiumAccess && !(data['isFree'] == true),
      jogesetCount: count,
      category: widget.category,
      customFromUrl: '/notes',
    );
  }

  Widget _buildDeckCollectionWidget(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = (data['title'] ?? 'Gyűjtemény').toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          context.push('/deck-collections/${doc.id}');
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(
                Icons.style,
                color: Color(0xFF1E3A8A),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderWidget(String tag, Map<String, dynamic> data,
      {Color? bgColor, Color? iconColor}) {
    // Betöltött dokumentumok száma (fallback)
    final loadedCount = (data['docs'] as List).length;

    // Hierarchikus path építése a jelenlegi címke útvonalból
    final tagPath = [...widget.tagPath, tag];
    final hierarchicalPath = tagPath.join('/');

    return Card(
      color: bgColor ?? Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        onTap: () => _navigateToNextLevel(context, tag),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(data['hasChildren'] ? Icons.folder : Icons.label,
                  color: iconColor ?? const Color(0xFF3366CC)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(tag,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500))),
              FutureBuilder<int>(
                future: _getHierarchicalCount(hierarchicalPath),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? loadedCount;
                  return Text('$count',
                      style: const TextStyle(color: Colors.grey, fontSize: 14));
                },
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// Hierarchikus count lekérése a metadata-ból
  Future<int> _getHierarchicalCount(String hierarchicalPath) async {
    try {
      final metadata = await MetadataService.getCategoryTagMapping('Jogász');
      final hierarchicalCounts =
          metadata['hierarchicalCounts'] as Map<String, Map<String, int>>?;

      if (hierarchicalCounts != null &&
          hierarchicalCounts.containsKey(widget.category)) {
        final categoryCounts = hierarchicalCounts[widget.category]!;
        // Ha van cache-elt adatunk, azt azonnal visszaadhatjuk (ha lenne ilyen mechanizmus)
        return categoryCounts[hierarchicalPath] ?? 0;
      }

      return 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Hiba a hierarchikus count lekérésekor: $e');
      }
      return 0;
    }
  }
}
