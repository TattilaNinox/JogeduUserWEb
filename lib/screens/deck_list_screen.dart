import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../widgets/sidebar.dart';

class DeckListScreen extends StatelessWidget {
  const DeckListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tanulókártya Paklik'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                final newDeckRef =
                    FirebaseFirestore.instance.collection('notes').doc();
                newDeckRef.set({
                  'title': 'Új pakli',
                  'type': 'deck',
                  'status': 'Draft',
                  'flashcards': [],
                  'createdAt': Timestamp.now(),
                  'modified': Timestamp.now(),
                }).then((_) {
                  if (context.mounted) {
                    context.go('/decks/edit/${newDeckRef.id}');
                  }
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Új Pakli'),
            ),
          )
        ],
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'decks'),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notes')
                  .where('type', isEqualTo: 'deck')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Hiba: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text('Nincsenek tanulókártya paklik.'));
                }
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final cards = data['flashcards'] as List<dynamic>? ?? [];
                    return ListTile(
                      leading: const Icon(Icons.style),
                      title: Text(data['title'] ?? 'Névtelen pakli'),
                      subtitle: Text('${cards.length} kártya'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () =>
                                context.go('/decks/edit/${doc.id}'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => doc.reference.delete(),
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
    );
  }
}
