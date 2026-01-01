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
  // OPTIMALIZÁLT: Limit csökkentése a költséghatékonyság érdekében
  final int _currentLimit = 100;
  final ScrollController _breadcrumbScrollController = ScrollController();

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
      // LAZY LOADING: Először ellenőrizzük a metadata-ból, vannak-e alcímkék
      // Ha VANNAK alcímkék → Csak címke kártyákat mutatunk (0 Firestore olvasás!)
      // Ha NINCSENEK alcímkék → Betöltjük a dokumentumokat
      body: FutureBuilder<Map<String, int>>(
        future: MetadataService.getSubTagsForPath(
            'Jogász', widget.category, widget.tagPath),
        builder: (context, subTagsSnapshot) {
          if (subTagsSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final subTags = subTagsSnapshot.data ?? {};
          final hasSubTags = subTags.isNotEmpty;

          if (kDebugMode) {
            debugPrint(
                '🔍 TagDrillDownScreen: tagPath=${widget.tagPath}, hasSubTags=$hasSubTags, subTags=$subTags');
          }

          // Ha VANNAK alcímkék → Csak címke kártyákat mutatunk
          if (hasSubTags) {
            return _buildSubTagsView(subTags);
          }

          // Ha NINCSENEK alcímkék → Betöltjük a dokumentumokat
          return _buildDocumentsView();
        },
      ),
    );
  }

  /// LAZY LOADING: Alcímke kártyák megjelenítése metadata-ból
  /// 0 Firestore olvasás!
  Widget _buildSubTagsView(Map<String, int> subTags) {
    // Rendezés ABC sorrendben
    final sortedTags = subTags.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ...sortedTags.map((entry) => _buildSubTagCard(entry.key, entry.value)),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Text(
              'Címkék: ${sortedTags.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  /// Alcímke kártya UI (hasonló a CategoryTagsScreen-hez)
  Widget _buildSubTagCard(String tagName, int count) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.folder_outlined, color: Colors.blue),
        title: Text(tagName),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TagDrillDownScreen(
                category: widget.category,
                tagPath: [...widget.tagPath, tagName],
              ),
            ),
          );
        },
      ),
    );
  }

  /// LAZY LOADING: Dokumentumok betöltése (leaf szint, nincs több alcímke)
  Widget _buildDocumentsView() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Kérjük, jelentkezzen be.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = userSnapshot.data?.data() ?? {};
        final userType = (userData['userType'] as String? ?? '').toLowerCase();
        final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
        final isAdminBool = userData['isAdmin'] == true;
        final bool isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;
        const String science = 'Jogász';

        // Lekérdezések építése - CSAK a pontos tagPath-ra szűrve
        Query<Map<String, dynamic>> notesQuery = FirebaseConfig.firestore
            .collection('notes')
            .where('science', isEqualTo: science)
            .where('category', isEqualTo: widget.category);

        // Szűrés a tagPath utolsó elemére
        if (widget.tagPath.isNotEmpty) {
          notesQuery =
              notesQuery.where('tags', arrayContains: widget.tagPath.last);
        }

        notesQuery = notesQuery.orderBy('title').limit(_currentLimit + 1);

        if (isAdmin) {
          notesQuery = notesQuery
              .where('status', whereIn: const ['Published', 'Public', 'Draft']);
        } else {
          notesQuery = notesQuery
              .where('status', whereIn: const ['Published', 'Public']);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: notesQuery.snapshots(),
          builder: (context, notesSnap) {
            if (notesSnap.hasError) {
              return Center(child: Text('Hiba: ${notesSnap.error}'));
            }
            if (!notesSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // Szűrés: csak azok a dokumentumok, ahol a tags PONTOSAN egyezik a tagPath-tal
            final allDocs = notesSnap.data!.docs
                .where((d) => d.data()['deletedAt'] == null)
                .where((d) {
              final tags =
                  (d.data()['tags'] as List<dynamic>? ?? []).cast<String>();
              // A tags-nak PONTOSAN meg kell egyeznie a tagPath-tal
              if (tags.length != widget.tagPath.length) return false;
              for (int i = 0; i < widget.tagPath.length; i++) {
                if (i >= tags.length || tags[i] != widget.tagPath[i]) {
                  return false;
                }
              }
              return true;
            }).toList();

            if (allDocs.isEmpty) {
              return const Center(
                  child: Text('Nincs megjeleníthető tartalom ezen a szinten.'));
            }

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ...allDocs.map((doc) => _buildNoteWidget(doc)),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'Összesen: ${allDocs.length} dokumentum',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _buildHierarchy(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? jogesetDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? dialogusDocs,
    bool isAdmin,
  ) {
    final hierarchy = <String, dynamic>{};
    final direct = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    // Standard dokumentumok (notes, allomasok, jogesetek)
    for (var doc in docs) {
      final data = doc.data();
      final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();

      final matchIndex = _findTagPathIndex(tags, widget.tagPath);
      if (matchIndex == -1) continue;

      final effectiveDepth = matchIndex + widget.tagPath.length;

      if (tags.length > effectiveDepth) {
        final nextTag = tags[effectiveDepth];
        _addToHierarchy(
            hierarchy, nextTag, doc, tags.length > effectiveDepth + 1);
      } else {
        direct.add(doc);
      }
    }

    // Dialógusok
    if (widget.category == 'Dialogus tags' && dialogusDocs != null) {
      for (var doc in dialogusDocs) {
        if (doc.data()['deletedAt'] != null) continue;
        final data = doc.data();
        final status = data['status'] as String? ?? 'Draft';
        if (!isAdmin && status != 'Published') continue;
        final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();
        // Dialógusoknál is csak a valódi címkéket használjuk
        final effectiveTags = tags;

        final matchIndex = _findTagPathIndex(effectiveTags, widget.tagPath);

        // Ha üres a keresési út, minden dialógust mutatunk, ami ide tartozik
        if (widget.tagPath.isEmpty) {
          if (tags.isNotEmpty) {
            _addToHierarchy(hierarchy, tags[0], doc, tags.length > 1);
          } else {
            direct.add(doc);
          }
          continue;
        }

        if (matchIndex == -1) continue;

        final effectiveDepth = matchIndex + widget.tagPath.length;

        if (effectiveTags.length > effectiveDepth) {
          final nextTag = effectiveTags[effectiveDepth];
          _addToHierarchy(hierarchy, nextTag, doc,
              effectiveTags.length > effectiveDepth + 1);
        } else {
          direct.add(doc);
        }
      }
    }

    if (direct.isNotEmpty) hierarchy['_direct'] = direct;
    return hierarchy;
  }

  /// Megkeresi a tagPath sorrendet a dokumentum saját tags listájában.
  /// JAVÍTVA: Csak a tags elejétől (0. pozíciótól) egyeztet!
  /// Visszatér 0-val ha egyezik, vagy -1-gyel ha nem.
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

  void _addToHierarchy(Map<String, dynamic> hierarchy, String tag,
      QueryDocumentSnapshot doc, bool hasChildren) {
    if (!hierarchy.containsKey(tag)) {
      hierarchy[tag] = {
        'docs': <QueryDocumentSnapshot>[],
        'hasChildren': false
      };
    }
    hierarchy[tag]['docs'].add(doc);
    if (hasChildren) hierarchy[tag]['hasChildren'] = true;
  }

  List<dynamic> _getUnifiedList(Map<String, dynamic> hierarchy) {
    // Egységes lista létrehozása a mappákból és a közvetlen dokumentumokból
    final List<dynamic> unifiedList = [];

    if (hierarchy.containsKey('_direct')) {
      unifiedList.addAll(hierarchy['_direct']);
    }

    final folders =
        hierarchy.entries.where((e) => !e.key.startsWith('_')).toList();
    unifiedList.addAll(folders);

    unifiedList.sort((a, b) {
      String titleA;
      if (a is MapEntry<String, dynamic>) {
        titleA = a.key;
      } else {
        final docA = a as QueryDocumentSnapshot<Map<String, dynamic>>;
        final dataA = docA.data();
        final isJogesetA = docA.reference.path.contains('jogesetek');
        final isMPA = docA.reference.path.contains('memoriapalota_allomasok');
        final isDialogusA = docA.reference.path.contains('dialogus_fajlok');

        titleA = (isJogesetA
                ? (dataA['title'] ?? docA.id)
                : (isMPA || isDialogusA
                    ? (dataA['title'] ?? dataA['cim'] ?? 'Névtelen')
                    : (dataA['title'] ?? dataA['name'] ?? 'Névtelen')))
            .toString();
      }

      String titleB;
      if (b is MapEntry<String, dynamic>) {
        titleB = b.key;
      } else {
        final docB = b as QueryDocumentSnapshot<Map<String, dynamic>>;
        final dataB = docB.data();
        final isJogesetB = docB.reference.path.contains('jogesetek');
        final isMPB = docB.reference.path.contains('memoriapalota_allomasok');
        final isDialogusB = docB.reference.path.contains('dialogus_fajlok');

        titleB = (isJogesetB
                ? (dataB['title'] ?? docB.id)
                : (isMPB || isDialogusB
                    ? (dataB['title'] ?? dataB['cim'] ?? 'Névtelen')
                    : (dataB['title'] ?? dataB['name'] ?? 'Névtelen')))
            .toString();
      }

      return StringUtils.naturalCompare(titleA, titleB);
    });

    return unifiedList;
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

  Widget _buildFolderWidget(String tag, Map<String, dynamic> data) {
    // Betöltött dokumentumok száma (fallback)
    final loadedCount = (data['docs'] as List).length;

    // Hierarchikus path építése a jelenlegi címke útvonalból
    final tagPath = [...widget.tagPath, tag];
    final hierarchicalPath = tagPath.join('/');

    // Próbáljuk meg lekérni a pontos count-ot a metadata-ból
    // Ez egy Future, de mivel a widget build-ban vagyunk, használjuk a betöltött count-ot
    // és egy FutureBuilder-t a pontos count megjelenítéséhez

    return Card(
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
                  color: const Color(0xFF3366CC)),
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
