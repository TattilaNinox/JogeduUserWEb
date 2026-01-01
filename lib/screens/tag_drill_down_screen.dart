import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  // OPTIMALIZÁLT: Limit növelése a kliens oldali szűrés miatt
  final int _currentLimit = 300;
  final ScrollController _breadcrumbScrollController = ScrollController();

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
    _checkPremiumAccess();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollBreadcrumbToEnd());
  }

  @override
  void dispose() {
    _breadcrumbScrollController.dispose();
    super.dispose();
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
      final isAdmin = userType == 'admin' ||
          user.email == 'tattila.ninox@gmail.com' ||
          userData['isAdmin'] == true;
      if (isAdmin) {
        setState(() => _hasPremiumAccess = true);
        return;
      }
      final subscriptionStatus =
          userData['subscriptionStatus'] as String? ?? 'inactive';
      final trialActive = userData['trialActive'] as bool? ?? false;
      setState(() =>
          _hasPremiumAccess = subscriptionStatus == 'active' || trialActive);
    } catch (e) {
      debugPrint('Error checking premium access: $e');
    }
  }

  void _navigateToNextLevel(BuildContext context, String nextTag) {
    final screen = TagDrillDownScreen(
      category: widget.category,
      tagPath: [...widget.tagPath, nextTag],
    );
    if (!kIsWeb && Platform.isIOS) {
      Navigator.push(context, CupertinoPageRoute(builder: (context) => screen));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
    }
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
        title: Text(widget.tagPath.last),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: _buildBreadcrumb(),
          ),
        ),
      ),
      // HIBRID LAZY LOADING REFACTOR
      body: FutureBuilder<List<String>>(
        // 1. Mappák betöltése MetadataService-ből (Gyors, 0 Firestore olvasás)
        future: MetadataService.getSubTagsForPath(
            'Jogász', widget.category, widget.tagPath),
        builder: (context, subTagsSnapshot) {
          final subTags = subTagsSnapshot.data ?? [];
          final bool isLoadingFolders =
              subTagsSnapshot.connectionState == ConnectionState.waiting;

          // 2. Jegyzetek betöltése Firestore-ból (Háttérben)
          // FONTOS: Mindig elindítjuk a lekérdezést, de csak akkor jelenítjük meg,
          // ha vannak "közvetlen" jegyzetek.
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseConfig.firestore
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (!userSnapshot.hasData && isLoadingFolders) {
                return const Center(child: CircularProgressIndicator());
              }

              final userData = userSnapshot.data?.data() ?? {};
              final userType =
                  (userData['userType'] as String? ?? '').toLowerCase();
              final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
              final isAdminBool = userData['isAdmin'] == true;
              final bool isAdmin =
                  userType == 'admin' || isAdminEmail || isAdminBool;
              const String science = 'Jogász';

              // Lekérdezések építése - BŐVEBB LIMITTEL
              Query<Map<String, dynamic>> notesQuery = FirebaseConfig.firestore
                  .collection('notes')
                  .where('science', isEqualTo: science)
                  .where('category', isEqualTo: widget.category)
                  .orderBy('title')
                  .limit(_currentLimit + 1);

              if (isAdmin) {
                notesQuery = notesQuery.where('status',
                    whereIn: const ['Published', 'Public', 'Draft']);
              } else {
                notesQuery = notesQuery
                    .where('status', whereIn: const ['Published', 'Public']);
              }

              Query<Map<String, dynamic>> jogesetQuery = FirebaseConfig
                  .firestore
                  .collection('jogesetek')
                  .where('science', isEqualTo: science)
                  .where('category', isEqualTo: widget.category)
                  .orderBy(FieldPath.documentId)
                  .limit(_currentLimit + 1);

              if (isAdmin) {
                jogesetQuery = jogesetQuery.where('status',
                    whereIn: const ['Published', 'Public', 'Draft']);
              } else {
                jogesetQuery = jogesetQuery
                    .where('status', whereIn: const ['Published', 'Public']);
              }

              Query<Map<String, dynamic>> allomasQuery = FirebaseConfig
                  .firestore
                  .collection('memoriapalota_allomasok')
                  .where('science', isEqualTo: science)
                  .where('category', isEqualTo: widget.category)
                  .orderBy('title')
                  .limit(_currentLimit + 1);

              if (isAdmin) {
                allomasQuery = allomasQuery.where('status',
                    whereIn: const ['Published', 'Public', 'Draft']);
              } else {
                allomasQuery = allomasQuery
                    .where('status', whereIn: const ['Published', 'Public']);
              }

              Query<Map<String, dynamic>>? dialogusQuery;
              if (widget.category == 'Dialogus tags') {
                dialogusQuery = FirebaseConfig.firestore
                    .collection('dialogus_fajlok')
                    .where('science', isEqualTo: science);
                if (widget.tagPath.isNotEmpty) {
                  dialogusQuery = dialogusQuery.where('tags',
                      arrayContains: widget.tagPath.last);
                }
              }

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: notesQuery.snapshots(),
                builder: (context, notesSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: jogesetQuery.snapshots(),
                    builder: (context, jogesetSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: allomasQuery.snapshots(),
                        builder: (context, allomasSnap) {
                          final dStream = dialogusQuery?.snapshots() ??
                              const Stream.empty();
                          return StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
                            stream: dStream,
                            builder: (context, dSnap) {
                              // Adatok összegyűjtése
                              final allDocs = <QueryDocumentSnapshot<
                                  Map<String, dynamic>>>[];
                              if (notesSnap.hasData) {
                                allDocs.addAll(notesSnap.data!.docs.where(
                                    (d) => d.data()['deletedAt'] == null));
                              }
                              if (jogesetSnap.hasData) {
                                allDocs.addAll(jogesetSnap.data!.docs.where(
                                    (d) => d.data()['deletedAt'] == null));
                              }
                              if (allomasSnap.hasData) {
                                allDocs.addAll(allomasSnap.data!.docs.where(
                                    (d) => d.data()['deletedAt'] == null));
                              }
                              if (dSnap.hasData) {
                                allDocs.addAll(dSnap.data!.docs.where(
                                    (d) => d.data()['deletedAt'] == null));
                              }

                              // KLIENS OLDALI SZŰRÉS: "Közvetlen Jegyzetek"
                              final directNotes = allDocs.where((doc) {
                                final data = doc.data();
                                final tags =
                                    (data['tags'] as List<dynamic>? ?? [])
                                        .cast<String>();

                                // 1. Ellenőrizzük, hogy illeszkedik-e a jelenlegi path-ra
                                if (_findTagPathIndex(tags, widget.tagPath) ==
                                    -1) {
                                  return false;
                                }

                                // 2. Ellenőrizzük, hogy VAN-E TOVÁBBI címkéje
                                // Ha a tags hossza > path hossza, akkor van alcímkéje -> Mappába való -> KISZŰRJÜK
                                return tags.length <= widget.tagPath.length;
                              }).toList();

                              // Rendezés
                              directNotes.sort((a, b) {
                                final dataA = a.data();
                                final dataB = b.data();
                                final titleA = (dataA['title'] ??
                                        dataA['name'] ??
                                        dataA['cim'] ??
                                        '')
                                    .toString();
                                final titleB = (dataB['title'] ??
                                        dataB['name'] ??
                                        dataB['cim'] ??
                                        '')
                                    .toString();
                                return StringUtils.naturalCompare(
                                    titleA, titleB);
                              });

                              final List<Widget> widgetsList = [];

                              // 1. MAPPÁK (Színesen)
                              for (int i = 0; i < subTags.length; i++) {
                                final tag = subTags[i];
                                final colorIndex = i % _folderColors.length;
                                widgetsList.add(_buildFolderWidget(
                                    tag,
                                    {
                                      'docs': [],
                                      'hasChildren': true
                                    }, // Metadata-ból jön, tuti van countja
                                    bgColor: _folderColors[colorIndex],
                                    iconColor: _folderIconColors[colorIndex]));
                              }

                              // Elválasztó
                              if (widgetsList.isNotEmpty &&
                                  directNotes.isNotEmpty) {
                                widgetsList.add(const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                                  child: Text('Dokumentumok',
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold)),
                                ));
                              }

                              // 2. KÖZVETLEN JEGYZETEK
                              for (var doc in directNotes) {
                                if (doc.reference.path.contains('jogesetek')) {
                                  widgetsList.add(_buildJogesetWidget(doc));
                                } else {
                                  widgetsList.add(_buildNoteWidget(doc));
                                }
                              }

                              if (widgetsList.isEmpty) {
                                // Ha a mappák még töltődnek, akkor loading
                                if (isLoadingFolders &&
                                    !notesSnap.hasData &&
                                    !allomasSnap.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                return const Center(
                                    child: Text(
                                        'Nincs megjeleníthető tartalom ezen a szinten.'));
                              }

                              // Összesítés (Csak a látható közvetlen jegyzetek száma + mappák)
                              final visibleCount =
                                  subTags.length + directNotes.length;

                              return ListView(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                children: [
                                  if (isLoadingFolders)
                                    const LinearProgressIndicator(),
                                  ...widgetsList,
                                  Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Center(
                                      child: Text(
                                        'Megjelenítve: $visibleCount elem',
                                        textAlign: TextAlign.center,
                                        style:
                                            const TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Megkeresi a tagPath sorrendet a dokumentum saját tags listájában.
  int _findTagPathIndex(List<String> tags, List<String> path) {
    if (path.isEmpty) return 0;
    // Ellenőrizzük, hogy a path PONTOSAN megegyezik a tags elejével
    if (tags.length < path.length) return -1;
    for (int j = 0; j < path.length; j++) {
      if (tags[j] != path[j]) {
        return -1;
      }
    }
    return 0;
  }

  // _addToHierarchy és _getUnifiedList már nem szükségesek a fő rendereléshez,
  // de benne hagyom őket, ha esetleg másra kellenének.

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
