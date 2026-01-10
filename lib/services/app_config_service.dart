import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/firebase_config.dart';

/// Alkalmazás globális konfigurációs szolgáltatás.
/// Regisztrációs beállítások és egyéb app-szintű konfiguráció kezelése.
class AppConfigService {
  static final AppConfigService _instance = AppConfigService._internal();
  factory AppConfigService() => _instance;
  AppConfigService._internal();

  /// A Firestore gyűjtemény és dokumentum nevek
  static const String _collection = 'app_config';
  static const String _registrationDoc = 'registration';

  /// Regisztrációs konfiguráció stream (valós idejű figyelés)
  Stream<bool> isRegistrationEnabledStream() {
    return FirebaseConfig.firestore
        .collection(_collection)
        .doc(_registrationDoc)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        // Ha nincs dokumentum, alapértelmezetten engedélyezett
        return true;
      }
      final data = snapshot.data() ?? {};
      return data['isEnabled'] == true;
    });
  }

  /// Regisztrációs konfiguráció egyszeri lekérdezése
  Future<bool> isRegistrationEnabled() async {
    try {
      final doc = await FirebaseConfig.firestore
          .collection(_collection)
          .doc(_registrationDoc)
          .get();

      if (!doc.exists) {
        // Ha nincs dokumentum, alapértelmezetten engedélyezett
        return true;
      }
      final data = doc.data() ?? {};
      return data['isEnabled'] == true;
    } catch (e) {
      // Hiba esetén alapértelmezetten engedélyezett (megakadályozza a blokkolást)
      return true;
    }
  }

  /// Teljes regisztrációs konfiguráció lekérdezése
  Future<Map<String, dynamic>> getRegistrationConfig() async {
    try {
      final doc = await FirebaseConfig.firestore
          .collection(_collection)
          .doc(_registrationDoc)
          .get();

      if (!doc.exists) {
        return {
          'isEnabled': true,
          'maxUsers': null,
          'updatedAt': null,
          'updatedBy': null,
        };
      }
      return doc.data() ?? {};
    } catch (e) {
      return {
        'isEnabled': true,
        'maxUsers': null,
        'updatedAt': null,
        'updatedBy': null,
      };
    }
  }

  /// Regisztráció engedélyezése/tiltása (csak admin számára)
  Future<void> setRegistrationEnabled(bool enabled, String adminEmail) async {
    await FirebaseConfig.firestore
        .collection(_collection)
        .doc(_registrationDoc)
        .set({
      'isEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminEmail,
    }, SetOptions(merge: true));
  }

  /// Maximum felhasználószám beállítása (opcionális)
  Future<void> setMaxUsers(int? maxUsers, String adminEmail) async {
    await FirebaseConfig.firestore
        .collection(_collection)
        .doc(_registrationDoc)
        .set({
      'maxUsers': maxUsers,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminEmail,
    }, SetOptions(merge: true));
  }
}
