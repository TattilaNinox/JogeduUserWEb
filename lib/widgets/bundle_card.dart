import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';

/// Köteg kártya widget a grid nézethez.
///
/// Hasonló a NoteCard-hoz, de kötegek megjelenítésére optimalizálva.
/// Megjeleníti a köteg nevét, leírását, dokumentumok számát típusonként,
/// és a létrehozás dátumát.
class BundleCard extends StatelessWidget {
  final String id;
  final String name;
  final String? description;
  final int noteCount;
  final int allomasCount;
  final int dialogusCount;
  final Timestamp? createdAt;

  const BundleCard({
    super.key,
    required this.id,
    required this.name,
    this.description,
    required this.noteCount,
    required this.allomasCount,
    required this.dialogusCount,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = noteCount + allomasCount + dialogusCount;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

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
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 2 : 4,
        ),
        child: Row(
          children: [
            // Kattintható rész a megtekintéshez
            Expanded(
              child: InkWell(
                onTap: () => context.go('/my-bundles/view/$id'),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_special,
                        color: const Color(0xFF1976D2),
                        size: isMobile ? 22 : 24,
                      ),
                      SizedBox(width: isMobile ? 8 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isMobile
                              ? CrossAxisAlignment.center
                              : CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              textAlign:
                                  isMobile ? TextAlign.center : TextAlign.start,
                              style: TextStyle(
                                fontSize: isMobile ? 12 : 15,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF202122),
                              ),
                            ),
                            if (description != null &&
                                description!.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                description!,
                                textAlign: isMobile
                                    ? TextAlign.center
                                    : TextAlign.start,
                                style: TextStyle(
                                  fontSize: isMobile ? 12 : 13,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Jobb oldali szekció (szám és menü)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  totalCount.toString(),
                  style: TextStyle(
                    fontSize: isMobile ? 13 : 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (isMobile)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 20, color: Colors.grey.shade600),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) {
                      if (value == 'edit') {
                        context.go('/my-bundles/edit/$id');
                      } else if (value == 'delete') {
                        _confirmDelete(context);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined,
                                size: 18, color: Colors.grey.shade700),
                            const SizedBox(width: 12),
                            const Text('Szerkesztés'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            const SizedBox(width: 12),
                            const Text('Törlés',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  const SizedBox(width: 8),
                  // Desktop akció ikonok
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => context.go('/my-bundles/edit/$id'),
                    tooltip: 'Szerkesztés',
                    color: Colors.grey.shade700,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.red),
                    onPressed: () => _confirmDelete(context),
                    tooltip: 'Törlés',
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Köteg törlése'),
        content: Text('Biztosan törölni szeretnéd a "$name" köteget?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        await FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .doc(id)
            .delete();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Köteg sikeresen törölve')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hiba a törlés során: $e')),
          );
        }
      }
    }
  }
}
