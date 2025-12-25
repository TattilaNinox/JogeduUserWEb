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
  bool _notesExpanded = true;
  bool _allomasExpanded = true;
  bool _dialogusExpanded = true;

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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Jegyzetek szekció
          if (noteIds.isNotEmpty)
            _buildExpandableSection(
              title: 'Jegyzetek',
              icon: Icons.description,
              count: noteIds.length,
              isExpanded: _notesExpanded,
              onToggle: () => setState(() => _notesExpanded = !_notesExpanded),
              ids: noteIds,
              collection: 'notes',
            ),

          // Állomások szekció
          if (allomasIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildExpandableSection(
              title: 'Memóriapalota állomások',
              icon: Icons.train,
              count: allomasIds.length,
              isExpanded: _allomasExpanded,
              onToggle: () =>
                  setState(() => _allomasExpanded = !_allomasExpanded),
              ids: allomasIds,
              collection: 'memoriapalota_allomasok',
            ),
          ],

          // Dialógusok szekció
          if (dialogusIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildExpandableSection(
              title: 'Dialógus fájlok',
              icon: Icons.chat_bubble_outline,
              count: dialogusIds.length,
              isExpanded: _dialogusExpanded,
              onToggle: () =>
                  setState(() => _dialogusExpanded = !_dialogusExpanded),
              ids: dialogusIds,
              collection: 'dialogus_fajlok',
            ),
          ],

          // Ha nincs egyetlen dokumentum sem
          if (noteIds.isEmpty && allomasIds.isEmpty && dialogusIds.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ez a köteg még üres',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection({
    required String title,
    required IconData icon,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<String> ids,
    required String collection,
  }) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon, color: Theme.of(context).primaryColor),
            title: Text(
              '$title ($count)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: onToggle,
          ),
          if (isExpanded)
            ...ids.map((id) => ListTile(
                  dense: true,
                  leading: const SizedBox(width: 40),
                  title: FutureBuilder<DocumentSnapshot>(
                    future: FirebaseConfig.firestore
                        .collection(collection)
                        .doc(id)
                        .get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Text('Betöltés...');
                      }
                      if (!snapshot.data!.exists) {
                        return Text('Dokumentum nem található ($id)');
                      }
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      final title = data['title'] ?? data['name'] ?? 'Névtelen';
                      return Text(title);
                    },
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // Navigálás a dokumentumhoz
                    _navigateToDocument(id, collection);
                  },
                )),
        ],
      ),
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
