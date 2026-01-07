import 'package:cloud_firestore/cloud_firestore.dart';

/// Felhasználói köteg reprezentációja.
///
/// A köteg számlálókat tartalmaz a gyors listázáshoz,
/// az elemek külön subcollection-ben vannak tárolva.
class UserBundle {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime modifiedAt;

  // Aggregált számlálók (típusonként)
  final int totalCount;
  final int noteCount;
  final int jogesetCount;
  final int dialogusCount;
  final int allomasCount;

  UserBundle({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    required this.modifiedAt,
    this.totalCount = 0,
    this.noteCount = 0,
    this.jogesetCount = 0,
    this.dialogusCount = 0,
    this.allomasCount = 0,
  });

  /// Firestore dokumentumból konvertálás.
  factory UserBundle.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserBundle(
      id: doc.id,
      name: data['name'] ?? 'Névtelen köteg',
      description: data['description'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      modifiedAt:
          (data['modifiedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalCount: data['totalCount'] ?? 0,
      noteCount: data['noteCount'] ?? 0,
      jogesetCount: data['jogesetCount'] ?? 0,
      dialogusCount: data['dialogusCount'] ?? 0,
      allomasCount: data['allomasCount'] ?? 0,
    );
  }

  /// Firestore-ba mentéshez.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'createdAt': Timestamp.fromDate(createdAt),
      'modifiedAt': Timestamp.fromDate(modifiedAt),
      'totalCount': totalCount,
      'noteCount': noteCount,
      'jogesetCount': jogesetCount,
      'dialogusCount': dialogusCount,
      'allomasCount': allomasCount,
    };
  }

  /// Másolat módosított mezőkkel.
  UserBundle copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? totalCount,
    int? noteCount,
    int? jogesetCount,
    int? dialogusCount,
    int? allomasCount,
  }) {
    return UserBundle(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      totalCount: totalCount ?? this.totalCount,
      noteCount: noteCount ?? this.noteCount,
      jogesetCount: jogesetCount ?? this.jogesetCount,
      dialogusCount: dialogusCount ?? this.dialogusCount,
      allomasCount: allomasCount ?? this.allomasCount,
    );
  }

  /// Számláló növelése típus alapján.
  UserBundle incrementCounter(String itemType) {
    int newNoteCount = noteCount;
    int newJogesetCount = jogesetCount;
    int newDialogusCount = dialogusCount;
    int newAllomasCount = allomasCount;

    switch (itemType) {
      case 'jogeset':
        newJogesetCount++;
        break;
      case 'dialogus':
        newDialogusCount++;
        break;
      case 'allomas':
        newAllomasCount++;
        break;
      default:
        newNoteCount++;
    }

    return copyWith(
      totalCount: totalCount + 1,
      noteCount: newNoteCount,
      jogesetCount: newJogesetCount,
      dialogusCount: newDialogusCount,
      allomasCount: newAllomasCount,
      modifiedAt: DateTime.now(),
    );
  }

  /// Számláló csökkentése típus alapján.
  UserBundle decrementCounter(String itemType) {
    int newNoteCount = noteCount;
    int newJogesetCount = jogesetCount;
    int newDialogusCount = dialogusCount;
    int newAllomasCount = allomasCount;

    switch (itemType) {
      case 'jogeset':
        newJogesetCount = (newJogesetCount - 1).clamp(0, 999999);
        break;
      case 'dialogus':
        newDialogusCount = (newDialogusCount - 1).clamp(0, 999999);
        break;
      case 'allomas':
        newAllomasCount = (newAllomasCount - 1).clamp(0, 999999);
        break;
      default:
        newNoteCount = (newNoteCount - 1).clamp(0, 999999);
    }

    return copyWith(
      totalCount: (totalCount - 1).clamp(0, 999999),
      noteCount: newNoteCount,
      jogesetCount: newJogesetCount,
      dialogusCount: newDialogusCount,
      allomasCount: newAllomasCount,
      modifiedAt: DateTime.now(),
    );
  }
}
