import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Session-alapú cache a jegyzetek betöltéséhez.
/// A cache az alkalmazás futása alatt megmarad, nincs időkorlát.
/// Csak akkor törlődik, ha explicit invalidálás történik vagy az app újraindul.
class NoteSessionCache {
  // Kategória szintű cache
  static final Map<String, CachedCategoryData> _categoryCache = {};

  // Címke szintű cache
  static final Map<String, CachedTagData> _tagCache = {};

  // Betöltött jegyzetek ID-k nyilvántartása (duplikáció elkerülése)
  static final Set<String> _loadedNoteIds = {};

  /// Kategória cache mentése
  static void cacheCategory({
    required String category,
    required List<String> tags,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> untaggedNotes,
  }) {
    _categoryCache[category] = CachedCategoryData(
      tags: tags,
      untaggedNotes: untaggedNotes,
      cachedAt: DateTime.now(),
    );

    // Jegyzet ID-k nyilvántartása
    for (var doc in untaggedNotes) {
      _loadedNoteIds.add(doc.id);
    }

    if (kDebugMode) {
      debugPrint(
          '✅ Cache: Kategória "$category" mentve (${tags.length} címke, ${untaggedNotes.length} címke nélküli jegyzet)');
    }
  }

  /// Kategória cache lekérése
  static CachedCategoryData? getCategoryCache(String category) {
    final cached = _categoryCache[category];
    if (cached != null && kDebugMode) {
      debugPrint(
          '💾 Cache HIT: Kategória "$category" (${cached.tags.length} címke)');
    }
    return cached;
  }

  /// Címke cache mentése
  static void cacheTag({
    required String category,
    required List<String> tagPath,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> notes,
    required List<String> subTags,
  }) {
    final key = _buildTagKey(category, tagPath);
    _tagCache[key] = CachedTagData(
      notes: notes,
      subTags: subTags,
      cachedAt: DateTime.now(),
    );

    // Jegyzet ID-k nyilvántartása
    for (var doc in notes) {
      _loadedNoteIds.add(doc.id);
    }

    if (kDebugMode) {
      debugPrint(
          '✅ Cache: Címke "$key" mentve (${notes.length} jegyzet, ${subTags.length} alcímke)');
    }
  }

  /// Címke cache lekérése
  static CachedTagData? getTagCache(String category, List<String> tagPath) {
    final key = _buildTagKey(category, tagPath);
    final cached = _tagCache[key];
    if (cached != null && kDebugMode) {
      debugPrint('💾 Cache HIT: Címke "$key" (${cached.notes.length} jegyzet)');
    }
    return cached;
  }

  /// Ellenőrzi, hogy egy jegyzet már be van-e töltve
  static bool isNoteLoaded(String noteId) {
    return _loadedNoteIds.contains(noteId);
  }

  /// Kategória cache invalidálása (pl. admin módosítás után)
  static void invalidateCategory(String category) {
    _categoryCache.remove(category);
    // Töröljük az összes kapcsolódó címke cache-t is
    _tagCache.removeWhere((key, _) => key.startsWith('$category/'));

    if (kDebugMode) {
      debugPrint('🗑️ Cache INVALIDATED: Kategória "$category"');
    }
  }

  /// Címke cache invalidálása
  static void invalidateTag(String category, List<String> tagPath) {
    final key = _buildTagKey(category, tagPath);
    _tagCache.remove(key);

    if (kDebugMode) {
      debugPrint('🗑️ Cache INVALIDATED: Címke "$key"');
    }
  }

  /// Teljes cache törlése (pl. kijelentkezéskor)
  static void clearAll() {
    final categoryCount = _categoryCache.length;
    final tagCount = _tagCache.length;
    final noteCount = _loadedNoteIds.length;

    _categoryCache.clear();
    _tagCache.clear();
    _loadedNoteIds.clear();

    if (kDebugMode) {
      debugPrint(
          '🗑️ Cache CLEARED: $categoryCount kategória, $tagCount címke, $noteCount jegyzet');
    }
  }

  /// Cache kulcs generálása címke útvonalból
  static String _buildTagKey(String category, List<String> tagPath) {
    return '$category/${tagPath.join('/')}';
  }

  /// Cache statisztika (debug célra)
  static Map<String, int> getStats() {
    return {
      'categories': _categoryCache.length,
      'tags': _tagCache.length,
      'loadedNotes': _loadedNoteIds.length,
    };
  }
}

/// Kategória cache adat
class CachedCategoryData {
  final List<String> tags;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> untaggedNotes;
  final DateTime cachedAt;

  CachedCategoryData({
    required this.tags,
    required this.untaggedNotes,
    required this.cachedAt,
  });
}

/// Címke cache adat
class CachedTagData {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> notes;
  final List<String> subTags;
  final DateTime cachedAt;

  CachedTagData({
    required this.notes,
    required this.subTags,
    required this.cachedAt,
  });
}
