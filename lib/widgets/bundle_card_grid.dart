import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
import 'bundle_card.dart';

/// Kötegek grid megjelenítése.
///
/// Hasonló a NoteCardGrid-hez, de felhasználói kötegek megjelenítésére.
/// StreamBuilder-rel figyeli a users/{userId}/bundles subcollection-t.
class BundleCardGrid extends StatelessWidget {
  final String searchText;

  const BundleCardGrid({
    super.key,
    required this.searchText,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
        child: Text('Jelentkezz be a kötegek megtekintéséhez'),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .collection('bundles')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Hiba történt: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var bundles = snapshot.data!.docs.toList();

        // Rendezés kliens oldalon (hogy kötelező orderBy nélkül is lássuk a régi dokumentumokat)
        bundles.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;

          final tsA = dataA['modified'] as Timestamp? ??
              dataA['updatedAt'] as Timestamp? ??
              dataA['createdAt'] as Timestamp?;
          final tsB = dataB['modified'] as Timestamp? ??
              dataB['updatedAt'] as Timestamp? ??
              dataB['createdAt'] as Timestamp?;

          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });

        // Szűrés keresőszöveg alapján
        if (searchText.isNotEmpty) {
          bundles = bundles.where((bundle) {
            final data = bundle.data() as Map<String, dynamic>;
            final name = data['name']?.toString().toLowerCase() ?? '';
            final description =
                data['description']?.toString().toLowerCase() ?? '';
            final searchLower = searchText.toLowerCase();
            return name.contains(searchLower) ||
                description.contains(searchLower);
          }).toList();
        }

        if (bundles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_special,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  searchText.isEmpty
                      ? 'Még nincs egyetlen köteg sem'
                      : 'Nincs találat a keresésre',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (searchText.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Hozz létre egy új köteget!',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          itemCount: bundles.length,
          itemBuilder: (context, index) {
            final bundle = bundles[index];
            final data = bundle.data() as Map<String, dynamic>;

            final name = data['name'] ?? 'Névtelen köteg';
            final description = data['description'];
            final noteIds = (data['noteIds'] as List<dynamic>?) ?? [];
            final allomasIds = (data['allomasIds'] as List<dynamic>?) ?? [];
            final dialogusIds = (data['dialogusIds'] as List<dynamic>?) ?? [];
            final createdAt =
                (data['createdAt'] ?? data['created']) as Timestamp?;

            return BundleCard(
              id: bundle.id,
              name: name,
              description: description,
              noteCount: noteIds.length,
              allomasCount: allomasIds.length,
              dialogusCount: dialogusIds.length,
              createdAt: createdAt,
            );
          },
        );
      },
    );
  }
}
