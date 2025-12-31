import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
import '../widgets/note_list_tile.dart';
import '../utils/string_utils.dart';

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
  // FIX: Megemelt limit, hogy minden dokumentum betöltődjön egyszerre, gomb nélkül
  final int _currentLimit = 1000;
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

  int get _currentDepth => widget.tagPath.length;

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
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
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

          // Lekérdezések építése
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

          // Jogesetek: Restore science and category filters
          Query<Map<String, dynamic>> jogesetQuery = FirebaseConfig.firestore
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

          Query<Map<String, dynamic>> allomasQuery = FirebaseConfig.firestore
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
                      final dStream =
                          dialogusQuery?.snapshots() ?? const Stream.empty();
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: dStream,
                        builder: (context, dSnap) {
                          if (notesSnap.hasError) {
                            return Center(
                                child: Text('Hiba: ${notesSnap.error}'));
                          }

                          // Adatok összefésülése és szűrése a tagPath alapján
                          final allDocs =
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                          if (notesSnap.hasData) {
                            allDocs.addAll(notesSnap.data!.docs
                                .where((d) => d.data()['deletedAt'] == null));
                          }
                          if (jogesetSnap.hasData) {
                            allDocs.addAll(jogesetSnap.data!.docs
                                .where((d) => d.data()['deletedAt'] == null));
                          }
                          if (allomasSnap.hasData) {
                            allDocs.addAll(allomasSnap.data!.docs
                                .where((d) => d.data()['deletedAt'] == null));
                          }

                          final Map<String, dynamic> hierarchy =
                              _buildHierarchy(allDocs, jogesetSnap.data?.docs,
                                  dSnap.data?.docs, isAdmin);

                          final List<dynamic> unifiedList =
                              _getUnifiedList(hierarchy);

                          // Kiszámoljuk az összes dokumentumot ezen a szinten (és alatta)
                          int totalMatchingCount = 0;
                          if (hierarchy.containsKey('_direct')) {
                            totalMatchingCount +=
                                (hierarchy['_direct'] as List).length;
                          }
                          hierarchy.forEach((key, value) {
                            if (!key.startsWith('_')) {
                              totalMatchingCount +=
                                  (value['docs'] as List).length;
                            }
                          });

                          if (unifiedList.isEmpty) {
                            if (!notesSnap.hasData && !allomasSnap.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            return const Center(
                                child: Text(
                                    'Nincs megjeleníthető tartalom ezen a szinten.'));
                          }

                          final bool hasMore =
                              unifiedList.length > _currentLimit;
                          final displayedItems = hasMore
                              ? unifiedList.take(_currentLimit).toList()
                              : unifiedList;

                          final List<Widget> widgetsList = [];
                          for (var item in displayedItems) {
                            if (item is MapEntry<String, dynamic>) {
                              widgetsList.add(
                                  _buildFolderWidget(item.key, item.value));
                            } else {
                              final doc = item as QueryDocumentSnapshot<
                                  Map<String, dynamic>>;
                              if (doc.reference.path.contains('jogesetek')) {
                                widgetsList.add(_buildJogesetWidget(doc));
                              } else {
                                widgetsList.add(_buildNoteWidget(doc));
                              }
                            }
                          }

                          return ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              ...widgetsList,
                              Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Center(
                                  child: Text(
                                    'Összesen: $totalMatchingCount dokumentum',
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
                },
              );
            },
          );
        },
      ),
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
      if (!_matchesPath(tags)) continue;

      if (tags.length > _currentDepth) {
        final nextTag = tags[_currentDepth];
        _addToHierarchy(
            hierarchy, nextTag, doc, tags.length > _currentDepth + 1);
      } else {
        direct.add(doc);
      }
    }

    // Jogesetek: top-level fields are processed in the docs loop above.
    // Removed redundant nested jogesetek loop.

    // Dialógusok
    if (widget.category == 'Dialogus tags' && dialogusDocs != null) {
      for (var doc in dialogusDocs) {
        if (doc.data()['deletedAt'] != null) continue;
        final data = doc.data();
        final status = data['status'] as String? ?? 'Draft';
        if (!isAdmin && status != 'Published') continue;
        final category = data['category'] as String? ?? '';

        // Dialógusoknál a tagPath első eleme a category
        if (category != widget.tagPath[0]) continue;

        final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();
        // Dialógusoknál a tags tömb a 2. szinttől kezdődik
        final effectiveTags = [category, ...tags];
        if (!_matchesPath(effectiveTags)) continue;

        if (effectiveTags.length > _currentDepth) {
          final nextTag = effectiveTags[_currentDepth];
          _addToHierarchy(hierarchy, nextTag, doc,
              effectiveTags.length > _currentDepth + 1);
        } else {
          direct.add(doc);
        }
      }
    }

    if (direct.isNotEmpty) hierarchy['_direct'] = direct;
    return hierarchy;
  }

  bool _matchesPath(List<String> tags) {
    if (tags.length < widget.tagPath.length) return false;
    for (int i = 0; i < widget.tagPath.length; i++) {
      if (tags[i] != widget.tagPath[i]) return false;
    }
    return true;
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
    final count = (data['docs'] as List).length;
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
              Text('$count',
                  style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
