import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';

/// Felhasználói jogosultságokat és státuszt központosító szerviz.
/// Megakadályozza a felesleges ismételt Firestore lekérdezéseket.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  bool? _isAdmin;
  bool? _hasPremiumAccess;
  String? _cachedUserId;

  /// Törli a gyorsítótárazott adatokat (pl. kijelentkezéskor).
  void clearCache() {
    _isAdmin = null;
    _hasPremiumAccess = null;
    _cachedUserId = null;
  }

  /// Ellenőrzi, hogy az aktuális felhasználó admin-e.
  Future<bool> isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Ha ugyanaz a felhasználó és már van cache, adjuk vissza azt
    if (_cachedUserId == user.uid && _isAdmin != null) {
      return _isAdmin!;
    }

    try {
      final userDoc = await FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data() ?? {};
      final userType = (userData['userType'] as String? ?? '').toLowerCase();
      final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
      final isAdminBool = userData['isAdmin'] == true;

      _isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;
      _cachedUserId = user.uid;

      return _isAdmin!;
    } catch (e) {
      return false;
    }
  }

  /// Ellenőrzi, hogy a felhasználónak van-e prémium hozzáférése (előfizetés vagy próbaidő).
  Future<bool> hasPremiumAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    if (_cachedUserId == user.uid && _hasPremiumAccess != null) {
      return _hasPremiumAccess!;
    }

    try {
      final userDoc = await FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data() ?? {};

      // Próbaidő ellenőrzése
      final trialEndDate = userData['freeTrialEndDate'] as Timestamp?;
      final isTrialActive =
          trialEndDate != null && trialEndDate.toDate().isAfter(DateTime.now());

      // Előfizetés ellenőrzése
      bool isSubActive = userData['isSubscriptionActive'] ?? false;
      final subEndDate = userData['subscriptionEndDate'] as Timestamp?;
      if (subEndDate != null) {
        isSubActive = subEndDate.toDate().isAfter(DateTime.now());
      }

      _hasPremiumAccess = isTrialActive || isSubActive;
      _cachedUserId = user.uid;

      return _hasPremiumAccess!;
    } catch (e) {
      return false;
    }
  }
}
