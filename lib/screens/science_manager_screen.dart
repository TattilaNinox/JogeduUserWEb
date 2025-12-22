import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import '../widgets/header.dart';

/// Tudományok (science) kezelése – hasonló logikával, mint a kategóriák.
class ScienceManagerScreen extends StatefulWidget {
  const ScienceManagerScreen({super.key});

  @override
  State<ScienceManagerScreen> createState() => _ScienceManagerScreenState();
}

class _ScienceManagerScreenState extends State<ScienceManagerScreen> {
  final _scienceController = TextEditingController();
  final _searchController = TextEditingController();

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _addScience() async {
    final name = _scienceController.text.trim();
    if (name.isEmpty) return;

    final dupSnap = await FirebaseFirestore.instance
        .collection('sciences')
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    if (dupSnap.docs.isNotEmpty) {
      _showSnackBar('Ez a tudomány már létezik.');
      return;
    }

    await FirebaseFirestore.instance.collection('sciences').add({'name': name});
    _scienceController.clear();
    _showSnackBar('Tudomány sikeresen hozzáadva.');
  }

  Future<void> _deleteScience(String docId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Megerősítés'),
        content: Text('Biztosan törlöd a(z) "$name" tudományt?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Mégse')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Törlés', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await FirebaseFirestore.instance.collection('sciences').doc(docId).delete();
    _showSnackBar('Törölve.');
  }

  void _showEditDialog(BuildContext context, String docId, String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tudomány átnevezése'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Új név')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Mégse')),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              // Capture messenger before async gaps to avoid using context across awaits
              final messenger = ScaffoldMessenger.of(context);
              final dup = await FirebaseFirestore.instance
                  .collection('sciences')
                  .where('name', isEqualTo: newName)
                  .limit(1)
                  .get();
              if (dup.docs.isNotEmpty && dup.docs.first.id != docId) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Ez a név már foglalt.'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              await FirebaseFirestore.instance
                  .collection('sciences')
                  .doc(docId)
                  .update({'name': newName});
              if (!mounted) return;
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Frissítve.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Mentés'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 249, 250, 251),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'sciences'),
          Expanded(
            child: Column(
              children: [
                Header(onSearchChanged: (_) {}),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tudományok kezelése',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _scienceController,
                                decoration: const InputDecoration(
                                    labelText: 'Új tudomány neve'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                                onPressed: _addScience,
                                child: const Text('Hozzáadás')),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text('Tudományok:',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                              labelText: 'Keresés tudományok között',
                              prefixIcon: Icon(Icons.search)),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('sciences')
                                .orderBy('name')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              if (!snapshot.hasData ||
                                  snapshot.data!.docs.isEmpty) {
                                return const Text('Nincs elérhető tudomány.');
                              }
                              final all = snapshot.data!.docs;
                              final filtered = all.where((d) {
                                final name = d['name'] as String;
                                return name.toLowerCase().contains(
                                    _searchController.text.toLowerCase());
                              }).toList();
                              if (filtered.isEmpty) {
                                return const Text('Nincs találat a keresésre.');
                              }
                              return ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final doc = filtered[index];
                                  final name = doc['name'] as String;
                                  return ListTile(
                                    title: Text(name),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () => _showEditDialog(
                                              context, doc.id, name),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () =>
                                              _deleteScience(doc.id, name),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
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
