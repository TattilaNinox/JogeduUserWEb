import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
import '../widgets/note_list_tile.dart';
import '../utils/string_utils.dart';
import '../services/metadata_service.dart';
import '../services/note_session_cache.dart';
import 'tag_drill_down_screen.dart';

/// Kategória címkék képernyő - megjeleníti egy kategória 0-s indexű címkéit és a címke nélküli elemeket.
class CategoryTagsScreen extends StatefulWidget {
  final String category;

  const CategoryTagsScreen({
    super.key,
    required this.category,
  });

  @override
  State<CategoryTagsScreen> createState() => _CategoryTagsScreenState();
}

class _CategoryTagsScreenState extends State<CategoryTagsScreen> {
  bool _hasPremiumAccess = false;

  @override
  void initState() {
    super.initState();
    _checkPremiumAccess();
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

  void _navigateToTagDrillDown(BuildContext context, String tag) {
    final screen = TagDrillDownScreen(
      category: widget.category,
      tagPath: [tag],
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      Navigator.push(context, CupertinoPageRoute(builder: (context) => screen));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
    }
  }

  Widget _buildBreadcrumb() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Főoldal', style: TextStyle(fontSize: 14)),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          Text(widget.category,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
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
        title: Text(widget.category),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: _buildBreadcrumb(),
          ),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadCategoryData(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Hiba: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('Nincs adat.'));
          }

          final data = snapshot.data!;
          final tags = data['tags'] as List<String>;
          final untaggedDocs = data['untaggedDocs']
              as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
          final tagCounts = data['tagCounts'] as Map<String, int>;
          final isAdmin = data['isAdmin'] as bool;

          if (tags.isEmpty && untaggedDocs.isEmpty) {
            return const Center(child: Text('Nincs megjeleníthető tartalom.'));
          }

          // Egységes lista: címkék + címke nélküli jegyzetek
          // JAVÍTVA: Csak olyan címkéket jelenítünk meg, ahol count > 0
          final List<dynamic> unifiedList = [
            ...tags
                .where((tag) => (tagCounts[tag] ?? 0) > 0) // 0 count kiszűrése
                .map((tag) =>
                    {'type': 'tag', 'name': tag, 'count': tagCounts[tag] ?? 0}),
            ...untaggedDocs,
          ];

          // Rendezés
          unifiedList.sort((a, b) {
            String titleA;
            if (a is Map) {
              titleA = a['name'] as String;
            } else {
              final doc = a as QueryDocumentSnapshot<Map<String, dynamic>>;
              final dataA = doc.data();
              final isJogeset = doc.reference.path.contains('jogesetek');
              titleA = (isJogeset
                      ? (dataA['title'] ?? doc.id)
                      : (dataA['title'] ??
                          dataA['name'] ??
                          dataA['cim'] ??
                          'Névtelen'))
                  .toString();
            }

            String titleB;
            if (b is Map) {
              titleB = b['name'] as String;
            } else {
              final doc = b as QueryDocumentSnapshot<Map<String, dynamic>>;
              final dataB = doc.data();
              final isJogeset = doc.reference.path.contains('jogesetek');
              titleB = (isJogeset
                      ? (dataB['title'] ?? doc.id)
                      : (dataB['title'] ??
                          dataB['name'] ??
                          dataB['cim'] ??
                          'Névtelen'))
                  .toString();
            }

            return StringUtils.naturalCompare(titleA, titleB);
          });

          // final totalCount = tags.length + untaggedDocs.length; // Not used

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ...unifiedList.map((item) {
                if (item is Map) {
                  // Címke kártya
                  return _buildTagCard(
                    item['name'] as String,
                    item['count'] as int,
                  );
                } else {
                  // Címke nélküli jegyzet
                  final doc =
                      item as QueryDocumentSnapshot<Map<String, dynamic>>;
                  return _buildDirectNoteWidget(doc, isAdmin);
                }
              }).toList(),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    'Címkék: ${tags.length}, Címke nélküli jegyzetek: ${untaggedDocs.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Kategória adatok betöltése: címkék listája + címke nélküli jegyzetek
  Future<Map<String, dynamic>> _loadCategoryData(String userId) async {
    // 1. Ellenőrizzük a cache-t
    final cached = NoteSessionCache.getCategoryCache(widget.category);
    if (cached != null) {
      if (kDebugMode) {
        debugPrint('💾 CategoryTagsScreen: Cache HIT - ${widget.category}');
      }

      // Admin státusz lekérése
      final isAdmin = await _checkIsAdmin(userId);

      // Tag counts kiszámítása (metadata-ból)
      final tagCounts = await _getTagCounts();

      return {
        'tags': cached.tags,
        'untaggedDocs': cached.untaggedNotes,
        'tagCounts': tagCounts,
        'isAdmin': isAdmin,
      };
    }

    if (kDebugMode) {
      debugPrint('🔄 CategoryTagsScreen: Cache MISS - betöltés indul...');
    }

    // 2. Admin státusz ellenőrzése
    final isAdmin = await _checkIsAdmin(userId);

    // 3. Metadata-ból címkék listája
    final metadata = await MetadataService.getCategoryTagMapping('Jogász');
    final catToTags = metadata['catToTags'] ?? {};
    final tags = (catToTags[widget.category]?.toList() as List<String>?) ?? [];
    tags.sort();

    // 4. Tag counts lekérése
    final tagCounts = await _getTagCounts();

    // 5. Címke NÉLKÜLI jegyzetek betöltése (limit: 100)
    final untaggedDocs = await _loadUntaggedNotes(isAdmin);

    // 6. Cache-eljük az eredményt
    NoteSessionCache.cacheCategory(
      category: widget.category,
      tags: tags,
      untaggedNotes: untaggedDocs,
    );

    return {
      'tags': tags,
      'untaggedDocs': untaggedDocs,
      'tagCounts': tagCounts,
      'isAdmin': isAdmin,
    };
  }

  /// Admin státusz ellenőrzése
  Future<bool> _checkIsAdmin(String userId) async {
    try {
      final userDoc =
          await FirebaseConfig.firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data()!;
      final userType = (userData['userType'] as String? ?? '').toLowerCase();
      final isAdminEmail =
          FirebaseAuth.instance.currentUser?.email == 'tattila.ninox@gmail.com';
      final isAdminBool = userData['isAdmin'] == true;

      return userType == 'admin' || isAdminEmail || isAdminBool;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking admin status: $e');
      }
      return false;
    }
  }

  /// Tag counts lekérése a metadata aggregációból
  Future<Map<String, int>> _getTagCounts() async {
    try {
      final metadata = await MetadataService.getCategoryTagMapping('Jogász');

      if (kDebugMode) {
        debugPrint(
            '🔍 _getTagCounts: Keresett kategória: "${widget.category}"');
        debugPrint(
            '🔍 _getTagCounts: Metadata keys: ${metadata.keys.toList()}');
      }

      final tagCountsData =
          metadata['tagCounts'] as Map<String, Map<String, int>>?;

      if (kDebugMode) {
        debugPrint(
            '🔍 _getTagCounts: tagCountsData null? ${tagCountsData == null}');
        if (tagCountsData != null) {
          debugPrint(
              '🔍 _getTagCounts: tagCountsData keys: ${tagCountsData.keys.toList()}');
        }
      }

      if (tagCountsData != null && tagCountsData.containsKey(widget.category)) {
        final counts = tagCountsData[widget.category]!;
        if (kDebugMode) {
          debugPrint(
              '✅ Tag counts betöltve metadata-ból: ${counts.length} címke, értékek: $counts');
        }
        return counts;
      }

      if (kDebugMode) {
        debugPrint(
            '⚠️ Tag counts nem található a metadata-ban a(z) "${widget.category}" kategóriához');
      }
      return {};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Hiba a tag counts betöltésekor: $e');
      }
      return {};
    }
  }

  /// Címke NÉLKÜLI jegyzetek betöltése
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadUntaggedNotes(
      bool isAdmin) async {
    const science = 'Jogász';
    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final int currentLimit = 100;

    // Notes kollekció
    final notesQuery = FirebaseConfig.firestore
        .collection('notes')
        .where('science', isEqualTo: science)
        .where('category', isEqualTo: widget.category)
        .where('status',
            whereIn: isAdmin
                ? ['Published', 'Public', 'Draft']
                : ['Published', 'Public'])
        .orderBy('title')
        .limit(currentLimit);

    final notesSnapshot = await notesQuery.get();
    allDocs
        .addAll(notesSnapshot.docs.where((d) => d.data()['deletedAt'] == null));

    // Jogesetek kollekció
    final jogesetQuery = FirebaseConfig.firestore
        .collection('jogesetek')
        .where('science', isEqualTo: science)
        .where('category', isEqualTo: widget.category)
        .where('status',
            whereIn: isAdmin
                ? ['Published', 'Public', 'Draft']
                : ['Published', 'Public'])
        .orderBy(FieldPath.documentId)
        .limit(currentLimit);

    final jogesetSnapshot = await jogesetQuery.get();
    allDocs.addAll(
        jogesetSnapshot.docs.where((d) => d.data()['deletedAt'] == null));

    // Memoriapalota állomások
    final allomasQuery = FirebaseConfig.firestore
        .collection('memoriapalota_allomasok')
        .where('science', isEqualTo: science)
        .where('category', isEqualTo: widget.category)
        .where('status',
            whereIn: isAdmin
                ? ['Published', 'Public', 'Draft']
                : ['Published', 'Public'])
        .orderBy('title')
        .limit(currentLimit);

    final allomasSnapshot = await allomasQuery.get();
    allDocs.addAll(
        allomasSnapshot.docs.where((d) => d.data()['deletedAt'] == null));

    // Dialogus fajlok (csak ha "Dialogus tags" kategória)
    if (widget.category == 'Dialogus tags') {
      final dialogusQuery = FirebaseConfig.firestore
          .collection('dialogus_fajlok')
          .where('science', isEqualTo: science)
          .limit(currentLimit);

      final dialogusSnapshot = await dialogusQuery.get();
      allDocs.addAll(dialogusSnapshot.docs.where((d) {
        if (d.data()['deletedAt'] != null) return false;
        final status = d.data()['status'] as String? ?? 'Draft';
        if (!isAdmin && status != 'Published') return false;
        return true;
      }));
    }

    // Szűrés: CSAK azok, ahol tags üres vagy nincs
    final untaggedDocs = allDocs.where((doc) {
      final tags = doc.data()['tags'] as List? ?? [];
      return tags.isEmpty;
    }).toList();

    if (kDebugMode) {
      debugPrint(
          '✅ Címke nélküli jegyzetek betöltve: ${untaggedDocs.length} db (összesen: ${allDocs.length} db vizsgálva)');
    }

    return untaggedDocs;
  }

  Widget _buildTagCard(String tag, int count) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        onTap: () => _navigateToTagDrillDown(context, tag),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.label, color: Color(0xFF3366CC)),
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

  Widget _buildDirectNoteWidget(
      QueryDocumentSnapshot<Map<String, dynamic>> doc, bool isAdmin) {
    final data = doc.data();
    final isMP = doc.reference.path.contains('memoriapalota_allomasok');
    final isDialogus = doc.reference.path.contains('dialogus_fajlok');
    final isJogeset = doc.reference.path.contains('jogesetek');

    String title =
        (data['title'] ?? data['name'] ?? data['cim'] ?? 'Névtelen').toString();
    String type = isMP
        ? 'memoriapalota_allomasok'
        : (isDialogus
            ? 'dialogus_fajlok'
            : (isJogeset
                ? 'jogeset'
                : (data['type'] as String? ?? 'standard')));

    bool isFree = (data['isFree'] == true) ||
        (data['is_free'] == true) ||
        (data['isFree'] == 1) ||
        (data['is_free'] == 1);
    int? jogesetCount;

    if (isJogeset) {
      title = (data['title'] ?? 'Jogeset').toString();
      isFree = (data['isFree'] == true) || (data['is_free'] == true);

      // Kiszámoljuk a jogesetek számát a tömbből
      final jogesetekList = data['jogesetek'] as List? ?? [];
      jogesetCount = jogesetekList.length;
    }

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
      isLocked: !isFree && !_hasPremiumAccess,
      jogesetCount: jogesetCount,
      category: widget.category,
      customFromUrl: '/notes',
    );
  }
}
