import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
import '../widgets/note_list_tile.dart';

/// Drill-down navigációs képernyő a címkék hierarchikus böngészéséhez.
///
/// Ez a képernyő a 3+ szintű címke navigációt kezeli, ahol a felhasználó
/// mélyebbre áshat a címkék hierarchiájában. Minden szinten megjeleníti:
/// - A következő szintű címkéket (tags[currentDepth])
/// - A jegyzeteket, amelyeknek nincs további alcímkéjük
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

  @override
  void initState() {
    super.initState();
    _checkPremiumAccess();
  }

  Future<void> _checkPremiumAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _hasPremiumAccess = false);
      return;
    }

    try {
      final userDoc = await FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() => _hasPremiumAccess = false);
        return;
      }

      final userData = userDoc.data()!;

      // Admin ellenőrzés - adminok minden jegyzetet láthatnak
      final userType = (userData['userType'] as String? ?? '').toLowerCase();
      final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
      final isAdminBool = userData['isAdmin'] == true;
      final isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;

      if (isAdmin) {
        setState(() => _hasPremiumAccess = true);
        return;
      }

      // Nem admin esetén ellenőrizzük az előfizetést
      final subscriptionStatus =
          userData['subscriptionStatus'] as String? ?? 'inactive';
      final trialActive = userData['trialActive'] as bool? ?? false;

      setState(() {
        _hasPremiumAccess = subscriptionStatus == 'active' || trialActive;
      });
    } catch (e) {
      debugPrint('Error checking premium access: $e');
      setState(() => _hasPremiumAccess = false);
    }
  }

  int get _currentDepth => widget.tagPath.length;

  /// Platform-natív navigáció a következő szintre
  void _navigateToNextLevel(BuildContext context, String nextTag) {
    final newTagPath = [...widget.tagPath, nextTag];

    final screen = TagDrillDownScreen(
      category: widget.category,
      tagPath: newTagPath,
    );

    // Platform-natív navigáció
    if (!kIsWeb && Platform.isIOS) {
      Navigator.push(
        context,
        CupertinoPageRoute(builder: (context) => screen),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen),
      );
    }
  }

  /// Breadcrumb navigáció építése
  Widget _buildBreadcrumb() {
    final items = <Widget>[];

    // Kategória
    items.add(
      TextButton(
        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
        child: Text(
          widget.category,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );

    // Címkék
    for (int i = 0; i < widget.tagPath.length; i++) {
      items.add(const Icon(Icons.chevron_right, size: 16, color: Colors.grey));

      final isLast = i == widget.tagPath.length - 1;
      items.add(
        isLast
            ? Text(
                widget.tagPath[i],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              )
            : TextButton(
                onPressed: () {
                  // Visszanavigálás az adott szintre
                  final targetDepth = i + 1;
                  final currentDepth = widget.tagPath.length;
                  final popCount = currentDepth - targetDepth;

                  for (int j = 0; j < popCount; j++) {
                    Navigator.pop(context);
                  }
                },
                child: Text(
                  widget.tagPath[i],
                  style: const TextStyle(fontSize: 14),
                ),
              ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Hiba: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs
              .where((d) => d.data()['deletedAt'] == null)
              .toList();

          if (docs.isEmpty) {
            return const Center(child: Text('Nincs találat.'));
          }

          // Hierarchikus csoportosítás
          final hierarchy = _buildHierarchy(docs);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: _buildHierarchyWidgets(hierarchy),
          );
        },
      ),
    );
  }

  /// Firestore lekérdezés építése
  /// FONTOS: Firestore nem támogatja több array-contains szűrőt,
  /// ezért csak a kategóriára szűrünk, és kliens oldalon szűrjük a címkéket
  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseConfig.firestore
        .collection('notes')
        .where('science', isEqualTo: 'Jogász')
        .where('category', isEqualTo: widget.category);

    return query;
  }

  /// Hierarchia építése a dokumentumokból
  /// Kliens oldali szűrés a teljes tag path alapján
  Map<String, dynamic> _buildHierarchy(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final hierarchy = <String, dynamic>{};

    for (var doc in docs) {
      final data = doc.data();
      final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();

      // Ellenőrizzük, hogy a dokumentum címkéi megfelelnek-e a jelenlegi útvonalnak
      // A tagPath minden elemének meg kell egyeznie a dokumentum tags tömbjének megfelelő indexű elemével
      bool matchesPath = true;

      // Ha a tagPath hosszabb, mint a dokumentum tags tömbje, akkor nem egyezik
      if (tags.length < widget.tagPath.length) {
        matchesPath = false;
      } else {
        // Ellenőrizzük, hogy minden tagPath elem megegyezik-e a megfelelő pozícióban
        for (int i = 0; i < widget.tagPath.length; i++) {
          if (tags[i] != widget.tagPath[i]) {
            matchesPath = false;
            break;
          }
        }
      }

      if (!matchesPath) continue;

      // Ha van következő szintű címke
      if (tags.length > _currentDepth) {
        final nextTag = tags[_currentDepth];

        if (!hierarchy.containsKey(nextTag)) {
          hierarchy[nextTag] = <String, dynamic>{
            'docs': <QueryDocumentSnapshot<Map<String, dynamic>>>[],
            'hasChildren': false,
          };
        }

        // Ellenőrizzük, van-e még mélyebb szint
        if (tags.length > _currentDepth + 1) {
          hierarchy[nextTag]['hasChildren'] = true;
        }

        hierarchy[nextTag]['docs'].add(doc);
      } else {
        // Ha nincs következő szintű címke, akkor közvetlenül ide tartozik
        hierarchy.putIfAbsent(
            '_direct', () => <QueryDocumentSnapshot<Map<String, dynamic>>>[]);
        (hierarchy['_direct'] as List).add(doc);
      }
    }

    return hierarchy;
  }

  /// Hierarchia widgetek építése
  List<Widget> _buildHierarchyWidgets(Map<String, dynamic> hierarchy) {
    final widgets = <Widget>[];

    // Először a közvetlen jegyzetek (amelyeknek nincs további alcímkéjük)
    if (hierarchy.containsKey('_direct')) {
      final directDocs = hierarchy['_direct']
          as List<QueryDocumentSnapshot<Map<String, dynamic>>>;

      if (directDocs.isNotEmpty) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Jegyzetek',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

        for (var doc in directDocs) {
          widgets.add(_buildNoteWidget(doc));
        }

        widgets.add(const SizedBox(height: 24));
      }
    }

    // Aztán a következő szintű címkék
    final tagEntries = hierarchy.entries
        .where((e) => e.key != '_direct')
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (tagEntries.isNotEmpty) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Alcímkék',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

      for (var entry in tagEntries) {
        widgets.add(_buildTagWidget(entry.key, entry.value));
      }
    }

    return widgets;
  }

  /// Címke widget építése
  Widget _buildTagWidget(String tag, Map<String, dynamic> data) {
    final docs =
        data['docs'] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final hasChildren = data['hasChildren'] as bool;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToNextLevel(context, tag),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                hasChildren ? Icons.folder : Icons.label,
                color: const Color(0xFF3366CC),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${docs.length}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Jegyzet widget építése
  Widget _buildNoteWidget(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = data['title'] as String? ?? '';
    final type = data['type'] as String? ?? 'standard';
    final isFree = data['isFree'] as bool? ?? false;
    final isLocked = !isFree && !_hasPremiumAccess;

    // Egyedi from URL létrehozása a jelenlegi TagDrillDownScreen-hez való visszalépéshez
    // Mivel Navigator.push()-sal navigáltunk ide, nincs GoRouter URL
    // Ezért manuálisan kell létrehozni egy /notes URL-t, amely visszavisz a főoldalra
    // MEGJEGYZÉS: Ideális esetben itt egy deep link-et kellene létrehozni a TagDrillDownScreen-hez,
    // de mivel az Navigator.push()-sal van megnyitva, nincs URL-je
    // Egyszerűsített megoldás: visszalépés a /notes főoldalra
    final customFromUrl = '/notes';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: NoteListTile(
        id: doc.id,
        title: title,
        type: type,
        hasDoc: (data['docxUrl'] ?? '').toString().isNotEmpty,
        hasAudio: (data['audioUrl'] ?? '').toString().isNotEmpty,
        audioUrl: (data['audioUrl'] ?? '').toString(),
        hasVideo: (data['videoUrl'] ?? '').toString().isNotEmpty,
        deckCount: type == 'deck'
            ? (data['flashcards'] as List<dynamic>? ?? []).length
            : null,
        isLocked: isLocked,
        isLast: false,
        customFromUrl: customFromUrl, // Egyedi from URL átadása
      ),
    );
  }
}
