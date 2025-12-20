import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

          // Összegyűjtjük a tags[0] címkéket
          final tagMap =
              <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

          for (var doc in docs) {
            final data = doc.data();
            final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();

            if (tags.isNotEmpty) {
              final firstTag = tags[0];
              tagMap.putIfAbsent(firstTag, () => []);
              tagMap[firstTag]!.add(doc);
            }
          }

          // Rendezés
          final sortedTags = tagMap.keys.toList()..sort();

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ...sortedTags.map((tag) => _buildTagCard(tag, tagMap[tag]!)),
            ],
          );
        },
      ),
    );
  }

  /// Firestore lekérdezés építése
  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseConfig.firestore
        .collection('notes')
        .where('science', isEqualTo: 'Jogász')
        .where('category', isEqualTo: widget.category);

    return query;
  }

  /// Címke kártya widget építése
  Widget _buildTagCard(
      String tag, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // Számoljuk meg, hány jegyzet van összesen ebben a címkében (beleértve az alcímkéket is)
    final noteCount = docs.length;

    // Ellenőrizzük, van-e mélyebb szintű címke
    final hasDeepTags = docs.any((doc) {
      final tags = (doc.data()['tags'] as List<dynamic>? ?? []).cast<String>();
      return tags.length > 1;
    });

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
                '$noteCount',
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
