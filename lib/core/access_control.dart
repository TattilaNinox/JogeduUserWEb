import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_config.dart';

class AccessControl {
  // Engedélyezett admin email címek
  static const List<String> allowedAdmins = [
    'tattila.ninox@gmail.com',
    // További admin email címek...
  ];

  /// Ellenőrzi, hogy a bejelentkezett felhasználó admin-e
  /// Több módszert használ: email, userType, isAdmin flag
  static Future<bool> isAdminUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final userDoc = await FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data() ?? {};
      final userType = (userData['userType'] as String? ?? '').toLowerCase();
      final isAdminEmail = user.email != null && allowedAdmins.contains(user.email);
      final isAdminBool = userData['isAdmin'] == true;

      return userType == 'admin' || isAdminEmail || isAdminBool;
    } catch (e) {
      // Ha hiba van, csak email alapján ellenőrizzük
      return user.email != null && allowedAdmins.contains(user.email);
    }
  }

  /// Szinkron admin ellenőrzés userData alapján (StreamBuilder-ekhez)
  /// Használja a már betöltött userData-t, hogy ne kelljen újra lekérdezni
  static bool isAdminUserSync(Map<String, dynamic>? userData, String? userEmail) {
    if (userData == null) {
      return userEmail != null && allowedAdmins.contains(userEmail);
    }

    final userType = (userData['userType'] as String? ?? '').toLowerCase();
    final isAdminEmail = userEmail != null && allowedAdmins.contains(userEmail);
    final isAdminBool = userData['isAdmin'] == true;

    return userType == 'admin' || isAdminEmail || isAdminBool;
  }

  /// Visszaadja a felhasználó tudományágát
  /// Webalkalmazásban MINDIG "Jogász"
  static String getUserScience() {
    return 'Jogász';
  }

  /// Környezet alapú ellenőrzés
  static bool isProductionEnvironment() {
    // Production környezetben extra védelem
    const bool isProduction = bool.fromEnvironment('dart.vm.product');
    return isProduction;
  }
}

