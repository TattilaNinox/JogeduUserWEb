import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccessControl {
  // Engedélyezett admin email címek
  static const List<String> allowedAdmins = [
    'tattila.ninox@gmail.com',
    // További admin email címek...
  ];

  // Ellenőrzi, hogy a bejelentkezett felhasználó admin-e
  static Future<bool> isAdminUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Email alapú ellenőrzés
    if (!allowedAdmins.contains(user.email)) {
      return false;
    }

    // Firestore-ban tárolt admin flag ellenőrzése
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      return userDoc.data()?['isAdmin'] == true;
    } catch (e) {
      return false;
    }
  }

  // Környezet alapú ellenőrzés
  static bool isProductionEnvironment() {
    // Production környezetben extra védelem
    const bool isProduction = bool.fromEnvironment('dart.vm.product');
    return isProduction;
  }
}

