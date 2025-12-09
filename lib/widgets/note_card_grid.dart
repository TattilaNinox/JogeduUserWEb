import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/firebase_config.dart';
import 'note_list_tile.dart';

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
        final isAdminEmail = user.email != null && user.email == 'tattila.ninox@gmail.com';
        final isAdminBool = userData['isAdmin'] == true;
        final bool isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;
        
        // Debug: admin ellenőrzés eredménye
        debugPrint('[NoteCardGrid] Admin check - email: ${user.email}, userType: $userType, isAdminBool: $isAdminBool, isAdminEmail: $isAdminEmail, final isAdmin: $isAdmin');

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
            debugPrint('[NoteCardGrid] Admin query - showing Published and Draft notes');
          } else {
            // Nem admin csak Published jegyzeteket lát
            query = query.where('status', isEqualTo: 'Published');
            debugPrint('[NoteCardGrid] Non-admin query - showing only Published notes');
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
        debugPrint('[NoteCardGrid] Query params - science: $userScience, status: ${isAdmin ? "Published/Draft" : "Published"}, type: ${widget.selectedType ?? "all"}');

        // Ha nincs típus szűrő, vagy ha a típus szűrő "memoriapalota_allomasok", betöltjük a fő útvonal dokumentumokat
        final shouldLoadAllomasok = widget.selectedType == null || 
                                     widget.selectedType!.isEmpty || 
                                     widget.selectedType == 'memoriapalota_allomasok';

        // Fő útvonal dokumentumok lekérdezése a memoriapalota_allomasok kollekcióból
        // Ezek a fő dokumentumok, amelyek az utvonalId-val rendelkeznek
        final allomasQuery = shouldLoadAllomasok
            ? FirebaseConfig.firestore
                .collection('memoriapalota_allomasok')
                .where('science', isEqualTo: userScience)
            : null;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            // Állomások stream builder
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: allomasQuery?.snapshots(),
              builder: (context, allomasSnapshot) {
                // Debug: találatok száma
                if (snapshot.hasData) {
                  final docs = snapshot.data!.docs;
                  debugPrint('[NoteCardGrid] Found ${docs.length} notes');
                  // Debug: típusok listája
                  final types = docs.map((d) => d.data()['type'] as String? ?? 'unknown').toSet();
                  debugPrint('[NoteCardGrid] Note types found: $types');
                }
                if (allomasSnapshot.hasData) {
                  debugPrint('[NoteCardGrid] Found ${allomasSnapshot.data!.docs.length} allomasok');
                }
                
                if (snapshot.hasError) {
                  return Center(
                      child: Text(
                          'Hiba az adatok betöltésekor: ${snapshot.error.toString()}'));
                }
                
                // Összegyűjtjük a notes dokumentumokat
                final notesDocs = (snapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
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
                if (shouldLoadAllomasok) {
                  final allomasDocs = (allomasSnapshot.data?.docs ??
                          const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      .where((d) {
                        final data = d.data();
                        // Szűrés cím alapján (cim mező)
                        final cim = (data['cim'] ?? '').toString();
                        return cim.toLowerCase().contains(widget.searchText.toLowerCase());
                      })
                      .toList();
                  allDocs.addAll(allomasDocs);
                }
                
                // Típus szűrés
                final filteredDocs = widget.selectedType != null && widget.selectedType!.isNotEmpty
                    ? allDocs.where((d) {
                        final data = d.data();
                        // A fő útvonal dokumentumok a memoriapalota_allomasok kollekcióból jönnek
                        if (d.reference.path.contains('memoriapalota_allomasok') && 
                            !d.reference.path.contains('/allomasok/')) {
                          return widget.selectedType == 'memoriapalota_allomasok';
                        }
                        return data['type'] == widget.selectedType;
                      }).toList()
                    : allDocs;
                
                final docs = filteredDocs;

                if (!snapshot.hasData &&
                    snapshot.connectionState != ConnectionState.active &&
                    (!shouldLoadAllomasok || !allomasSnapshot.hasData)) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (docs.isEmpty) {
                  return const Center(child: Text('Nincs találat.'));
                }

            // Hierarchikus csoportosítás: Kategória → Címkék (tudomány szint nélkül, mert csak "Jogász" van)
            // Map<category, Map<tag, List<docs>>>
            final Map<String, Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>> 
                hierarchical = {};
            
            for (var d in docs) {
              final category = (d.data()['category'] ?? 'Egyéb') as String;
              final tags = (d.data()['tags'] as List<dynamic>? ?? []).cast<String>();
              
              hierarchical.putIfAbsent(category, () => {});
              
              // Címkék szerint csoportosítás
              if (tags.isEmpty) {
                hierarchical[category]!.putIfAbsent('Nincs címke', () => []).add(d);
              } else {
                for (var tag in tags) {
                  hierarchical[category]!.putIfAbsent(tag, () => []).add(d);
                }
              }
            }

            // Rendezés minden szinten
            hierarchical.forEach((category, tags) {
              tags.forEach((tag, docsList) {
                docsList.sort((a, b) {
                  // Fő útvonal dokumentumok típusának meghatározása (nem subcollection)
                  final isAllomasA = a.reference.path.contains('memoriapalota_allomasok') && 
                                     !a.reference.path.contains('/allomasok/');
                  final isAllomasB = b.reference.path.contains('memoriapalota_allomasok') && 
                                     !b.reference.path.contains('/allomasok/');
                  final typeA = isAllomasA ? 'memoriapalota_allomasok' : (a.data()['type'] as String? ?? '');
                  final typeB = isAllomasB ? 'memoriapalota_allomasok' : (b.data()['type'] as String? ?? '');
                  
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
                  // Cím meghatározása: fő útvonal dokumentumoknál 'cim', egyébként 'title'
                  final titleA = isAllomasA 
                      ? (a.data()['cim'] as String? ?? '')
                      : (a.data()['title'] as String? ?? '');
                  final titleB = isAllomasB 
                      ? (b.data()['cim'] as String? ?? '')
                      : (b.data()['title'] as String? ?? '');
                  return titleA.compareTo(titleB);
                });
              });
            });

                return ListView(
                  padding: EdgeInsets.zero,
                  children: hierarchical.entries.map((categoryEntry) {
                    return _CategorySection(
                      key: ValueKey('category_${categoryEntry.key}'),
                      category: categoryEntry.key,
                      tags: categoryEntry.value,
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
  }
}

// Kategória szintű szekció widget
class _CategorySection extends StatefulWidget {
  final String category;
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> tags;
  final String? selectedCategory;
  final String? selectedTag;
  final bool hasPremiumAccess;

  const _CategorySection({
    super.key,
    required this.category,
    required this.tags,
    this.selectedCategory,
    this.selectedTag,
    required this.hasPremiumAccess,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    // Alapértelmezetten zárva - csak akkor legyen kibontva, ha explicit módon kiválasztották a szűrőben
    _isExpanded = widget.category == widget.selectedCategory && widget.selectedCategory != null;
  }

  @override
  Widget build(BuildContext context) {
    final totalDocs = widget.tags.values.fold<int>(0, (sum, docs) => sum + docs.length);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              borderRadius: _isExpanded
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    )
                  : BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _isExpanded 
                      ? const Color(0xFFF9FAFB)
                      : Colors.white,
                  borderRadius: _isExpanded
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        )
                      : BorderRadius.circular(8),
                  border: _isExpanded
                      ? const Border(
                          bottom: BorderSide(
                            color: Color(0xFFE5E7EB),
                            width: 1,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      _isExpanded ? Icons.folder_open : Icons.folder_outlined,
                      color: const Color(0xFF6B7280),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.category,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                          fontSize: 14,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Text(
                      '$totalDocs',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF6B7280),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.tags.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final tagEntry = widget.tags.entries.elementAt(index);
                        return _TagSection(
                          key: ValueKey('tag_${widget.category}_${tagEntry.key}'),
                          tag: tagEntry.key,
                          docs: tagEntry.value,
                          selectedTag: widget.selectedTag,
                          hasPremiumAccess: widget.hasPremiumAccess,
                        );
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// Címke szintű szekció widget
class _TagSection extends StatefulWidget {
  final String tag;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String? selectedTag;
  final bool hasPremiumAccess;

  const _TagSection({
    super.key,
    required this.tag,
    required this.docs,
    this.selectedTag,
    required this.hasPremiumAccess,
  });

  @override
  State<_TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends State<_TagSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    // Csak akkor legyen kibontva, ha konkrétan kiválasztva van a szűrőben
    _isExpanded = widget.tag == widget.selectedTag;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              borderRadius: _isExpanded
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    )
                  : BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _isExpanded 
                      ? const Color(0xFFFAFBFC)
                      : Colors.white,
                  borderRadius: _isExpanded
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        )
                      : BorderRadius.circular(6),
                  border: _isExpanded
                      ? const Border(
                          bottom: BorderSide(
                            color: Color(0xFFE5E7EB),
                            width: 1,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      _isExpanded ? Icons.label : Icons.label_outline,
                      color: const Color(0xFF6B7280),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.tag,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF111827),
                          fontSize: 13,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.docs.length}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF6B7280),
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 0),
                      itemBuilder: (context, index) {
                        final doc = widget.docs[index];
                        final data = doc.data();
                        // Fő útvonal dokumentumok esetén külön kezelés (nem subcollection)
                        final isAllomas = doc.reference.path.contains('memoriapalota_allomasok') && 
                                         !doc.reference.path.contains('/allomasok/');
                        final type = isAllomas 
                            ? 'memoriapalota_allomasok' 
                            : (data['type'] as String? ?? 'standard');
                        // Fő útvonal dokumentumoknál 'cim' mező, egyébként 'title'
                        final title = isAllomas 
                            ? (data['cim'] as String? ?? '')
                            : (data['title'] as String? ?? '');
                        // Ha az isFree mező hiányzik, akkor ZÁRT (false)
                        final isFree = data['isFree'] as bool? ?? false;

                        final isLocked = !isFree && !widget.hasPremiumAccess;
                        final isLast = index == widget.docs.length - 1;

                        return NoteListTile(
                          id: doc.id,
                          title: title,
                          type: type,
                          hasDoc: (data['docxUrl'] ?? '').toString().isNotEmpty,
                          hasAudio:
                              (data['audioUrl'] ?? '').toString().isNotEmpty,
                          audioUrl: (data['audioUrl'] ?? '').toString(),
                          hasVideo:
                              (data['videoUrl'] ?? '').toString().isNotEmpty,
                          deckCount: type == 'deck'
                              ? (data['flashcards'] as List<dynamic>? ?? [])
                                  .length
                              : null,
                          isLocked: isLocked,
                          isLast: isLast,
                        );
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
