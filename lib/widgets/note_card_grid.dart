import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../core/firebase_config.dart';
import '../services/auth_service.dart';
import '../screens/category_tags_screen.dart';
import '../screens/tag_drill_down_screen.dart';
import '../widgets/note_list_tile.dart';
import '../utils/string_utils.dart';

class NoteCardGrid extends StatefulWidget {
  final String searchText;
  final String? selectedStatus;
  final String? selectedCategory;
  final String? selectedScience;
  final String? selectedTag;
  final String? selectedType;

  const NoteCardGrid({
    super.key,
    required this.searchText,
    this.selectedStatus,
    this.selectedCategory,
    this.selectedScience,
    this.selectedTag,
    this.selectedType,
  });

  @override
  State<NoteCardGrid> createState() => _NoteCardGridState();
}

class _NoteCardGridState extends State<NoteCardGrid> {
  // Pagination state variables
  int _currentLimit = 25; // Start with 25 notes
  bool _isLoadingMore = false; // Loading state for "Load More" button

  final _authService = AuthService();

  /// Load more notes by increasing the limit
  void _loadMore() {
    if (_isLoadingMore) return;

    setState(() {
      _currentLimit += 25; // Increase by 25 notes
      _isLoadingMore = true;
    });

    // StreamBuilder will automatically re-query with new limit
    // After rebuild, _isLoadingMore will be set to false
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _authService.isAdmin(),
        _authService.hasPremiumAccess(),
      ]),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final bool isAdmin = authSnapshot.data?[0] ?? false;
        final bool hasPremiumAccess = authSnapshot.data?[1] ?? false;

        // FIX: Webalkalmazásban MINDIG csak "Jogász" tudományág
        const userScience = 'Jogász';

        Query<Map<String, dynamic>> query =
            FirebaseConfig.firestore.collection('notes');

        // KÖTELEZŐ: Csak "Jogász" tudományágú jegyzetek
        query = query.where('science', isEqualTo: userScience);

        // Keresés állapotának meghatározása
        final bool isSearching = widget.searchText.trim().isNotEmpty;
        final int queryLimit = isSearching ? 1000 : _currentLimit + 1;

        // FREEMIUM MODEL: Minden jegyzet látszik, de a zártak nem nyithatók meg
        // Nem szűrünk isFree alapján, hogy a prémium jegyzetek is látszódjanak

        // Státusz szűrés: admin esetén Draft jegyzeteket is mutatunk
        if (widget.selectedStatus != null &&
            widget.selectedStatus!.isNotEmpty) {
          // Ha van kiválasztott státusz, azt használjuk
          query = query.where('status', isEqualTo: widget.selectedStatus);
        } else {
          // Ha nincs kiválasztott státusz, alapértelmezett szűrés
          if (isAdmin) {
            // Admin esetén Published és Draft jegyzeteket mutatunk
            query = query.where('status', whereIn: ['Published', 'Draft']);
            if (kDebugMode) {
              debugPrint(
                  '[NoteCardGrid] Admin query - showing Published and Draft notes');
            }
          } else {
            // Nem admin csak Published jegyzeteket lát
            query = query.where('status', isEqualTo: 'Published');
            if (kDebugMode) {
              debugPrint(
                  '[NoteCardGrid] Non-admin query - showing only Published notes');
            }
          }
        }
        if (widget.selectedCategory != null &&
            widget.selectedCategory!.isNotEmpty) {
          query = query.where('category', isEqualTo: widget.selectedCategory);
        }
        // selectedScience szűrő NEM kell, mert már a userScience alapján szűrünk
        if (widget.selectedTag != null && widget.selectedTag!.isNotEmpty) {
          query = query.where('tags', arrayContains: widget.selectedTag);
        }
        if (widget.selectedType != null && widget.selectedType!.isNotEmpty) {
          query = query.where('type', isEqualTo: widget.selectedType);
        }

        // Pagination: Add ordering by title (ABC) and limit
        query = query.orderBy('title').limit(queryLimit);

        // Debug: lekérdezés paraméterek
        if (kDebugMode) {
          debugPrint(
              '[NoteCardGrid] Query params - science: $userScience, status: ${isAdmin ? "Published/Draft" : "Published"}, type: ${widget.selectedType ?? "all"}');
        }

        // Ha nincs típus szűrő, vagy ha a típus szűrő "memoriapalota_allomasok", betöltjük a fő útvonal dokumentumokat
        final shouldLoadAllomasok = widget.selectedType == null ||
            widget.selectedType!.isEmpty ||
            widget.selectedType == 'memoriapalota_allomasok';

        // Ha nincs típus szűrő, vagy ha a típus szűrő "dialogus_fajlok", betöltjük a dialogus fájl dokumentumokat
        final shouldLoadDialogus = widget.selectedType == null ||
            widget.selectedType!.isEmpty ||
            widget.selectedType == 'dialogus_fajlok';

        // Fő útvonal dokumentumok lekérdezése a memoriapalota_allomasok kollekcióból
        // Ezek a fő dokumentumok, amelyek az utvonalId-val rendelkeznek
        Query<Map<String, dynamic>>? allomasQuery = shouldLoadAllomasok
            ? FirebaseConfig.firestore
                .collection('memoriapalota_allomasok')
                .where('science', isEqualTo: userScience)
            : null;

        // Dialogus fájl dokumentumok lekérdezése a dialogus_fajlok kollekcióból
        Query<Map<String, dynamic>>? dialogusQuery = shouldLoadDialogus
            ? FirebaseConfig.firestore
                .collection('dialogus_fajlok')
                .where('science', isEqualTo: userScience)
            : null;

        // ÚJ: Jogesetek lekérdezése a jogesetek kollekcióból
        // Ha nincs típus szűrő, vagy ha a típus szűrő "jogeset", betöltjük a jogeseteket
        final shouldLoadJogeset = widget.selectedType == null ||
            widget.selectedType!.isEmpty ||
            widget.selectedType == 'jogeset';

        Query<Map<String, dynamic>>? jogesetQuery = shouldLoadJogeset
            ? FirebaseConfig.firestore
                .collection('jogesetek')
                .where('science', isEqualTo: userScience)
            : null;

        if (allomasQuery != null) {
          // category
          if (widget.selectedCategory != null &&
              widget.selectedCategory!.isNotEmpty) {
            allomasQuery = allomasQuery.where('category',
                isEqualTo: widget.selectedCategory);
          }

          // status
          if (widget.selectedStatus != null &&
              widget.selectedStatus!.isNotEmpty) {
            allomasQuery =
                allomasQuery.where('status', isEqualTo: widget.selectedStatus);
          } else {
            allomasQuery = isAdmin
                ? allomasQuery.where('status', whereIn: ['Published', 'Draft'])
                : allomasQuery.where('status', isEqualTo: 'Published');
          }
          // tag
          if (widget.selectedTag != null && widget.selectedTag!.isNotEmpty) {
            allomasQuery =
                allomasQuery.where('tags', arrayContains: widget.selectedTag);
          }

          // Pagination: Add ordering by title (ABC) and limit
          allomasQuery = allomasQuery.orderBy('title').limit(queryLimit);
        }

        if (dialogusQuery != null) {
          // status
          if (widget.selectedStatus != null &&
              widget.selectedStatus!.isNotEmpty) {
            dialogusQuery =
                dialogusQuery.where('status', isEqualTo: widget.selectedStatus);
          } else {
            dialogusQuery = isAdmin
                ? dialogusQuery.where('status', whereIn: ['Published', 'Draft'])
                : dialogusQuery.where('status', isEqualTo: 'Published');
          }
          // tag
          // FONTOS: Firestore nem támogatja több array-contains szűrőt,
          // és a dialogus_fajlok dokumentumoknak category és tags mezője is van
          if (widget.selectedTag != null && widget.selectedTag!.isNotEmpty) {
            dialogusQuery =
                dialogusQuery.where('tags', arrayContains: widget.selectedTag);
          }

          // Pagination: Add ordering by title (ABC) and limit
          dialogusQuery = dialogusQuery.orderBy('title').limit(queryLimit);
        }

        if (jogesetQuery != null) {
          // category
          if (widget.selectedCategory != null &&
              widget.selectedCategory!.isNotEmpty) {
            jogesetQuery = jogesetQuery.where('category',
                isEqualTo: widget.selectedCategory);
          }

          // status
          if (widget.selectedStatus != null &&
              widget.selectedStatus!.isNotEmpty) {
            jogesetQuery =
                jogesetQuery.where('status', isEqualTo: widget.selectedStatus);
          } else {
            if (isAdmin) {
              jogesetQuery = jogesetQuery.where('status',
                  whereIn: const ['Published', 'Public', 'Draft']);
            } else {
              jogesetQuery = jogesetQuery
                  .where('status', whereIn: const ['Published', 'Public']);
            }
          }

          // tag
          if (widget.selectedTag != null && widget.selectedTag!.isNotEmpty) {
            jogesetQuery =
                jogesetQuery.where('tags', arrayContains: widget.selectedTag);
          }

          // Pagination: Add ordering by title (ABC) and limit
          // A jogeseteknél a documentId a "cím", és az index is __name__ alapú
          jogesetQuery =
              jogesetQuery.orderBy(FieldPath.documentId).limit(queryLimit);
        }

        // Create a unique key for the combined query to help FutureBuilder
        final compositeFutureKey =
            'notes|limit=$queryLimit|isAdmin=$isAdmin|science=$userScience|status=${widget.selectedStatus ?? ""}|cat=${widget.selectedCategory ?? ""}|tag=${widget.selectedTag ?? ""}|type=${widget.selectedType ?? ""}|search=${widget.searchText}';

        return FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
          key: ValueKey(compositeFutureKey),
          future: Future.wait([
            query.get(),
            if (allomasQuery != null)
              allomasQuery.get()
            else
              Future.value(null),
            if (dialogusQuery != null)
              dialogusQuery.get()
            else
              Future.value(null),
            if (jogesetQuery != null)
              jogesetQuery.get()
            else
              Future.value(null),
          ].whereType<Future<QuerySnapshot<Map<String, dynamic>>>>()),
          builder: (context, snapshots) {
            if (snapshots.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshots.hasError) {
              return Center(
                  child:
                      Text('Hiba az adatok betöltésekor: ${snapshots.error}'));
            }

            final results = snapshots.data!;
            final snapshot = results[0];

            int idx = 1;
            final allomasSnapshot = shouldLoadAllomasok ? results[idx++] : null;
            final dialogusSnapshot = shouldLoadDialogus ? results[idx++] : null;
            final jogesetSnapshot = shouldLoadJogeset ? results[idx++] : null;

            // Debug: találatok száma
            final docs = snapshot.docs;
            if (kDebugMode) {
              debugPrint('[NoteCardGrid] Found ${docs.length} notes');
            }
            // Debug: típusok listája
            final types = docs
                .map((d) => d.data()['type'] as String? ?? 'unknown')
                .toSet();
            if (kDebugMode) {
              debugPrint('[NoteCardGrid] Note types found: $types');
            }

            if (allomasSnapshot != null && kDebugMode) {
              debugPrint(
                  '[NoteCardGrid] Found ${allomasSnapshot.docs.length} allomasok');
            }
            if (dialogusSnapshot != null && kDebugMode) {
              debugPrint(
                  '[NoteCardGrid] Found ${dialogusSnapshot.docs.length} dialogus_fajlok');
            }
            if (jogesetSnapshot != null && kDebugMode) {
              debugPrint(
                  '🔵 [NoteCardGrid] Found ${jogesetSnapshot.docs.length} jogesetek in collection');
            }

            // Összegyűjtjük a notes dokumentumokat
            final notesDocs = docs
                .where((d) => !(d.data()['deletedAt'] != null))
                .where((d) => (d.data()['title'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(widget.searchText.toLowerCase()))
                .toList();

            // Összefésüljük a két listát
            // A fő útvonal dokumentumokat hozzáadjuk, de virtuálisan hozzáadjuk a type mezőt
            final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            allDocs.addAll(notesDocs);

            // Fő útvonal dokumentumok hozzáadása - csak akkor, ha nincs típus szűrő vagy az állomások típusa van kiválasztva
            if (shouldLoadAllomasok && allomasSnapshot != null) {
              final allomasDocs = allomasSnapshot.docs.where((d) {
                final data = d.data();
                // Szűrés cím alapján (cim mező)
                final cim = (data['cim'] ?? '').toString();
                return cim
                    .toLowerCase()
                    .contains(widget.searchText.toLowerCase());
              }).toList();
              allDocs.addAll(allomasDocs);
            }

            // Dialogus fájl dokumentumok hozzáadása
            if (shouldLoadDialogus && dialogusSnapshot != null) {
              final dialogusDocs = dialogusSnapshot.docs.where((d) {
                final data = d.data();

                // Szűrés cím alapján (title vagy cim mező)
                final title = (data['title'] ?? data['cim'] ?? '').toString();
                return title
                    .toLowerCase()
                    .contains(widget.searchText.toLowerCase());
              }).toList();
              allDocs.addAll(dialogusDocs);
            }

            // Jogesetek hozzáadása
            if (shouldLoadJogeset && jogesetSnapshot != null) {
              final jogesetDocs = jogesetSnapshot.docs.where((d) {
                final data = d.data();
                // Szűrés cím alapján (title mező VAGY ID)
                final title = (data['title'] ?? d.id).toString();
                return title
                    .toLowerCase()
                    .contains(widget.searchText.toLowerCase());
              }).toList();
              allDocs.addAll(jogesetDocs);
            }

            // Típus szűrés
            final filteredDocs = widget.selectedType != null &&
                    widget.selectedType!.isNotEmpty
                ? allDocs.where((d) {
                    final data = d.data();
                    // A fő útvonal dokumentumok a memoriapalota_allomasok kollekcióból jönnek
                    if (d.reference.path.contains('memoriapalota_allomasok') &&
                        !d.reference.path.contains('/allomasok/')) {
                      return widget.selectedType == 'memoriapalota_allomasok';
                    }
                    // A dialogus fájl dokumentumok a dialogus_fajlok kollekcióból jönnek
                    if (d.reference.path.contains('dialogus_fajlok')) {
                      return widget.selectedType == 'dialogus_fajlok';
                    }
                    // A jogesetek a jogesetek kollekcióból jönnek
                    if (d.reference.path.contains('jogesetek')) {
                      return widget.selectedType == 'jogeset';
                    }
                    return data['type'] == widget.selectedType;
                  }).toList()
                : allDocs;

            final docsResult = filteredDocs;

            // Hibajavítás: A hasMore akkor igaz, ha több találatunk van, mint a jelenlegi limit
            final bool hasMore =
                !isSearching && docsResult.length > _currentLimit;

            // Hibajavítás: Csak a limitnek megfelelő mennyiségű elemet mutatunk
            final displayedDocs = isSearching
                ? docsResult
                : docsResult.take(_currentLimit).toList();

            final totalCount = displayedDocs.length;

            if (docsResult.isEmpty) {
              return const Center(child: Text('Nincs találat.'));
            }

            // Hierarchikus csoportosítás: Kategória → Címkék hierarchia (tudomány szint nélkül, mert csak "Jogász" van)
            // A címkék hierarchikusan működnek: tags[0] = főcím, tags[1] = alcím, tags[2] = alcím az alcím alatt, stb.
            // Map<category, Map<firstTag, Map<secondTag, Map<thirdTag, ...>>>>
            final Map<String, Map<String, dynamic>> hierarchical = {};

            for (var d in displayedDocs) {
              // Ha dialogus_fajlok dokumentum, akkor a kategória mindig "Dialogus tags"
              // Ez biztosítja, hogy külön mappába kerüljenek
              final isDialogusFajl =
                  d.reference.path.contains('dialogus_fajlok');

              final category = isDialogusFajl
                  ? 'Dialogus tags'
                  : (d.data()['category'] ?? 'Egyéb') as String;

              final tags =
                  (d.data()['tags'] as List<dynamic>? ?? []).cast<String>();

              hierarchical.putIfAbsent(category, () => {});

              // Címkék hierarchikus csoportosítása
              if (tags.isEmpty) {
                hierarchical[category]!
                    .putIfAbsent('Nincs címke',
                        () => <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .add(d);
              } else {
                // A címkék sorrendje fontos: tags[0] = főcím, tags[1] = alcím, stb.
                // Hierarchikusan építjük fel: category -> tags[0] -> tags[1] -> tags[2] -> ... -> docs
                Map<String, dynamic> current = hierarchical[category]!;

                for (int i = 0; i < tags.length; i++) {
                  final tag = tags[i];
                  final isLast = i == tags.length - 1;

                  if (isLast) {
                    // Ha ez az utolsó címke, akkor itt vannak a jegyzetek
                    // Ha már létezik ez a kulcs és Map típusú, akkor az üres kulcs alá tesszük
                    if (current.containsKey(tag)) {
                      if (current[tag] is Map<String, dynamic>) {
                        // Ha már Map van, akkor az üres kulcs alá tesszük a jegyzetet
                        final map = current[tag] as Map<String, dynamic>;
                        if (!map.containsKey('')) {
                          map[''] =
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                        }
                        (map[''] as List<
                                QueryDocumentSnapshot<Map<String, dynamic>>>)
                            .add(d);
                      } else {
                        // Ha lista van, akkor hozzáadjuk
                        (current[tag] as List<
                                QueryDocumentSnapshot<Map<String, dynamic>>>)
                            .add(d);
                      }
                    } else {
                      // Ha nem létezik, akkor létrehozzuk listaként
                      current[tag] =
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[d];
                    }
                  } else {
                    // Ha nem az utolsó, akkor egy köztes szint
                    if (!current.containsKey(tag)) {
                      current[tag] = <String, dynamic>{};
                    } else if (current[tag] is! Map) {
                      // Ha véletlenül lista van, átalakítjuk Map-pé és összefésüljük
                      final existingDocs = current[tag]
                          as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
                      current[tag] = <String, dynamic>{'': existingDocs};
                    }
                    current = current[tag] as Map<String, dynamic>;
                  }
                }
              }
            }

            // Rendezés minden szinten - rekurzívan
            void sortDocs(Map<String, dynamic> level) {
              level.forEach((key, value) {
                if (value
                    is List<QueryDocumentSnapshot<Map<String, dynamic>>>) {
                  value.sort((a, b) {
                    // Fő útvonal dokumentumok típusának meghatározása (nem subcollection)
                    final isAllomasA =
                        a.reference.path.contains('memoriapalota_allomasok') &&
                            !a.reference.path.contains('/allomasok/');
                    final isAllomasB =
                        b.reference.path.contains('memoriapalota_allomasok') &&
                            !b.reference.path.contains('/allomasok/');
                    final isDialogusA =
                        a.reference.path.contains('dialogus_fajlok');
                    final isDialogusB =
                        b.reference.path.contains('dialogus_fajlok');
                    final isJogesetA = a.reference.path.contains('jogesetek');
                    final isJogesetB = b.reference.path.contains('jogesetek');

                    final typeA = isAllomasA
                        ? 'memoriapalota_allomasok'
                        : (isDialogusA
                            ? 'dialogus_fajlok'
                            : (isJogesetA
                                ? 'jogeset'
                                : (a.data()['type'] as String? ?? '')));
                    final typeB = isAllomasB
                        ? 'memoriapalota_allomasok'
                        : (isDialogusB
                            ? 'dialogus_fajlok'
                            : (isJogesetB
                                ? 'jogeset'
                                : (b.data()['type'] as String? ?? '')));

                    final bool isSourceA = typeA == 'source';
                    final bool isSourceB = typeB == 'source';
                    if (isSourceA != isSourceB) {
                      return isSourceA ? 1 : -1;
                    }

                    final titleA = (isJogesetA
                        ? (a.data()['title'] ?? a.id).toString()
                        : (isAllomasA || isDialogusA
                            ? (a.data()['title'] ?? a.data()['cim'] ?? '')
                                .toString()
                            : (a.data()['title'] as String? ?? '')));
                    final titleB = (isJogesetB
                        ? (b.data()['title'] ?? b.id).toString()
                        : (isAllomasB || isDialogusB
                            ? (b.data()['title'] ?? b.data()['cim'] ?? '')
                                .toString()
                            : (b.data()['title'] as String? ?? '')));
                    return StringUtils.naturalCompare(titleA, titleB);
                  });
                } else if (value is Map<String, dynamic>) {
                  sortDocs(value);
                }
              });
            }

            hierarchical.forEach((category, tags) {
              sortDocs(tags);
            });

            final bool skipCategoryWrapper = widget.selectedCategory != null &&
                widget.selectedCategory!.isNotEmpty &&
                hierarchical.containsKey(widget.selectedCategory);

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              children: [
                if (skipCategoryWrapper)
                  // Közvetlenül a szint elemeit jelenítjük meg, kategória fejléc/mappa nélkül
                  ..._buildHierarchyItems(
                      context, hierarchical[widget.selectedCategory!]!,
                      category: widget.selectedCategory!,
                      hasPremiumAccess: hasPremiumAccess)
                else
                  ...(hierarchical.entries.toList()
                        ..sort(
                            (a, b) => StringUtils.naturalCompare(a.key, b.key)))
                      .map((categoryEntry) {
                    return _CategorySection(
                      key: ValueKey('category_${categoryEntry.key}'),
                      category: categoryEntry.key,
                      tagHierarchy: categoryEntry.value,
                      selectedCategory: widget.selectedCategory,
                      selectedTag: widget.selectedTag,
                      hasPremiumAccess: hasPremiumAccess,
                    );
                  }),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: _isLoadingMore
                        ? const CircularProgressIndicator()
                        : hasMore
                            ? ElevatedButton.icon(
                                onPressed: _loadMore,
                                icon: const Icon(Icons.expand_more),
                                label: Text(
                                  'További dokumentumok betöltése',
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 32, vertical: 16),
                                ),
                              )
                            : Text(
                                'Minden dokumentum betöltve ($totalCount dokumentum)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: MediaQuery.of(context).size.width <
                                          600
                                      ? 12
                                      : null, // Mobil nézetben 2px-el kisebb (alap 14px -> 12px)
                                ),
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

  List<Widget> _buildHierarchyItems(
    BuildContext context,
    Map<String, dynamic> hierarchy, {
    required String category,
    required bool hasPremiumAccess,
  }) {
    final List<dynamic> unifiedList = [];
    if (hierarchy.containsKey('Nincs címke')) {
      unifiedList.addAll(hierarchy['Nincs címke']);
    }

    final tags =
        hierarchy.entries.where((e) => e.key != 'Nincs címke').toList();
    unifiedList.addAll(tags);

    unifiedList.sort((a, b) {
      String titleA;
      if (a is MapEntry<String, dynamic>) {
        titleA = a.key;
      } else {
        final docA = a as QueryDocumentSnapshot<Map<String, dynamic>>;
        titleA = (docA.reference.path.contains('jogesetek')
                ? (docA.data()['title'] ?? docA.id)
                : (docA.data()['title'] ?? docA.data()['cim'] ?? 'Névtelen'))
            .toString();
      }
      String titleB;
      if (b is MapEntry<String, dynamic>) {
        titleB = b.key;
      } else {
        final docB = b as QueryDocumentSnapshot<Map<String, dynamic>>;
        titleB = (docB.reference.path.contains('jogesetek')
                ? (docB.data()['title'] ?? docB.id)
                : (docB.data()['title'] ?? docB.data()['cim'] ?? 'Névtelen'))
            .toString();
      }
      return StringUtils.naturalCompare(titleA, titleB);
    });

    return unifiedList.map((item) {
      if (item is MapEntry<String, dynamic>) {
        final tag = item.key;
        final data = item.value;
        final count = data is List
            ? data.length
            : (data is Map ? (data['docs'] as List? ?? []).length : 0);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade200)),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TagDrillDownScreen(
                    category: category,
                    tagPath: [tag],
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(item.value is Map ? Icons.folder : Icons.label,
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
      } else {
        final doc = item as QueryDocumentSnapshot<Map<String, dynamic>>;
        final data = doc.data();
        final isMP = doc.reference.path.contains('memoriapalota_allomasok');
        final isDialogus = doc.reference.path.contains('dialogus_fajlok');
        final isJogeset = doc.reference.path.contains('jogesetek');

        String title =
            (data['title'] ?? data['name'] ?? data['cim'] ?? 'Névtelen')
                .toString();
        String type = isMP
            ? 'memoriapalota_allomasok'
            : (isDialogus
                ? 'dialogus_fajlok'
                : (isJogeset ? 'jogeset' : (data['type'] as String? ?? '')));

        bool isFree = (data['isFree'] == true) ||
            (data['is_free'] == true) ||
            (data['isFree'] == 1) ||
            (data['is_free'] == 1);
        int? jogesetCount;
        if (isJogeset) {
          title = (data['title'] ?? 'Jogeset').toString();
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
          deckCount: type == 'deck'
              ? (data['flashcards'] as List? ?? []).length
              : null,
          isLocked: !isFree && !hasPremiumAccess,
          jogesetCount: jogesetCount,
          category: category,
          customFromUrl: '/notes',
        );
      }
    }).toList();
  }
}

// Kategória szintű szekció widget
class _CategorySection extends StatefulWidget {
  final String category;
  final Map<String, dynamic> tagHierarchy;
  final String? selectedCategory;
  final String? selectedTag;
  final bool hasPremiumAccess;

  const _CategorySection({
    super.key,
    required this.category,
    required this.tagHierarchy,
    this.selectedCategory,
    this.selectedTag,
    required this.hasPremiumAccess,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  /// Összegyűjti az összes jegyzetet a hierarchiából
  int _countTotalDocs(Map<String, dynamic> hierarchy) {
    int count = 0;
    for (var value in hierarchy.values) {
      if (value is List) {
        count += value.length;
      } else if (value is Map) {
        count += _countTotalDocs(value as Map<String, dynamic>);
      }
    }
    return count;
  }

  /// Platform-natív navigáció a CategoryTagsScreen-re
  void _navigateToCategoryTags(BuildContext context) {
    // Ha a főoldalon van aktív "Címke" szűrő, akkor a kategóriába belépéskor
    // közvetlenül a címke drill-down nézetet nyissuk meg, különben úgy tűnik,
    // mintha a szűrő nem működne (mert a CategoryTagsScreen minden tags[0]-t listáz).
    final selectedTag = widget.selectedTag;
    final Widget screen = (selectedTag != null && selectedTag.isNotEmpty)
        ? TagDrillDownScreen(
            category: widget.category,
            tagPath: [selectedTag],
          )
        : CategoryTagsScreen(category: widget.category);

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

  @override
  Widget build(BuildContext context) {
    final totalDocs = _countTotalDocs(widget.tagHierarchy);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _navigateToCategoryTags(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                color: Color(0xFF1976D2),
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.category,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF202122),
                  ),
                ),
              ),
              Text(
                '$totalDocs',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade400,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
