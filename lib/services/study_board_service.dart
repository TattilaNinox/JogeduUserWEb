import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/study_board_models.dart';

class StudyBoardService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _uid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not authenticated');
    }
    return user.uid;
  }

  static CollectionReference<Map<String, dynamic>> _boardsCol() =>
      _db.collection('study_boards');

  static DocumentReference<Map<String, dynamic>> boardRef(String boardId) =>
      _boardsCol().doc(boardId);

  static CollectionReference<Map<String, dynamic>> cardsCol(String boardId) =>
      boardRef(boardId).collection('cards');

  static CollectionReference<Map<String, dynamic>> itemsCol(
    String boardId,
    String cardId,
  ) =>
      cardsCol(boardId).doc(cardId).collection('items');

  static List<StudyBoardColumn> defaultColumns() => const [
        StudyBoardColumn(id: 'later', title: 'Később', order: 0),
        StudyBoardColumn(id: 'doing', title: 'Folyamatban', order: 1),
        StudyBoardColumn(id: 'done', title: 'Kész', order: 2),
      ];

  static Future<String> createBoard({
    required String title,
    List<StudyBoardColumn>? columns,
  }) async {
    final uid = _uid();
    final now = FieldValue.serverTimestamp();
    final cols = (columns ?? defaultColumns()).map((c) => c.toMap()).toList();

    final doc = await _boardsCol().add({
      'ownerUid': uid,
      'title': title.trim(),
      'columns': cols,
      'createdAt': now,
      'updatedAt': now,
    });
    return doc.id;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> myBoardsStream() {
    final uid = _uid();
    return _boardsCol()
        .where('ownerUid', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  static Future<void> renameBoard(String boardId, String title) async {
    final uid = _uid();
    final ref = boardRef(boardId);
    final snap = await ref.get();
    if (!snap.exists) throw StateError('Board not found');
    if ((snap.data() ?? const {})['ownerUid'] != uid) {
      throw StateError('Not owner');
    }
    await ref.update({
      'title': title.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> boardStream(
      String boardId) {
    // ownership enforced by rules
    return boardRef(boardId).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> cardsStream(String boardId,
      {required String columnId}) {
    return cardsCol(boardId)
        .where('columnId', isEqualTo: columnId)
        .orderBy('order')
        .snapshots();
  }

  static Future<String> addCard({
    required String boardId,
    required String columnId,
    required String title,
    String? description,
  }) async {
    final now = FieldValue.serverTimestamp();
    // Compute next order without an index-dependent query.
    // We use a large, monotonic client timestamp so the card naturally appears
    // at the end when ordering by `order`.
    final order = DateTime.now().microsecondsSinceEpoch.toDouble();

    final doc = await cardsCol(boardId).add({
      'title': title.trim(),
      'description': description?.trim(),
      'columnId': columnId,
      'order': order,
      'createdAt': now,
      'updatedAt': now,
    });
    await boardRef(boardId).update({'updatedAt': now});
    return doc.id;
  }

  static Future<void> updateCard({
    required String boardId,
    required String cardId,
    required String title,
    String? description,
  }) async {
    final now = FieldValue.serverTimestamp();
    await cardsCol(boardId).doc(cardId).update({
      'title': title.trim(),
      'description': description?.trim(),
      'updatedAt': now,
    });
    await boardRef(boardId).update({'updatedAt': now});
  }

  static Future<void> moveCard({
    required String boardId,
    required String cardId,
    required String toColumnId,
    required double newOrder,
  }) async {
    final now = FieldValue.serverTimestamp();
    await cardsCol(boardId).doc(cardId).update({
      'columnId': toColumnId,
      'order': newOrder,
      'updatedAt': now,
    });
    await boardRef(boardId).update({'updatedAt': now});
  }

  static Future<void> setCardOrders({
    required String boardId,
    required String columnId,
    required List<String> orderedCardIds,
  }) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    for (var i = 0; i < orderedCardIds.length; i++) {
      final id = orderedCardIds[i];
      batch.update(cardsCol(boardId).doc(id), {
        'order': (i + 1) * 1000.0,
        'updatedAt': now,
        'columnId': columnId,
      });
    }
    batch.update(boardRef(boardId), {'updatedAt': now});
    await batch.commit();
  }

  static Future<void> deleteCard({
    required String boardId,
    required String cardId,
  }) async {
    // delete items subcollection in chunks
    while (true) {
      final snap = await itemsCol(boardId, cardId).limit(200).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await cardsCol(boardId).doc(cardId).delete();
    await boardRef(boardId).update({'updatedAt': FieldValue.serverTimestamp()});
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> itemsStream({
    required String boardId,
    required String cardId,
  }) {
    return itemsCol(boardId, cardId).orderBy('order').snapshots();
  }

  static Future<void> addItem({
    required String boardId,
    required String cardId,
    required String contentType,
    required String contentId,
    String? titleSnapshot,
    String? categorySnapshot,
  }) async {
    // NOTE: use limitToLast to avoid needing a descending composite index.
    final lastSnap =
        await itemsCol(boardId, cardId).orderBy('order').limitToLast(1).get();
    final lastOrder = lastSnap.docs.isNotEmpty
        ? ((lastSnap.docs.first.data()['order'] as num?)?.toDouble() ?? 0.0)
        : 0.0;
    final order = lastOrder + 1000.0;
    await itemsCol(boardId, cardId).add({
      'contentType': contentType,
      'contentId': contentId,
      'order': order,
      if (titleSnapshot != null) 'titleSnapshot': titleSnapshot,
      if (categorySnapshot != null) 'categorySnapshot': categorySnapshot,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await cardsCol(boardId)
        .doc(cardId)
        .update({'updatedAt': FieldValue.serverTimestamp()});
    await boardRef(boardId).update({'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> removeItem({
    required String boardId,
    required String cardId,
    required String itemId,
  }) async {
    await itemsCol(boardId, cardId).doc(itemId).delete();
    await cardsCol(boardId)
        .doc(cardId)
        .update({'updatedAt': FieldValue.serverTimestamp()});
    await boardRef(boardId).update({'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> setItemOrders({
    required String boardId,
    required String cardId,
    required List<String> orderedItemIds,
  }) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    for (var i = 0; i < orderedItemIds.length; i++) {
      batch.update(itemsCol(boardId, cardId).doc(orderedItemIds[i]), {
        'order': (i + 1) * 1000.0,
        'updatedAt': now,
      });
    }
    batch.update(cardsCol(boardId).doc(cardId), {'updatedAt': now});
    batch.update(boardRef(boardId), {'updatedAt': now});
    await batch.commit();
  }

  static Future<void> deleteBoard(String boardId) async {
    // Delete all cards & their items in chunks.
    while (true) {
      final cards = await cardsCol(boardId).limit(50).get();
      if (cards.docs.isEmpty) break;
      for (final card in cards.docs) {
        await deleteCard(boardId: boardId, cardId: card.id);
      }
    }
    await boardRef(boardId).delete();
  }
}
