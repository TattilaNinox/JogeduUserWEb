import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_bundle.dart';
import '../services/user_bundle_service.dart';
import 'bundle_card.dart';

/// Kötegek grid megjelenítése.
///
/// UserBundleService stream-jét használja a kötegek listázásához.
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

    return StreamBuilder<List<UserBundle>>(
      stream: UserBundleService.getUserBundles(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Hiba történt: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var bundles = snapshot.data!;

        // Szűrés keresőszöveg alapján
        if (searchText.isNotEmpty) {
          final searchLower = searchText.toLowerCase();
          bundles = bundles.where((bundle) {
            return bundle.name.toLowerCase().contains(searchLower) ||
                bundle.description.toLowerCase().contains(searchLower);
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

            return BundleCard(
              id: bundle.id,
              name: bundle.name,
              description:
                  bundle.description.isNotEmpty ? bundle.description : null,
              noteCount: bundle.noteCount,
              allomasCount: bundle.allomasCount,
              dialogusCount: bundle.dialogusCount,
              jogesetCount: bundle.jogesetCount,
              totalCount: bundle.totalCount,
            );
          },
        );
      },
    );
  }
}
