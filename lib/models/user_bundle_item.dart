import 'package:cloud_firestore/cloud_firestore.dart';

/// Egy kötegben lévő elem reprezentációja.
///
/// Denormalizált metaadatokat tartalmaz a hatékony listázáshoz és szűréshez,
/// anélkül hogy az eredeti dokumentumot le kellene kérdezni.
class UserBundleItem {
  final String id;
  final String originalId;
  final String originalCollection;

  // Denormalizált metaadatok
  final String title;
  final String type;
  final String? science;
  final String? category;
  final List<String> tags;
  final String? status;

  // Rendezéshez
  final DateTime addedAt;

  UserBundleItem({
    required this.id,
    required this.originalId,
    required this.originalCollection,
    required this.title,
    required this.type,
    this.science,
    this.category,
    this.tags = const [],
    this.status,
    required this.addedAt,
  });

  /// Firestore dokumentumból konvertálás.
  factory UserBundleItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserBundleItem(
      id: doc.id,
      originalId: data['originalId'] ?? '',
      originalCollection: data['originalCollection'] ?? 'notes',
      title: data['title'] ?? 'Névtelen',
      type: data['type'] ?? 'text',
      science: data['science'],
      category: data['category'],
      tags: List<String>.from(data['tags'] ?? []),
      status: data['status'],
      addedAt: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Firestore-ba mentéshez.
  Map<String, dynamic> toFirestore() {
    return {
      'originalId': originalId,
      'originalCollection': originalCollection,
      'title': title,
      'type': type,
      'science': science,
      'category': category,
      'tags': tags,
      'status': status,
      'addedAt': Timestamp.fromDate(addedAt),
    };
  }

  /// Másolat módosított mezőkkel.
  UserBundleItem copyWith({
    String? id,
    String? originalId,
    String? originalCollection,
    String? title,
    String? type,
    String? science,
    String? category,
    List<String>? tags,
    String? status,
    DateTime? addedAt,
  }) {
    return UserBundleItem(
      id: id ?? this.id,
      originalId: originalId ?? this.originalId,
      originalCollection: originalCollection ?? this.originalCollection,
      title: title ?? this.title,
      type: type ?? this.type,
      science: science ?? this.science,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}
