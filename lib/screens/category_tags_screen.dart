import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
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
              final isAdmin = user?.email == 'tattila.ninox@gmail.com'; // Egyszerűsített admin ellenőrzés
              
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
              
              // Összevonjuk a két tag map-et
              final allTags = <String>{};
              allTags.addAll(tagMap.keys);
              allTags.addAll(jogesetTagMap.keys);
              
              if (allTags.isEmpty && allDocs.isEmpty) {
                return const Center(child: Text('Nincs találat.'));
              }

              // Rendezés
              final sortedTags = allTags.toList()..sort();

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ...sortedTags.map((tag) {
                    // Összevonjuk a notes és jogeset dokumentumokat
                    final notesDocs = tagMap[tag] ?? [];
                    final jogesetDocs = jogesetTagMap[tag] ?? [];
                    final totalCount = notesDocs.length + jogesetDocs.length;
                    
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
                        });
                    
                    return _buildTagCard(tag, notesDocs, jogesetDocs, totalCount, hasDeepTags);
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Firestore lekérdezés építése notes kollekcióhoz
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
}
