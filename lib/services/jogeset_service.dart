import 'package:flutter/foundation.dart';
import '../core/firebase_config.dart';
import '../models/jogeset_models.dart';

/// Jogeset szolgáltatás Firestore lekérdezésekhez.
///
/// Ez a szolgáltatás felelős a jogesetek lekérdezéséért és szűréséért.
/// A státusz szűrés alkalmazás szinten történik (nem Firestore szabály szinten).
class JogesetService {
  /// Egy dokumentum (paragrafus) összes jogesetének lekérése
  ///
  /// [documentId]: A dokumentum ID (normalizált paragrafus szám, pl. "6_519")
  /// [isAdmin]: Admin felhasználó-e (ha igen, Draft státuszú jogesetek is láthatóak)
  ///
  /// Visszatérési érték: JogesetDocument vagy null, ha nem található
  static Future<JogesetDocument?> getJogesetDocument(
    String documentId, {
    bool isAdmin = false,
  }) async {
    try {
      debugPrint(
          '🔵 JogesetService.getJogesetDocument: documentId=$documentId, isAdmin=$isAdmin');

      final docSnapshot = await FirebaseConfig.firestore
          .collection('jogesetek')
          .doc(documentId)
          .get();

      if (!docSnapshot.exists) {
        debugPrint('🔴 JogesetService: Dokumentum nem található: $documentId');
        return null;
      }

      final data = docSnapshot.data();
      if (data == null) {
        debugPrint('🔴 JogesetService: Dokumentum adatok null: $documentId');
        return null;
      }

      // Dokumentum létrehozása
      final document = JogesetDocument.fromMap(data, documentId);

      // Státusz szűrés alkalmazása
      final filteredJogesetek = filterJogesetekByStatus(
        document.jogesetek,
        isAdmin: isAdmin,
      );

      debugPrint(
          '🔵 JogesetService: ${filteredJogesetek.length} jogeset betöltve (összesen: ${document.jogesetek.length})');

      return JogesetDocument(
        documentId: documentId,
        jogesetek: filteredJogesetek,
        title: document.title, // Megőrizzük a dokumentum title mezőjét
      );
    } catch (e) {
      debugPrint('🔴 JogesetService.getJogesetDocument hiba: $e');
      return null;
    }
  }

  /// Jogesetek szűrése státusz szerint
  ///
  /// [jogesetek]: A szűrendő jogesetek listája
  /// [isAdmin]: Admin felhasználó-e
  ///
  /// Admin esetén: Published és Draft státuszú jogesetek
  /// User esetén: Csak Published státuszú jogesetek
  ///
  /// Visszatérési érték: Szűrt jogesetek listája
  static List<Jogeset> filterJogesetekByStatus(
    List<Jogeset> jogesetek, {
    bool isAdmin = false,
  }) {
    if (isAdmin) {
      // Admin látja a Published és Draft státuszú jogeseteket
      return jogesetek
          .where((jogeset) =>
              jogeset.status == 'Published' || jogeset.status == 'Draft')
          .toList();
    } else {
      // User csak a Published státuszú jogeseteket látja
      return jogesetek
          .where((jogeset) => jogeset.status == 'Published')
          .toList();
    }
  }

  /// Paragrafus szám normalizálása dokumentum ID-vá
  ///
  /// Példák:
  /// - "6:519" -> "6_519"
  /// - "6:519. §" -> "6_519"
  /// - "6:528 1. bek. §" -> "6_528"
  ///
  /// [paragrafus]: A paragrafus szám (pl. "6:519. §")
  ///
  /// Visszatérési érték: Normalizált dokumentum ID
  static String normalizeParagrafus(String paragrafus) {
    // Szóközök eltávolítása elejéről és végéről
    var normalized = paragrafus.trim();

    // Ha van szóköz, csak az első részt vesszük
    if (normalized.contains(' ')) {
      normalized = normalized.split(' ').first;
    }

    // Kettőspont (:) -> aláhúzás (_)
    normalized = normalized.replaceAll(':', '_');

    // Pontok (.) eltávolítása
    normalized = normalized.replaceAll('.', '');

    // § jel eltávolítása
    normalized = normalized.replaceAll('§', '');

    // Szóközök eltávolítása
    normalized = normalized.replaceAll(' ', '');

    return normalized.trim();
  }

  /// Dokumentum ID visszaalakítása paragrafus számra
  ///
  /// Példák:
  /// - "6_519" -> "6:519. §"
  /// - "4_15" -> "4:15. §"
  ///
  /// [documentId]: A dokumentum ID (pl. "6_519")
  ///
  /// Visszatérési érték: Paragrafus szám megjelenítési formátumban
  static String denormalizeParagrafus(String documentId) {
    // Aláhúzás (_) -> kettőspont (:)
    final paragrafus = documentId.replaceAll('_', ':');

    // Hozzáadjuk a ". §" végződést
    return '$paragrafus. §';
  }
}
