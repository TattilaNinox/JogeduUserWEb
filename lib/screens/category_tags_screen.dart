import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
import '../widgets/note_list_tile.dart';
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

    if (!kIsWeb && Platform.isIOS) {
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
    if (user == null)
      return const Scaffold(
          body: Center(child: Text('Kérjük, jelentkezzen be.')));

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
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData)
            return const Center(child: CircularProgressIndicator());

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
              .where('category', isEqualTo: widget.category);

          if (isAdmin) {
            notesQuery = notesQuery
                .where('status', whereIn: const ['Published', 'Draft']);
          } else {
            notesQuery = notesQuery.where('status', isEqualTo: 'Published');
          }

          Query<Map<String, dynamic>> jogesetQuery =
              FirebaseConfig.firestore.collection('jogesetek');

          Query<Map<String, dynamic>> allomasQuery = FirebaseConfig.firestore
              .collection('memoriapalota_allomasok')
              .where('science', isEqualTo: science)
              .where('category', isEqualTo: widget.category);

          if (isAdmin) {
            allomasQuery = allomasQuery
                .where('status', whereIn: const ['Published', 'Draft']);
          } else {
            allomasQuery = allomasQuery.where('status', isEqualTo: 'Published');
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
                      final dialogusStream =
                          dialogusQuery?.snapshots() ?? const Stream.empty();
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: dialogusStream,
                        builder: (context, dSnap) {
                          if (notesSnap.hasError)
                            return Center(
                                child: Text('Hiba: ${notesSnap.error}'));

                          final allDocs =
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                          if (notesSnap.hasData)
                            allDocs.addAll(notesSnap.data!.docs
                                .where((d) => d.data()['deletedAt'] == null));
                          if (allomasSnap.hasData)
                            allDocs.addAll(allomasSnap.data!.docs
                                .where((d) => d.data()['deletedAt'] == null));

                          final tagMap = <String,
                              List<
                                  QueryDocumentSnapshot<
                                      Map<String, dynamic>>>>{};
                          final directDocs =
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                          for (var doc in allDocs) {
                            final tags =
                                (doc.data()['tags'] as List<dynamic>? ?? [])
                                    .cast<String>();
                            if (tags.isNotEmpty) {
                              tagMap.putIfAbsent(tags[0], () => []).add(doc);
                            } else {
                              directDocs.add(doc);
                            }
                          }

                          if (jogesetSnap.hasData) {
                            for (var doc in jogesetSnap.data!.docs) {
                              if (doc.data()['deletedAt'] != null) continue;
                              final jogesetekList =
                                  doc.data()['jogesetek'] as List? ?? [];
                              for (var jogesetData in jogesetekList) {
                                final jogeset =
                                    jogesetData as Map<String, dynamic>;
                                if (jogeset['category'] != widget.category)
                                  continue;
                                final status =
                                    jogeset['status'] as String? ?? 'Draft';
                                if (!isAdmin && status != 'Published') continue;
                                final tags = (jogeset['tags'] as List? ?? [])
                                    .cast<String>();
                                if (tags.isNotEmpty) {
                                  tagMap
                                      .putIfAbsent(tags[0], () => [])
                                      .add(doc);
                                } else {
                                  directDocs.add(doc);
                                }
                              }
                            }
                          }

                          if (widget.category == 'Dialogus tags' &&
                              dSnap.hasData) {
                            for (var doc in dSnap.data!.docs) {
                              if (doc.data()['deletedAt'] != null) continue;
                              final data = doc.data();
                              final status =
                                  data['status'] as String? ?? 'Draft';
                              if (!isAdmin && status != 'Published') continue;
                              final audioUrl = data['audioUrl'] as String?;
                              if (audioUrl == null || audioUrl.isEmpty)
                                continue;
                              tagMap
                                  .putIfAbsent(
                                      data['category'] ?? 'Egyéb', () => [])
                                  .add(doc);
                            }
                          }

                          if (tagMap.isEmpty && directDocs.isEmpty) {
                            if (!notesSnap.hasData && !allomasSnap.hasData)
                              return const Center(
                                  child: CircularProgressIndicator());
                            return const Center(
                                child: Text('Nincs megjeleníthető tartalom.'));
                          }

                          final sortedTags = tagMap.keys.toList()..sort();

                          return ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              ...sortedTags.map((tag) {
                                final docs = tagMap[tag]!;
                                final hasDeepTags = docs.any((doc) {
                                  if (doc.reference.path
                                      .contains('jogesetek')) {
                                    final list =
                                        doc.data()['jogesetek'] as List? ?? [];
                                    return list.any(
                                        (j) => (j['tags'] as List).length > 1);
                                  }
                                  return (doc.data()['tags'] as List? ?? [])
                                          .length >
                                      1;
                                });
                                return _buildTagCard(
                                    tag, docs.length, hasDeepTags);
                              }),
                              if (directDocs.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                                  child: Text('Egyéb jegyzetek',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey)),
                                ),
                                ...directDocs.map((doc) =>
                                    _buildDirectNoteWidget(doc, isAdmin)),
                              ],
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

  Widget _buildTagCard(String tag, int count, bool hasDeep) {
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
              Icon(hasDeep ? Icons.folder : Icons.label,
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

    bool isFree = data['isFree'] as bool? ?? false;
    int? jogesetCount;

    if (isJogeset) {
      final list = data['jogesetek'] as List? ?? [];
      final first = list.isNotEmpty ? list[0] as Map<String, dynamic> : {};
      title = (data['title'] ?? first['title'] ?? first['cim'] ?? 'Jogeset')
          .toString();
      isFree = first['isFree'] == true;
      jogesetCount = list.length;
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
