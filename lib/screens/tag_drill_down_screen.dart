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
  final ScrollController _breadcrumbScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkPremiumAccess();
    // Scroll to the end after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollBreadcrumbToEnd();
    });
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

    // Főoldal
    items.add(
      TextButton(
        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
        child: const Text(
          'Főoldal',
          style: TextStyle(fontSize: 14),
        ),
      ),
    );

    // Kategória - visszanavigál a CategoryTagsScreen-re
    items.add(const Icon(Icons.chevron_right, size: 16, color: Colors.grey));
    items.add(
      TextButton(
        onPressed: () {
          // Visszanavigálás a CategoryTagsScreen-re
          // Ha csak 1 elem van a tagPath-ban, akkor egy szinttel visszalépünk
          if (widget.tagPath.length == 1) {
            Navigator.pop(context);
          } else {
            // Ha több elem van, akkor a kategória szintre navigálunk vissza
            Navigator.popUntil(
              context,
              (route) =>
                  route.settings.name == '/category_tags' || route.isFirst,
            );
          }
        },
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
      controller: _breadcrumbScrollController,
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
        builder: (context, notesSnapshot) {
          // Jogesetek stream builder hozzáadása
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _buildJogesetQuery().snapshots(),
            builder: (context, jogesetSnapshot) {
              if (notesSnapshot.hasError || jogesetSnapshot.hasError) {
                return Center(
                  child: Text('Hiba: ${notesSnapshot.error ?? jogesetSnapshot.error}'),
                );
              }

              if (!notesSnapshot.hasData && !jogesetSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              // Összefésüljük a két kollekciót
              final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              
              if (notesSnapshot.hasData) {
                allDocs.addAll(notesSnapshot.data!.docs
                    .where((d) => d.data()['deletedAt'] == null)
                    .toList());
              }
              
              // Jogeset dokumentumok feldolgozása
              final processedJogesetDocs = <Map<String, dynamic>>[];
              if (jogesetSnapshot.hasData) {
                final jogesetDocs = jogesetSnapshot.data!.docs
                    .where((d) => d.data()['deletedAt'] == null)
                    .toList();
                
                // Admin ellenőrzés
                final user = FirebaseAuth.instance.currentUser;
                final isAdmin = user?.email == 'tattila.ninox@gmail.com';
                
                processedJogesetDocs.addAll(_processJogesetDocuments(jogesetDocs, isAdmin: isAdmin));
              }

              if (allDocs.isEmpty && processedJogesetDocs.isEmpty) {
                return const Center(child: Text('Nincs találat.'));
              }

              // Hierarchikus csoportosítás
              final hierarchy = _buildHierarchy(allDocs, processedJogesetDocs);

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _buildHierarchyWidgets(hierarchy),
              );
            },
          );
        },
      ),
    );
  }

  /// Firestore lekérdezés építése notes kollekcióhoz
  /// FONTOS: Firestore nem támogatja több array-contains szűrőt,
  /// ezért csak a kategóriára szűrünk, és kliens oldalon szűrjük a címkéket
  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseConfig.firestore
        .collection('notes')
        .where('science', isEqualTo: 'Jogász')
        .where('category', isEqualTo: widget.category);

    return query;
  }

  /// Firestore lekérdezés építése jogesetek kollekcióhoz
  /// FONTOS: A jogesetek dokumentumai csak egy 'jogesetek' tömböt tartalmaznak,
  /// a category, tags, status mezők a tömb elemeiben vannak, nem a dokumentum szinten.
  /// Ezért csak science alapján szűrünk, a többi szűrést kliens oldalon végezzük.
  Query<Map<String, dynamic>> _buildJogesetQuery() {
    Query<Map<String, dynamic>> query = FirebaseConfig.firestore
        .collection('jogesetek');
    // Megjegyzés: Ha van index a science mezőre a dokumentum szinten, akkor használhatjuk,
    // de valószínűleg nincs, ezért minden dokumentumot lekérdezünk és kliens oldalon szűrünk

    return query;
  }

  /// Jogeset dokumentumok feldolgozása és kliens oldali szűrése
  /// Kinyeri a jogesetek tömböt minden dokumentumból és szűr kategória alapján
  List<Map<String, dynamic>> _processJogesetDocuments(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      {bool isAdmin = false}) {
    final processedDocs = <Map<String, dynamic>>[];

    for (var doc in docs) {
      final data = doc.data();
      final jogesetekList = data['jogesetek'] as List<dynamic>? ?? [];

      // Minden jogeset objektumot külön dokumentumként kezelünk
      for (var jogesetData in jogesetekList) {
        final jogeset = jogesetData as Map<String, dynamic>;
        
        // Kategória szűrés
        final category = jogeset['category'] as String? ?? '';
        if (category != widget.category) {
          continue;
        }

        // Státusz szűrés
        final status = jogeset['status'] as String? ?? 'Draft';
        if (!isAdmin && status != 'Published') {
          continue;
        }

        // Létrehozunk egy virtuális dokumentumot a jogesetből
        final virtualDoc = {
          ...jogeset,
          '_documentId': doc.id, // Az eredeti dokumentum ID-ja
          '_jogesetId': jogeset['id'], // A jogeset ID-ja a dokumentumon belül
          'type': 'jogeset',
          // A 'name' mezőt használjuk címként (a dokumentum szerint 'cim' a mező neve)
          'name': jogeset['cim'] as String? ?? '',
          // A 'title' mezőt is hozzáadjuk a kompatibilitásért
          'title': jogeset['title'] as String? ?? '',
        };

        processedDocs.add(virtualDoc);
      }
    }

    return processedDocs;
  }

  /// Hierarchia építése a dokumentumokból
  /// Kliens oldali szűrés a teljes tag path alapján
  Map<String, dynamic> _buildHierarchy(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> notesDocs,
      List<Map<String, dynamic>> jogesetDocs) {
    final hierarchy = <String, dynamic>{};

    // Notes dokumentumok feldolgozása
    for (var doc in notesDocs) {
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
    
    // Jogeset dokumentumok feldolgozása
    for (var jogesetData in jogesetDocs) {
      final tags = (jogesetData['tags'] as List<dynamic>? ?? []).cast<String>();

      // Ellenőrizzük, hogy a dokumentum címkéi megfelelnek-e a jelenlegi útvonalnak
      bool matchesPath = true;

      if (tags.length < widget.tagPath.length) {
        matchesPath = false;
      } else {
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
            'jogesetek': <Map<String, dynamic>>[],
            'hasChildren': false,
          };
        }

        if (tags.length > _currentDepth + 1) {
          hierarchy[nextTag]['hasChildren'] = true;
        }

        // Jogeseteket külön listába tesszük
        if (hierarchy[nextTag]['jogesetek'] == null) {
          hierarchy[nextTag]['jogesetek'] = <Map<String, dynamic>>[];
        }
        (hierarchy[nextTag]['jogesetek'] as List).add(jogesetData);
      } else {
        // Ha nincs következő szintű címke, akkor közvetlenül ide tartozik
        hierarchy.putIfAbsent(
            '_directJogesetek', () => <Map<String, dynamic>>[]);
        (hierarchy['_directJogesetek'] as List).add(jogesetData);
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
        for (var doc in directDocs) {
          widgets.add(_buildNoteWidget(doc));
        }

        widgets.add(const SizedBox(height: 24));
      }
    }
    
    // Közvetlen jogesetek (amelyeknek nincs további alcímkéjük)
    if (hierarchy.containsKey('_directJogesetek')) {
      final directJogesetek = hierarchy['_directJogesetek']
          as List<Map<String, dynamic>>;

      if (directJogesetek.isNotEmpty) {
        for (var jogesetData in directJogesetek) {
          widgets.add(_buildJogesetWidget(jogesetData));
        }

        widgets.add(const SizedBox(height: 24));
      }
    }

    // Aztán a következő szintű címkék
    final tagEntries = hierarchy.entries
        .where((e) => e.key != '_direct' && e.key != '_directJogesetek')
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (tagEntries.isNotEmpty) {
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
    final jogesetek = data['jogesetek'] as List<Map<String, dynamic>>? ?? [];
    final hasChildren = data['hasChildren'] as bool;
    final totalCount = docs.length + jogesetek.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _navigateToNextLevel(context, tag),
        borderRadius: BorderRadius.circular(8),
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
                '$totalCount',
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
    
    // Ellenőrizzük, hogy jogeset dokumentumról van-e szó
    final isJogeset = doc.reference.path.contains('jogesetek');
    
    // Jogeseteknél 'name' mezőt használunk, egyébként 'title'-t
    final title = isJogeset 
        ? (data['name'] as String? ?? '')
        : (data['title'] as String? ?? '');
    
    // Típus meghatározása
    final type = isJogeset 
        ? 'jogeset'
        : (data['type'] as String? ?? 'standard');
    
    final isFree = data['isFree'] as bool? ?? false;
    final isLocked = !isFree && !_hasPremiumAccess;

    // Egyedi from URL létrehozása a jelenlegi TagDrillDownScreen-hez való visszalépéshez
    // Mivel Navigator.push()-sal navigáltunk ide, nincs GoRouter URL
    // Ezért manuálisan kell létrehozni egy /notes URL-t, amely visszavisz a főoldalra
    // MEGJEGYZÉS: Ideális esetben itt egy deep link-et kellene létrehozni a TagDrillDownScreen-hez,
    // de mivel az Navigator.push()-sal van megnyitva, nincs URL-je
    // Egyszerűsített megoldás: visszalépés a /notes főoldalra
    const customFromUrl = '/notes';

    return NoteListTile(
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
    );
  }

  /// Jogeset widget építése
  Widget _buildJogesetWidget(Map<String, dynamic> jogesetData) {
    // A dokumentum ID-t a _documentId mezőből vesszük
    final documentId = jogesetData['_documentId'] as String? ?? '';
    final title = jogesetData['name'] as String? ?? jogesetData['cim'] as String? ?? '';
    final type = 'jogeset';
    final isFree = jogesetData['isFree'] as bool? ?? false;
    final isLocked = !isFree && !_hasPremiumAccess;

    const customFromUrl = '/notes';

    return NoteListTile(
      id: documentId,
      title: title,
      type: type,
      hasDoc: false, // Jogeseteknek nincs docxUrl-ük
      hasAudio: false, // Jogeseteknek nincs audioUrl-ük
      hasVideo: false, // Jogeseteknek nincs videoUrl-ük
      isLocked: isLocked,
      isLast: false,
      customFromUrl: customFromUrl,
    );
  }
}
