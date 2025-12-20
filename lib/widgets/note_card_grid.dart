import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../core/firebase_config.dart';
import '../screens/category_tags_screen.dart';

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
  bool _checkPremiumAccess(Map<String, dynamic> userData) {
    // Próbaidő ellenőrzése
    final trialEndDate = userData['freeTrialEndDate'] as Timestamp?;
    if (trialEndDate != null && trialEndDate.toDate().isAfter(DateTime.now())) {
      return true; // Trial period is active
    }

    // Előfizetés ellenőrzése
    final bool isActive = userData['isSubscriptionActive'] ?? false;
    if (isActive) {
      // Ha van subscriptionEndDate, azt is ellenőrizni kell
      final subscriptionEndDate = userData['subscriptionEndDate'] as Timestamp?;
      if (subscriptionEndDate != null) {
        return subscriptionEndDate.toDate().isAfter(DateTime.now());
      }
      // Ha nincs subscriptionEndDate, akkor az isSubscriptionActive dönt (visszafelé kompatibilitás)
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Kérjük, jelentkezzen be.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          return const Center(
              child: Text('Felhasználói profil nem található.'));
        }

        final userData = userSnapshot.data?.data() ?? {};
        final bool hasPremiumAccess = _checkPremiumAccess(userData);

        // Admin ellenőrzés - több módszerrel ellenőrizzük
        final userType = (userData['userType'] as String? ?? '').toLowerCase();
        final isAdminEmail =
            user.email != null && user.email == 'tattila.ninox@gmail.com';
        final isAdminBool = userData['isAdmin'] == true;
        final bool isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;

        // Debug: admin ellenőrzés eredménye
        debugPrint(
            '[NoteCardGrid] Admin check - email: ${user.email}, userType: $userType, isAdminBool: $isAdminBool, isAdminEmail: $isAdminEmail, final isAdmin: $isAdmin');

        // FIX: Webalkalmazásban MINDIG csak "Jogász" tudományág
        const userScience = 'Jogász';

        Query<Map<String, dynamic>> query =
            FirebaseConfig.firestore.collection('notes');

        // KÖTELEZŐ: Csak "Jogász" tudományágú jegyzetek
        query = query.where('science', isEqualTo: userScience);

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
            debugPrint(
                '[NoteCardGrid] Admin query - showing Published and Draft notes');
          } else {
            // Nem admin csak Published jegyzeteket lát
            query = query.where('status', isEqualTo: 'Published');
            debugPrint(
                '[NoteCardGrid] Non-admin query - showing only Published notes');
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

        // Debug: lekérdezés paraméterek
        debugPrint(
            '[NoteCardGrid] Query params - science: $userScience, status: ${isAdmin ? "Published/Draft" : "Published"}, type: ${widget.selectedType ?? "all"}');

        // Ha nincs típus szűrő, vagy ha a típus szűrő "memoriapalota_allomasok", betöltjük a fő útvonal dokumentumokat
        final shouldLoadAllomasok = widget.selectedType == null ||
            widget.selectedType!.isEmpty ||
            widget.selectedType == 'memoriapalota_allomasok';

        // Ha nincs típus szűrő, vagy ha a típus szűrő "memoriapalota_fajlok", betöltjük a fájl dokumentumokat
        final shouldLoadFajlok = widget.selectedType == null ||
            widget.selectedType!.isEmpty ||
            widget.selectedType == 'memoriapalota_fajlok';

        // Fő útvonal dokumentumok lekérdezése a memoriapalota_allomasok kollekcióból
        // Ezek a fő dokumentumok, amelyek az utvonalId-val rendelkeznek
        Query<Map<String, dynamic>>? allomasQuery = shouldLoadAllomasok
            ? FirebaseConfig.firestore
                .collection('memoriapalota_allomasok')
                .where('science', isEqualTo: userScience)
            : null;

        // Fájl dokumentumok lekérdezése a memoriapalota_fajlok kollekcióból
        Query<Map<String, dynamic>>? fajlokQuery = shouldLoadFajlok
            ? FirebaseConfig.firestore
                .collection('memoriapalota_fajlok')
                .where('science', isEqualTo: userScience)
            : null;

        if (allomasQuery != null) {
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
        }

        if (fajlokQuery != null) {
          // status
          if (widget.selectedStatus != null &&
              widget.selectedStatus!.isNotEmpty) {
            fajlokQuery =
                fajlokQuery.where('status', isEqualTo: widget.selectedStatus);
          } else {
            fajlokQuery = isAdmin
                ? fajlokQuery.where('status', whereIn: ['Published', 'Draft'])
                : fajlokQuery.where('status', isEqualTo: 'Published');
          }
          // tag
          if (widget.selectedTag != null && widget.selectedTag!.isNotEmpty) {
            fajlokQuery =
                fajlokQuery.where('tags', arrayContains: widget.selectedTag);
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            // Állomások stream builder
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: allomasQuery?.snapshots(),
              builder: (context, allomasSnapshot) {
                // Fájlok stream builder
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: fajlokQuery?.snapshots(),
                  builder: (context, fajlokSnapshot) {
                    // Debug: találatok száma
                    if (snapshot.hasData) {
                      final docs = snapshot.data!.docs;
                      debugPrint('[NoteCardGrid] Found ${docs.length} notes');
                      // Debug: típusok listája
                      final types = docs
                          .map((d) => d.data()['type'] as String? ?? 'unknown')
                          .toSet();
                      debugPrint('[NoteCardGrid] Note types found: $types');
                    }
                    if (allomasSnapshot.hasData) {
                      debugPrint(
                          '[NoteCardGrid] Found ${allomasSnapshot.data!.docs.length} allomasok');
                    }
                    if (fajlokSnapshot.hasData) {
                      debugPrint(
                          '[NoteCardGrid] Found ${fajlokSnapshot.data!.docs.length} fajlok');
                    }

                    if (snapshot.hasError) {
                      return Center(
                          child: Text(
                              'Hiba az adatok betöltésekor: ${snapshot.error.toString()}'));
                    }

                    // Összegyűjtjük a notes dokumentumokat
                    final notesDocs = (snapshot.data?.docs ??
                            const <QueryDocumentSnapshot<
                                Map<String, dynamic>>>[])
                        .where((d) => !(d.data()['deletedAt'] != null))
                        .where((d) => (d.data()['title'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(widget.searchText.toLowerCase()))
                        .toList();

                    // Összefésüljük a két listát
                    // A fő útvonal dokumentumokat hozzáadjuk, de virtuálisan hozzáadjuk a type mezőt
                    final allDocs =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    allDocs.addAll(notesDocs);

                    // Fő útvonal dokumentumok hozzáadása - csak akkor, ha nincs típus szűrő vagy az állomások típusa van kiválasztva
                    if (shouldLoadAllomasok) {
                      final allomasDocs = (allomasSnapshot.data?.docs ??
                              const <QueryDocumentSnapshot<
                                  Map<String, dynamic>>>[])
                          .where((d) {
                        final data = d.data();
                        // Szűrés cím alapján (cim mező)
                        final cim = (data['cim'] ?? '').toString();
                        return cim
                            .toLowerCase()
                            .contains(widget.searchText.toLowerCase());
                      }).toList();
                      allDocs.addAll(allomasDocs);
                    }

                    // Fájl dokumentumok hozzáadása - csak akkor, ha nincs típus szűrő vagy a fájlok típusa van kiválasztva
                    if (shouldLoadFajlok) {
                      final fajlokDocs = (fajlokSnapshot.data?.docs ??
                              const <QueryDocumentSnapshot<
                                  Map<String, dynamic>>>[])
                          .where((d) {
                        final data = d.data();
                        // Szűrés cím alapján (cim mező)
                        final cim = (data['cim'] ?? '').toString();
                        return cim
                            .toLowerCase()
                            .contains(widget.searchText.toLowerCase());
                      }).toList();
                      allDocs.addAll(fajlokDocs);
                    }

                    // Típus szűrés
                    final filteredDocs = widget.selectedType != null &&
                            widget.selectedType!.isNotEmpty
                        ? allDocs.where((d) {
                            final data = d.data();
                            // A fő útvonal dokumentumok a memoriapalota_allomasok kollekcióból jönnek
                            if (d.reference.path
                                    .contains('memoriapalota_allomasok') &&
                                !d.reference.path.contains('/allomasok/')) {
                              return widget.selectedType ==
                                  'memoriapalota_allomasok';
                            }
                            // A fájl dokumentumok a memoriapalota_fajlok kollekcióból jönnek
                            if (d.reference.path
                                .contains('memoriapalota_fajlok')) {
                              return widget.selectedType ==
                                  'memoriapalota_fajlok';
                            }
                            return data['type'] == widget.selectedType;
                          }).toList()
                        : allDocs;

                    final docs = filteredDocs;

                    if (!snapshot.hasData &&
                        snapshot.connectionState != ConnectionState.active &&
                        (!shouldLoadAllomasok || !allomasSnapshot.hasData) &&
                        (!shouldLoadFajlok || !fajlokSnapshot.hasData)) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (docs.isEmpty) {
                      return const Center(child: Text('Nincs találat.'));
                    }

                    // Hierarchikus csoportosítás: Kategória → Címkék hierarchia (tudomány szint nélkül, mert csak "Jogász" van)
                    // A címkék hierarchikusan működnek: tags[0] = főcím, tags[1] = alcím, tags[2] = alcím az alcím alatt, stb.
                    // Map<category, Map<firstTag, Map<secondTag, Map<thirdTag, ...>>>>
                    final Map<String, Map<String, dynamic>> hierarchical = {};

                    for (var d in docs) {
                      final category =
                          (d.data()['category'] ?? 'Egyéb') as String;
                      final tags = (d.data()['tags'] as List<dynamic>? ?? [])
                          .cast<String>();

                      hierarchical.putIfAbsent(category, () => {});

                      // Címkék hierarchikus csoportosítása
                      if (tags.isEmpty) {
                        hierarchical[category]!
                            .putIfAbsent(
                                'Nincs címke',
                                () => <QueryDocumentSnapshot<
                                    Map<String, dynamic>>>[])
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
                                final map =
                                    current[tag] as Map<String, dynamic>;
                                if (!map.containsKey('')) {
                                  map[''] = <QueryDocumentSnapshot<
                                      Map<String, dynamic>>>[];
                                }
                                (map[''] as List<
                                        QueryDocumentSnapshot<
                                            Map<String, dynamic>>>)
                                    .add(d);
                              } else {
                                // Ha lista van, akkor hozzáadjuk
                                (current[tag] as List<
                                        QueryDocumentSnapshot<
                                            Map<String, dynamic>>>)
                                    .add(d);
                              }
                            } else {
                              // Ha nem létezik, akkor létrehozzuk listaként
                              current[tag] =
                                  <QueryDocumentSnapshot<Map<String, dynamic>>>[
                                d
                              ];
                            }
                          } else {
                            // Ha nem az utolsó, akkor egy köztes szint
                            if (!current.containsKey(tag)) {
                              current[tag] = <String, dynamic>{};
                            } else if (current[tag] is! Map) {
                              // Ha véletlenül lista van, átalakítjuk Map-pé és összefésüljük
                              // Ez akkor történik, amikor egy jegyzetnek csak ["MP"] címkéje van,
                              // majd egy másik jegyzetnek ["MP", "Teszt"] címkéi vannak
                              final existingDocs = current[tag] as List<
                                  QueryDocumentSnapshot<Map<String, dynamic>>>;
                              current[tag] = <String, dynamic>{
                                '': existingDocs
                              };
                            }
                            current = current[tag] as Map<String, dynamic>;
                          }
                        }
                      }
                    }

                    // Rendezés minden szinten - rekurzívan
                    void sortDocs(Map<String, dynamic> level) {
                      level.forEach((key, value) {
                        if (value is List<
                            QueryDocumentSnapshot<Map<String, dynamic>>>) {
                          value.sort((a, b) {
                            // Fő útvonal dokumentumok típusának meghatározása (nem subcollection)
                            final isAllomasA = a.reference.path
                                    .contains('memoriapalota_allomasok') &&
                                !a.reference.path.contains('/allomasok/');
                            final isAllomasB = b.reference.path
                                    .contains('memoriapalota_allomasok') &&
                                !b.reference.path.contains('/allomasok/');
                            final isFajlA = a.reference.path
                                .contains('memoriapalota_fajlok');
                            final isFajlB = b.reference.path
                                .contains('memoriapalota_fajlok');
                            final typeA = isAllomasA
                                ? 'memoriapalota_allomasok'
                                : (isFajlA
                                    ? 'memoriapalota_fajlok'
                                    : (a.data()['type'] as String? ?? ''));
                            final typeB = isAllomasB
                                ? 'memoriapalota_allomasok'
                                : (isFajlB
                                    ? 'memoriapalota_fajlok'
                                    : (b.data()['type'] as String? ?? ''));

                            // 'source' típus mindig a lista végére kerüljön
                            final bool isSourceA = typeA == 'source';
                            final bool isSourceB = typeB == 'source';
                            if (isSourceA != isSourceB) {
                              return isSourceA ? 1 : -1; // source után soroljuk
                            }
                            // ha mindkettő ugyanaz a forrás státusz, marad a korábbi logika
                            final typeCompare = typeA.compareTo(typeB);
                            if (typeCompare != 0) {
                              return typeCompare;
                            }
                            // Cím meghatározása: fő útvonal dokumentumoknál és fájloknál 'cim', egyébként 'title'
                            final titleA = isAllomasA || isFajlA
                                ? (a.data()['cim'] as String? ?? '')
                                : (a.data()['title'] as String? ?? '');
                            final titleB = isAllomasB || isFajlB
                                ? (b.data()['cim'] as String? ?? '')
                                : (b.data()['title'] as String? ?? '');
                            return titleA.compareTo(titleB);
                          });
                        } else if (value is Map<String, dynamic>) {
                          // Rekurzívan rendezzük az al-szinteket
                          sortDocs(value);
                        }
                      });
                    }

                    hierarchical.forEach((category, tags) {
                      sortDocs(tags);
                    });

                    return ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 8),
                      children: hierarchical.entries.map((categoryEntry) {
                        return _CategorySection(
                          key: ValueKey('category_${categoryEntry.key}'),
                          category: categoryEntry.key,
                          tagHierarchy: categoryEntry.value,
                          selectedCategory: widget.selectedCategory,
                          selectedTag: widget.selectedTag,
                          hasPremiumAccess: hasPremiumAccess,
                        );
                      }).toList(),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
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
    final screen = CategoryTagsScreen(category: widget.category);

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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(0),
        side: BorderSide(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _navigateToCategoryTags(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                color: const Color(0xFF1976D2),
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
