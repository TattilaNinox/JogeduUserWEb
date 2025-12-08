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

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: Text(
                      'Hiba az adatok betöltésekor: ${snapshot.error.toString()}'));
            }
            final docs = (snapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((d) => !(d.data()['deletedAt'] != null))
                .where((d) => (d.data()['title'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(widget.searchText.toLowerCase()))
                .toList();

            if (!snapshot.hasData &&
                snapshot.connectionState != ConnectionState.active) {
              return const Center(child: CircularProgressIndicator());
            }

            if (docs.isEmpty) {
              return const Center(child: Text('Nincs találat.'));
            }

            // Csoportosítás kategóriánként
            final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
                grouped = {};
            for (var d in docs) {
              final cat = (d.data()['category'] ?? 'Egyéb') as String;
              grouped.putIfAbsent(cat, () => []).add(d);
            }

            // Kategórián belüli rendezés típus és cím alapján
            grouped.forEach((key, value) {
              value.sort((a, b) {
                final typeA = a.data()['type'] as String? ?? '';
                final typeB = b.data()['type'] as String? ?? '';
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
                final titleA = a.data()['title'] as String? ?? '';
                final titleB = b.data()['title'] as String? ?? '';
                return titleA.compareTo(titleB);
              });
            });

            return ListView(
              padding: EdgeInsets.zero,
              children: grouped.entries.map((entry) {
                final items = entry.value;
                return _CategorySection(
                  category: entry.key,
                  docs: items,
                  selectedCategory: widget.selectedCategory,
                  hasPremiumAccess: hasPremiumAccess,
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}

class _CategorySection extends StatefulWidget {
  final String category;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String? selectedCategory;
  final bool hasPremiumAccess;

  const _CategorySection({
    required this.category,
    required this.docs,
    this.selectedCategory,
    required this.hasPremiumAccess,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  late bool _isExpanded; // Alapértelmezetten összecsukva

  @override
  void initState() {
    super.initState();
    // Ha ez a kategória van kiválasztva a szűrőben, akkor kibontva legyen
    _isExpanded = widget.category == widget.selectedCategory;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.category,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                          fontSize: 15,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.docs.length}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
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
                        size: 20,
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
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 0),
                      itemBuilder: (context, index) {
                        final doc = widget.docs[index];
                        final data = doc.data();
                        final type = data['type'] as String? ?? 'standard';
                        // Ha az isFree mező hiányzik, akkor ZÁRT (false)
                        final isFree = data['isFree'] as bool? ?? false;

                        final isLocked = !isFree && !widget.hasPremiumAccess;
                        final isLast = index == widget.docs.length - 1;

                        return NoteListTile(
                          id: doc.id,
                          title: data['title'] ?? '',
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
