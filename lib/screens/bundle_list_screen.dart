import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../widgets/sidebar.dart';
import '../widgets/header.dart';

/// A jegyzet kötegek (bundle) listáját megjelenítő képernyő.
///
/// Ez a képernyő megjeleníti az összes létrehozott köteget, ahol minden köteg
/// azonos kategóriájú és címkéjű jegyzetek gyűjteménye. A felhasználó innen
/// tudja kezelni a kötegeket: új létrehozása, meglévő szerkesztése, törlése
/// és megtekintése prezentáció módban.
class BundleListScreen extends StatefulWidget {
  const BundleListScreen({super.key});

  @override
  State<BundleListScreen> createState() => _BundleListScreenState();
}

class _BundleListScreenState extends State<BundleListScreen> {
  String _searchText = '';

  /// Keresőszöveg frissítése a Header widgetből
  void _onSearchChanged(String value) {
    setState(() {
      _searchText = value;
    });
  }

  /// Új köteg létrehozása - navigálás a szerkesztő képernyőre
  void _createNewBundle() {
    context.go('/bundles/create');
  }

  /// Köteg szerkesztése
  void _editBundle(String bundleId) {
    context.go('/bundles/edit/$bundleId');
  }

  /// Köteg megtekintése prezentáció módban
  void _viewBundle(String bundleId) {
    context.go('/bundles/view/$bundleId');
  }

  /// Köteg törlése megerősítés után
  Future<void> _deleteBundle(String bundleId, String bundleName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Köteg törlése'),
        content: Text('Biztosan törölni szeretnéd a "$bundleName" köteget?'),
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

    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('bundles')
          .doc(bundleId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Köteg sikeresen törölve!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 249, 250, 251),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'bundles'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Header(onSearchChanged: _onSearchChanged),
                // Fejléc sáv az új köteg gombbal
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Jegyzetek kötegei',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      ElevatedButton.icon(
                        onPressed: _createNewBundle,
                        icon: const Icon(Icons.add),
                        label: const Text('Új köteg'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Kötegek táblázata
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('bundles')
                        .orderBy('createdAt', descending: true)
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

                      var bundles = snapshot.data!.docs;

                      // Szűrés keresőszöveg alapján
                      if (_searchText.isNotEmpty) {
                        bundles = bundles.where((bundle) {
                          final data = bundle.data() as Map<String, dynamic>;
                          final name =
                              data['name']?.toString().toLowerCase() ?? '';
                          final description =
                              data['description']?.toString().toLowerCase() ??
                                  '';
                          final searchLower = _searchText.toLowerCase();
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
                                Icons.collections_bookmark,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchText.isEmpty
                                    ? 'Még nincs egyetlen köteg sem'
                                    : 'Nincs találat a keresésre',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (_searchText.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Hozz létre egy új köteget a fenti gombbal!',
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

                      return Container(
                        margin: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Név')),
                              DataColumn(label: Text('Leírás')),
                              DataColumn(label: Text('Kategória')),
                              DataColumn(label: Text('Címkék')),
                              DataColumn(label: Text('Jegyzetek száma')),
                              DataColumn(label: Text('Létrehozva')),
                              DataColumn(label: Text('Műveletek')),
                            ],
                            rows: bundles.map((bundle) {
                              final data =
                                  bundle.data() as Map<String, dynamic>;
                              final name = data['name'] ?? 'Névtelen';
                              final description = data['description'] ?? '';
                              final category = data['category'] ?? '';
                              final tags = (data['tags'] as List<dynamic>?)
                                      ?.join(', ') ??
                                  '';
                              final noteIds =
                                  (data['noteIds'] as List<dynamic>?) ?? [];
                              final noteCount = noteIds.length;
                              final createdAt = data['createdAt'] as Timestamp?;
                              final createdDate = createdAt != null
                                  ? '${createdAt.toDate().year}.'
                                      '${createdAt.toDate().month.toString().padLeft(2, '0')}.'
                                      '${createdAt.toDate().day.toString().padLeft(2, '0')}.'
                                  : '';

                              return DataRow(
                                cells: [
                                  DataCell(Text(name)),
                                  DataCell(
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 200),
                                      child: Text(
                                        description,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(category)),
                                  DataCell(
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 150),
                                      child: Text(
                                        tags,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .primaryColor
                                              .withAlpha(26),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          noteCount.toString(),
                                          style: TextStyle(
                                            color:
                                                Theme.of(context).primaryColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(createdDate)),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.visibility),
                                          onPressed: noteCount > 0
                                              ? () => _viewBundle(bundle.id)
                                              : null,
                                          tooltip: 'Megtekintés',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          onPressed: () =>
                                              _editBundle(bundle.id),
                                          tooltip: 'Szerkesztés',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete),
                                          onPressed: () =>
                                              _deleteBundle(bundle.id, name),
                                          tooltip: 'Törlés',
                                          color: Colors.red,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
