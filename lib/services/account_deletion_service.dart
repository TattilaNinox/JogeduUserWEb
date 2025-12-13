import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Fióktörlést megvalósító szolgáltatás.
///
/// Lépések:
/// 1) Újrahitelesítés email+jelszóval
/// 2) Best‑effort token takarítás (Cloud Function: cleanupUserTokens, europe-west1)
/// 3) Firestore `users/{uid}` dokumentum törlése
/// 4) Firebase Auth felhasználó törlése
/// 5) Kijelentkezés
class AccountDeletionService {
  /// Teljes fióktörlési folyamat végrehajtása a megadott jelszóval.
  static Future<void> deleteAccount(String password) async {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

    final user = auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-logged-in',
        message: 'Nincs bejelentkezett felhasználó.',
      );
    }

    final email = user.email;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'A fiókhoz nem tartozik email cím.',
      );
    }

    // 1) Újrahitelesítés (kötelező)
    try {
      final credential =
          EmailAuthProvider.credential(email: email, password: password);
      await user.reauthenticateWithCredential(credential);
      debugPrint('[AccountDeletion] Reauth OK for uid=${user.uid}');
    } on FirebaseAuthException catch (e) {
      debugPrint('[AccountDeletion] Reauth failed: ${e.code} ${e.message}');
      rethrow; // A hívó felületen jelenjen meg az üzenet
    }

    // 2) Best‑effort token takarítás – hiba esetén csak naplózunk
    try {
      final callable = functions.httpsCallable('cleanupUserTokens');
      await callable.call(<String, dynamic>{'userId': user.uid});
      debugPrint('[AccountDeletion] cleanupUserTokens OK for uid=${user.uid}');
    } catch (e) {
      debugPrint('[AccountDeletion] cleanupUserTokens failed: $e');
    }

    // 3) Firestore felhasználói dokumentum törlése
    await firestore.collection('users').doc(user.uid).delete();
    debugPrint('[AccountDeletion] Firestore users/${user.uid} deleted');

    // 4) Firebase Auth user törlés
    await user.delete();
    debugPrint('[AccountDeletion] Auth user deleted for uid=${user.uid}');

    // 5) Kijelentkezés
    await auth.signOut();
    debugPrint('[AccountDeletion] Signed out');
  }
}
