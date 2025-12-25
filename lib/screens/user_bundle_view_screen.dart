import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../core/firebase_config.dart';
import '../utils/filter_storage.dart';

/// Köteg megtekintő képernyő.
///
/// Egyszerű lista nézetben jeleníti meg a köteg tartalmát,
/// típusonként csoportosítva expandable szekciókban.
class UserBundleViewScreen extends StatefulWidget {
  final String bundleId;

  const UserBundleViewScreen({super.key, required this.bundleId});

  @override
  State<UserBundleViewScreen> createState() => _UserBundleViewScreenState();
}

class _UserBundleViewScreenState extends State<UserBundleViewScreen> {
  Map<String, dynamic>? _bundleData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBundle();
  }

  Future<void> _loadBundle() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseConfig.firestore
        .collection('users')
        .doc(user.uid)
        .collection('bundles')
        .doc(widget.bundleId)
        .get();

    if (doc.exists) {
      setState(() {
        _bundleData = doc.data();
        _isLoading = false;
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Köteg nem található')),
        );
        context.go('/my-bundles');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Betöltés...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_bundleData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hiba')),
        body: const Center(child: Text('Köteg nem található')),
      );
    }

    final name = _bundleData!['name'] ?? 'Névtelen köteg';
    final description = _bundleData!['description'] ?? '';
    final noteIds = List<String>.from(_bundleData!['noteIds'] ?? []);
    final allomasIds = List<String>.from(_bundleData!['allomasIds'] ?? []);
    final dialogusIds = List<String>.from(_bundleData!['dialogusIds'] ?? []);

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/my-bundles'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.go('/my-bundles/edit/${widget.bundleId}'),
            tooltip: 'Szerkesztés',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Leírás
          if (description.isNotEmpty) ...[
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Egyetlen közös lista az összes elemnek
          if (noteIds.isNotEmpty ||
              allomasIds.isNotEmpty ||
              dialogusIds.isNotEmpty)
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  ...noteIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'notes',
                        icon: Icons.description,
                        iconColor: Colors.blue.shade700,
                      )),
                  ...allomasIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'memoriapalota_allomasok',
                        icon: Icons.directions_bus,
                        iconColor: Colors.orange.shade700,
                      )),
                  ...dialogusIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'dialogus_fajlok',
                        icon: Icons.chat_bubble_outline,
                        iconColor: Colors.green.shade700,
                      )),
                ],
              ),
            ),

          // Ha nincs egyetlen dokumentum sem
          if (noteIds.isEmpty && allomasIds.isEmpty && dialogusIds.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ez a köteg még üres',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile({
    required String id,
    required String collection,
    required IconData icon,
    required Color iconColor,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: FutureBuilder<DocumentSnapshot>(
            future:
                FirebaseConfig.firestore.collection(collection).doc(id).get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Text('Betöltés...',
                    style:
                        TextStyle(color: Colors.grey.shade400, fontSize: 14));
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return Text('Dokumentum nem található',
                    style: TextStyle(color: Colors.red.shade300, fontSize: 14));
              }
              final data = snapshot.data!.data() as Map<String, dynamic>;
              final title = data['title'] ?? data['name'] ?? 'Névtelen';
              return Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2C3E50),
                ),
              );
            },
          ),
          trailing:
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
          onTap: () => _navigateToDocument(id, collection),
        ),
        Divider(height: 1, indent: 70, color: Colors.grey.shade100),
      ],
    );
  }

  Future<void> _navigateToDocument(String id, String collection) async {
    try {
      // Megnyitás előtt lekérjük a dokumentum metaadatait a helyes navigációhoz
      final doc =
          await FirebaseConfig.firestore.collection(collection).doc(id).get();

      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dokumentum nem található')),
          );
        }
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      final science = data['science'] as String?;
      final category = data['category'] as String?;
      final tags = data['tags'] as List<dynamic>?;
      final tag =
          tags != null && tags.isNotEmpty ? tags.first.toString() : null;

      // FilterStorage inicializálása, hogy a Jegyzethallgató/Olvasó tudja, hova kell visszalépni
      // és milyen környezetben kell betöltenie a tartalmat
      FilterStorage.science = science;
      FilterStorage.category = category;
      FilterStorage.tag = tag;

      if (collection == 'notes') {
        if (!mounted) return;
        context.go('/note/$id?from=bundle');
      } else if (collection == 'memoriapalota_allomasok') {
        if (!mounted) return;
        context.go('/memoriapalota-allomas/$id?from=bundle');
      } else if (collection == 'dialogus_fajlok') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Dialógus fájl megnyitása még nem implementált')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a megnyitás során: $e')),
        );
      }
    }
  }
}
