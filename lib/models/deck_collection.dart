import 'package:cloud_firestore/cloud_firestore.dart';

/// Pakli gyűjteményt reprezentáló modell.
/// A deck_collections Firestore collection dokumentumait kezeli.
class DeckCollection {
  final String id;
  final String title;
  final String science;
  final String? category;
  final String? parentTag;
  final List<String> deckIds;
  final Timestamp createdAt;
  final Timestamp modified;

  const DeckCollection({
    required this.id,
    required this.title,
    required this.science,
    this.category,
    this.parentTag,
    required this.deckIds,
    required this.createdAt,
    required this.modified,
  });

  factory DeckCollection.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeckCollection(
      id: doc.id,
      title: data['title'] as String? ?? '',
      science: data['science'] as String? ?? 'Jogász',
      category: data['category'] as String?,
      parentTag: data['parentTag'] as String?,
      deckIds: List<String>.from(data['deckIds'] ?? []),
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      modified: data['modified'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'science': science,
      'category': category,
      'parentTag': parentTag,
      'deckIds': deckIds,
      'createdAt': createdAt,
      'modified': modified,
    };
  }

  /// Paklik száma a gyűjteményben
  int get deckCount => deckIds.length;
}
