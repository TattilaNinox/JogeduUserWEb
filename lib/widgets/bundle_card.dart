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
        onTap: () {
          context.go('/my-bundles/view/$id');
        },
        onLongPress: () {
          _showContextMenu(context);
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              const Icon(
                Icons.folder_special,
                color: Color(0xFF1976D2),
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF202122),
                      ),
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                totalCount.toString(),
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

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('Megtekintés'),
              onTap: () {
                Navigator.pop(context);
                context.go('/my-bundles/view/$id');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Szerkesztés'),
              onTap: () {
                Navigator.pop(context);
                context.go('/my-bundles/edit/$id');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Törlés', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context);
              },
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
