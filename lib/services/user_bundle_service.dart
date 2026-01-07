import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
import '../models/user_bundle.dart';
import '../models/user_bundle_item.dart';

/// Felhasználói kötegek kezelése.
///
/// Subcollection alapú architektúra a skálázhatóságért és
/// szerveroldali szűrés támogatásáért.
class UserBundleService {
  static final _firestore = FirebaseConfig.firestore;

  /// Az aktuális felhasználó ID-ja.
  static String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  /// Bundles kollekció referencia.
  static CollectionReference<Map<String, dynamic>> _bundlesRef(String userId) {
    return _firestore.collection('users').doc(userId).collection('bundles');
  }

  /// Items subcollection referencia.
  static CollectionReference<Map<String, dynamic>> _itemsRef(
    String userId,
    String bundleId,
  ) {
    return _bundlesRef(userId).doc(bundleId).collection('items');
  }

  // ============================================================
  // BUNDLE CRUD
  // ============================================================

  /// Felhasználó kötegeinek streamje.
  static Stream<List<UserBundle>> getUserBundles() {
    final userId = _userId;
    if (userId == null) return Stream.value([]);

    return _bundlesRef(userId).orderBy('name').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => UserBundle.fromFirestore(doc)).toList());
  }

  /// Egyedi köteg lekérése.
  static Future<UserBundle?> getBundle(String bundleId) async {
    final userId = _userId;
    if (userId == null) return null;

    final doc = await _bundlesRef(userId).doc(bundleId).get();
    if (!doc.exists) return null;
    return UserBundle.fromFirestore(doc);
  }

  /// Új köteg létrehozása.
  static Future<String> createBundle({
    required String name,
    String description = '',
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Nincs bejelentkezett felhasználó');

    final bundle = UserBundle(
      id: '',
      name: name,
      description: description,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );

    final docRef = await _bundlesRef(userId).add(bundle.toFirestore());
    return docRef.id;
  }

  /// Köteg frissítése.
  static Future<void> updateBundle(UserBundle bundle) async {
    final userId = _userId;
    if (userId == null) return;

    await _bundlesRef(userId).doc(bundle.id).update(bundle.toFirestore());
  }

  /// Köteg törlése (az összes elemével együtt).
  static Future<void> deleteBundle(String bundleId) async {
    final userId = _userId;
    if (userId == null) return;

    // Töröljük az összes itemet a subcollection-ből
    final itemsSnapshot = await _itemsRef(userId, bundleId).get();
    final batch = _firestore.batch();
    for (final doc in itemsSnapshot.docs) {
      batch.delete(doc.reference);
    }
    // Töröljük magát a bundle-t
    batch.delete(_bundlesRef(userId).doc(bundleId));
    await batch.commit();
  }

  // ============================================================
  // ITEMS CRUD (Subcollection)
  // ============================================================

  /// Eredmény típus a paginált lekérdezéshez.
  static Future<ItemsPageResult> getItems(
    String bundleId, {
    DocumentSnapshot? lastDocument,
    int limit = 20,
    String? scienceFilter,
    String? typeFilter,
    String? tagFilter,
  }) async {
    final userId = _userId;
    if (userId == null) return ItemsPageResult(items: [], lastDoc: null);

    Query<Map<String, dynamic>> query =
        _itemsRef(userId, bundleId).orderBy('addedAt', descending: true);

    if (scienceFilter != null) {
      query = query.where('science', isEqualTo: scienceFilter);
    }
    if (typeFilter != null) {
      query = query.where('type', isEqualTo: typeFilter);
    }
    if (tagFilter != null) {
      query = query.where('tags', arrayContains: tagFilter);
    }

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }

    final snapshot = await query.limit(limit).get();
    final items =
        snapshot.docs.map((doc) => UserBundleItem.fromFirestore(doc)).toList();

    return ItemsPageResult(
      items: items,
      lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
    );
  }

  /// Elem hozzáadása a köteghez.
  ///
  /// Lekéri az eredeti dokumentum metaadatait és létrehoz egy
  /// denormalizált itemet a subcollection-ben.
  static Future<void> addItemToBundle({
    required String bundleId,
    required String originalId,
    required String originalCollection,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    // Ellenőrizzük, hogy az elem már benne van-e
    final existingQuery = await _itemsRef(userId, bundleId)
        .where('originalId', isEqualTo: originalId)
        .limit(1)
        .get();
    if (existingQuery.docs.isNotEmpty) {
      return; // Már benne van
    }

    // Lekérjük az eredeti dokumentum adatait
    final originalDoc =
        await _firestore.collection(originalCollection).doc(originalId).get();
    if (!originalDoc.exists) {
      throw Exception('Az eredeti dokumentum nem található');
    }

    final data = originalDoc.data()!;

    // Típus meghatározása a collection alapján
    String itemType;
    if (originalCollection == 'jogesetek') {
      itemType = 'jogeset';
    } else if (originalCollection == 'dialogus_fajlok') {
      itemType = 'dialogus';
    } else if (originalCollection == 'memoriapalota_allomasok') {
      itemType = 'allomas';
    } else {
      itemType = data['type'] ?? 'text';
    }

    // Cím meghatározása (különböző mezőnevek kezelése)
    final title = data['title'] ??
        data['name'] ??
        data['utvonalNev'] ??
        data['cim'] ??
        data['documentId'] ??
        'Névtelen';

    final item = UserBundleItem(
      id: '',
      originalId: originalId,
      originalCollection: originalCollection,
      title: title,
      type: itemType,
      science: data['science'],
      category: data['category'],
      tags: List<String>.from(data['tags'] ?? []),
      status: data['status'],
      addedAt: DateTime.now(),
    );

    // Transaction: Item létrehozása + számláló növelése
    await _firestore.runTransaction((transaction) async {
      final bundleRef = _bundlesRef(userId).doc(bundleId);
      final bundleDoc = await transaction.get(bundleRef);

      if (!bundleDoc.exists) {
        throw Exception('A köteg nem található');
      }

      final bundle = UserBundle.fromFirestore(bundleDoc);
      final updatedBundle = bundle.incrementCounter(itemType);

      // Item hozzáadása
      final itemRef = _itemsRef(userId, bundleId).doc();
      transaction.set(itemRef, item.toFirestore());

      // Számláló frissítése
      transaction.update(bundleRef, {
        'totalCount': updatedBundle.totalCount,
        'noteCount': updatedBundle.noteCount,
        'jogesetCount': updatedBundle.jogesetCount,
        'dialogusCount': updatedBundle.dialogusCount,
        'allomasCount': updatedBundle.allomasCount,
        'modifiedAt': Timestamp.now(),
      });
    });
  }

  /// Elem eltávolítása a kötegből.
  static Future<void> removeItemFromBundle({
    required String bundleId,
    required String itemId,
    required String itemType,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    await _firestore.runTransaction((transaction) async {
      final bundleRef = _bundlesRef(userId).doc(bundleId);
      final bundleDoc = await transaction.get(bundleRef);

      if (!bundleDoc.exists) return;

      final bundle = UserBundle.fromFirestore(bundleDoc);
      final updatedBundle = bundle.decrementCounter(itemType);

      // Item törlése
      final itemRef = _itemsRef(userId, bundleId).doc(itemId);
      transaction.delete(itemRef);

      // Számláló frissítése
      transaction.update(bundleRef, {
        'totalCount': updatedBundle.totalCount,
        'noteCount': updatedBundle.noteCount,
        'jogesetCount': updatedBundle.jogesetCount,
        'dialogusCount': updatedBundle.dialogusCount,
        'allomasCount': updatedBundle.allomasCount,
        'modifiedAt': Timestamp.now(),
      });
    });
  }

  // ============================================================
  // LAZY CLEANUP
  // ============================================================

  /// Érvénytelen elem eltávolítása (ha az eredeti már nem létezik).
  static Future<void> cleanupInvalidItem({
    required String bundleId,
    required UserBundleItem item,
  }) async {
    await removeItemFromBundle(
      bundleId: bundleId,
      itemId: item.id,
      itemType: item.type,
    );
  }

  /// Ellenőrzi, hogy az eredeti dokumentum létezik-e.
  static Future<bool> checkOriginalExists(UserBundleItem item) async {
    final doc = await _firestore
        .collection(item.originalCollection)
        .doc(item.originalId)
        .get();
    return doc.exists;
  }
}

/// Paginált lekérdezés eredménye.
class ItemsPageResult {
  final List<UserBundleItem> items;
  final DocumentSnapshot? lastDoc;

  ItemsPageResult({required this.items, required this.lastDoc});
}
