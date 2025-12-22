import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
import '../core/access_control.dart';
import 'tag_drill_down_screen.dart';

/// Kategória címkék képernyő - megjeleníti egy kategória 0-s indexű címkéit
///
/// Ez a képernyő a kategória és a mélyebb címkék közötti navigációs szintet képviseli.
/// Megjeleníti az összes tags[0] címkét az adott kategóriában.
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
  /// Platform-natív navigáció a következő szintre (TagDrillDownScreen)
  void _navigateToTagDrillDown(BuildContext context, String tag) {
    final screen = TagDrillDownScreen(
      category: widget.category,
      tagPath: [tag],
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Főoldal',
              style: TextStyle(fontSize: 14),
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          Text(
            widget.category,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      body: widget.category == 'Dialogus tags'
          ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildDialogusFajlokQuery().snapshots(),
              builder: (context, dialogusSnapshot) {
                if (dialogusSnapshot.hasError) {
                  return Center(
                    child: Text('Hiba: ${dialogusSnapshot.error}'),
                  );
                }

                if (!dialogusSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final dialogusDocs = dialogusSnapshot.data!.docs
                    .where((d) {
                      final data = d.data();
                      return data['deletedAt'] == null;
                    })
                    .toList();

                // Admin ellenőrzés - StreamBuilder-ben szinkron módon
                final user = FirebaseAuth.instance.currentUser;
                bool isAdmin = false;
                if (user != null && user.email != null) {
                  isAdmin = AccessControl.allowedAdmins.contains(user.email);
                }

                // Feldolgozzuk a dialogus fájlokat: category mező alapján csoportosítás
                final categoryMap = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

                debugPrint('🔵 CategoryTagsScreen: ${dialogusDocs.length} dialogus_fajlok dokumentum betöltve');
                
                for (var doc in dialogusDocs) {
                  final data = doc.data();
                  
                  // Szűrés: csak azok a dokumentumok, amelyeknek van audioUrl-je
                  final audioUrl = data['audioUrl'] as String?;
                  if (audioUrl == null || audioUrl.isEmpty || audioUrl.trim().isEmpty) {
                    debugPrint('🔴 Dokumentum ${doc.id}: nincs audioUrl');
                    continue;
                  }

                  // Státusz szűrés
                  final status = data['status'] as String? ?? 'Draft';
                  if (!isAdmin && status != 'Published') {
                    debugPrint('🔴 Dokumentum ${doc.id}: státusz nem Published ($status)');
                    continue;
                  }

                  // Science már szűrve van a Firestore lekérdezésben

                  // Category mező alapján csoportosítás
                  final category = data['category'] as String? ?? '';
                  if (category.isNotEmpty && category.trim().isNotEmpty) {
                    categoryMap.putIfAbsent(category, () => []);
                    categoryMap[category]!.add(doc);
                    debugPrint('🔵 Dokumentum ${doc.id}: hozzáadva a $category kategóriához');
                  } else {
                    debugPrint('🔴 Dokumentum ${doc.id}: nincs category mező vagy üres');
                  }
                }
                
                debugPrint('🔵 CategoryTagsScreen: ${categoryMap.length} kategória található');

                if (categoryMap.isEmpty) {
                  return const Center(child: Text('Nincs találat.'));
                }

                // Rendezés
                final sortedCategories = categoryMap.keys.toList()..sort();

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    ...sortedCategories.map((category) {
                      final docs = categoryMap[category] ?? [];
                      return _buildCategoryCard(category, docs);
                    }),
                  ],
                );
              },
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildQuery().snapshots(),
              builder: (context, notesSnapshot) {
                // Jogesetek stream builder hozzáadása
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _buildJogesetQuery().snapshots(),
                  builder: (context, jogesetSnapshot) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _buildAllomasQuery().snapshots(),
                      builder: (context, allomasSnapshot) {
                        if (notesSnapshot.hasError ||
                            jogesetSnapshot.hasError ||
                            allomasSnapshot.hasError) {
                          return Center(
                            child: Text(
                                'Hiba: ${notesSnapshot.error ?? jogesetSnapshot.error ?? allomasSnapshot.error}'),
                          );
                        }

                        // Normál kategóriák esetén (notes, jogesetek, állomások)
                        if (!notesSnapshot.hasData &&
                            !jogesetSnapshot.hasData &&
                            !allomasSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                    // Összefésüljük a két kollekciót
                    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              
              if (notesSnapshot.hasData) {
                allDocs.addAll(notesSnapshot.data!.docs
                    .where((d) => d.data()['deletedAt'] == null)
                    .toList());
              }
              
              // Összegyűjtjük a tags[0] címkéket
              final tagMap =
                  <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
              
              // Jogesetek címkéinek külön kezelése
              final jogesetTagMap = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

              // Notes dokumentumok feldolgozása
              for (var doc in allDocs) {
                final data = doc.data();
                final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();

                if (tags.isNotEmpty) {
                  final firstTag = tags[0];
                  tagMap.putIfAbsent(firstTag, () => []);
                  tagMap[firstTag]!.add(doc);
                }
              }
              
              // Jogeset dokumentumok feldolgozása
              // Admin ellenőrzés szükséges a státusz szűréshez
              final user = FirebaseAuth.instance.currentUser;
              bool isAdmin = false;
              if (user != null) {
                isAdmin = AccessControl.allowedAdmins.contains(user.email);
              }
              
              // Jogesetek feldolgozása (ha vannak)
              if (jogesetSnapshot.hasData) {
                final jogesetDocs = jogesetSnapshot.data!.docs
                    .where((d) => d.data()['deletedAt'] == null)
                    .toList();
                final processedJogesetDocs = _processJogesetDocuments(jogesetDocs, isAdmin: isAdmin);
                
                // Az első jogeset címkéit használjuk a dokumentum címkéjeként
                for (var doc in processedJogesetDocs) {
                  final data = doc.data();
                  final jogesetekList = data['jogesetek'] as List<dynamic>? ?? [];
                  
                  // Megkeressük az első megfelelő jogesetet a címkék meghatározásához
                  Map<String, dynamic>? firstMatchingJogeset;
                  for (var jogesetData in jogesetekList) {
                    final jogeset = jogesetData as Map<String, dynamic>;
                    
                    final category = jogeset['category'] as String? ?? '';
                    if (category != widget.category) continue;
                    
                    final status = jogeset['status'] as String? ?? 'Draft';
                    if (!isAdmin && status != 'Published') continue;
                    
                    firstMatchingJogeset = jogeset;
                    break;
                  }
                  
                  if (firstMatchingJogeset != null) {
                    final tags = (firstMatchingJogeset['tags'] as List<dynamic>? ?? []).cast<String>();
                    
                    if (tags.isNotEmpty) {
                      final firstTag = tags[0];
                      jogesetTagMap.putIfAbsent(firstTag, () => []);
                      jogesetTagMap[firstTag]!.add(doc);
                    }
                  }
                }
              }
              
              // Állomások feldolgozása (ha vannak)
              final allomasTagMap = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
              if (allomasSnapshot.hasData) {
                final allomasDocs = allomasSnapshot.data!.docs
                    .where((d) => d.data()['deletedAt'] == null)
                    .toList();
                
                for (var doc in allomasDocs) {
                  final data = doc.data();
                  final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();
                  
                  if (tags.isNotEmpty) {
                    final firstTag = tags[0];
                    allomasTagMap.putIfAbsent(firstTag, () => []);
                    allomasTagMap[firstTag]!.add(doc);
                  }
                }
              }
              
              // Összevonjuk a három tag map-et
              final allTags = <String>{};
              allTags.addAll(tagMap.keys);
              allTags.addAll(jogesetTagMap.keys);
              allTags.addAll(allomasTagMap.keys);
              
              if (allTags.isEmpty && allDocs.isEmpty) {
                return const Center(child: Text('Nincs találat.'));
              }

              // Rendezés
              final sortedTags = allTags.toList()..sort();

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ...sortedTags.map((tag) {
                    // Összevonjuk a notes, jogeset és állomás dokumentumokat
                    final notesDocs = tagMap[tag] ?? [];
                    final jogesetDocs = jogesetTagMap[tag] ?? [];
                    final allomasDocs = allomasTagMap[tag] ?? [];
                    final totalCount = notesDocs.length + jogesetDocs.length + allomasDocs.length;
                    
                    // Ellenőrizzük, van-e mélyebb szintű címke
                    final hasDeepTags = notesDocs.any((doc) {
                          final tags = (doc.data()['tags'] as List<dynamic>? ?? []).cast<String>();
                          return tags.length > 1;
                        }) ||
                        jogesetDocs.any((doc) {
                          final data = doc.data();
                          final jogesetekList = data['jogesetek'] as List<dynamic>? ?? [];
                          if (jogesetekList.isEmpty) return false;
                          final firstJogeset = jogesetekList.first as Map<String, dynamic>;
                          final tags = (firstJogeset['tags'] as List<dynamic>? ?? []).cast<String>();
                          return tags.length > 1;
                        }) ||
                        allomasDocs.any((doc) {
                          final tags = (doc.data()['tags'] as List<dynamic>? ?? []).cast<String>();
                          return tags.length > 1;
                        });
                    
                    return _buildTagCard(tag, notesDocs, jogesetDocs, allomasDocs, totalCount, hasDeepTags);
                  }),
                ],
              );
                  },
                );
              },
            );
              },
            ),
    );
  }

  /// Firestore lekérdezés építése notes kollekcióhoz
  Query<Map<String, dynamic>> _buildQuery() {
    final userScience = AccessControl.getUserScience();
    Query<Map<String, dynamic>> query = FirebaseConfig.firestore
        .collection('notes')
        .where('science', isEqualTo: userScience)
        .where('category', isEqualTo: widget.category);

    return query;
  }

  /// Firestore lekérdezés építése dialogus_fajlok kollekcióhoz
  Query<Map<String, dynamic>> _buildDialogusFajlokQuery() {
    final userScience = AccessControl.getUserScience();
    Query<Map<String, dynamic>> query = FirebaseConfig.firestore
        .collection('dialogus_fajlok')
        .where('science', isEqualTo: userScience);
    
    // Státusz szűrés kliens oldalon történik (admin/nem-admin különbség miatt)
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

  /// Firestore lekérdezés építése memoriapalota_allomasok kollekcióhoz
  Query<Map<String, dynamic>> _buildAllomasQuery() {
    final userScience = AccessControl.getUserScience();
    // Itt is szűrünk kategóriára, mert az állomásoknak van kategóriája
    Query<Map<String, dynamic>> query = FirebaseConfig.firestore
        .collection('memoriapalota_allomasok')
        .where('science', isEqualTo: userScience)
        .where('category', isEqualTo: widget.category);

    return query;
  }

  /// Jogeset dokumentumok feldolgozása és kliens oldali szűrése
  /// Dokumentumonként kezeli a jogeseteket, nem külön jogesetenként
  /// Visszaadja a dokumentumokat az első jogeset metaadataival és a jogesetek számával
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _processJogesetDocuments(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      {bool isAdmin = false}) {
    final processedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (var doc in docs) {
      final data = doc.data();
      final jogesetekList = data['jogesetek'] as List<dynamic>? ?? [];

      // Szűrjük a jogeseteket kategória és státusz alapján
      final matchingJogesetek = <Map<String, dynamic>>[];
      
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

        matchingJogesetek.add(jogeset);
      }

      // Ha van legalább egy megfelelő jogeset, hozzáadjuk a dokumentumot
      if (matchingJogesetek.isNotEmpty) {
        processedDocs.add(doc);
      }
    }

    return processedDocs;
  }

  /// Címke kártya widget építése
  Widget _buildTagCard(
      String tag,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> notesDocs,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> jogesetDocs,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allomasDocs,
      int totalCount,
      bool hasDeepTags) {

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
        onTap: () => _navigateToTagDrillDown(context, tag),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                hasDeepTags ? Icons.folder : Icons.label,
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

  /// Kategória kártya widget építése (Dialogus tags esetén)
  Widget _buildCategoryCard(
      String category,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
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
        onTap: () {
          // Navigálás a TagDrillDownScreen-re, de a category paraméter "Dialogus tags" marad
          // és a tagPath tartalmazza a kategóriát
          final screen = TagDrillDownScreen(
            category: 'Dialogus tags',
            tagPath: [category],
          );

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
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.folder,
                color: Color(0xFF3366CC),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  category,
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
}
