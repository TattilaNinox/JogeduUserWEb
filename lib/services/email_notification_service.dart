import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Email értesítési szolgáltatás
///
/// Kezeli az előfizetési emlékeztetők és értesítések küldését
class EmailNotificationService {
  // A Cloud Functions függvényeink az "europe-west1" régióban futnak,
  // ezért kifejezetten oda kell irányítani a hívásokat, különben
  // NOT_FOUND hibát kapnánk.
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Lejárat előtti emlékeztető email küldése
  static Future<bool> sendExpiryWarningEmail({
    required String userId,
    required int daysLeft,
  }) async {
    try {
      final callable = _functions.httpsCallable('sendSubscriptionReminder');

      final result = await callable.call({
        'userId': userId,
        'reminderType': 'expiry_warning',
        'daysLeft': daysLeft,
      });

      if (result.data['success'] == true) {
        debugPrint('Expiry warning email sent successfully');
        return true;
      } else {
        debugPrint('Failed to send expiry warning email: ${result.data}');
        return false;
      }
    } catch (e) {
      debugPrint('Error sending expiry warning email: $e');
      return false;
    }
  }

  /// Lejárat utáni értesítő email küldése
  static Future<bool> sendExpiredNotificationEmail({
    required String userId,
  }) async {
    try {
      final callable = _functions.httpsCallable('sendSubscriptionReminder');

      final result = await callable.call({
        'userId': userId,
        'reminderType': 'expired',
      });

      if (result.data['success'] == true) {
        debugPrint('Expired notification email sent successfully');
        return true;
      } else {
        debugPrint('Failed to send expired notification email: ${result.data}');
        return false;
      }
    } catch (e) {
      debugPrint('Error sending expired notification email: $e');
      return false;
    }
  }

  /// Automatikus emlékeztető ellenőrzés futtatása
  static Future<bool> checkSubscriptionExpiry() async {
    try {
      final callable = _functions.httpsCallable('checkSubscriptionExpiry');

      final result = await callable.call();

      if (result.data['success'] == true) {
        final emailsSent = result.data['emailsSent'] ?? 0;
        debugPrint(
            'Subscription expiry check completed. $emailsSent emails sent.');
        return true;
      } else {
        debugPrint('Failed to check subscription expiry: ${result.data}');
        return false;
      }
    } catch (e) {
      debugPrint('Error checking subscription expiry: $e');
      return false;
    }
  }

  /// Teszt email küldése a jelenlegi felhasználónak
  static Future<bool> sendTestEmail({
    required String testType,
    int? daysLeft,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No authenticated user found');
      return false;
    }

    if (testType == 'expiry_warning' && daysLeft != null) {
      return await sendExpiryWarningEmail(
        userId: user.uid,
        daysLeft: daysLeft,
      );
    } else if (testType == 'expired') {
      return await sendExpiredNotificationEmail(
        userId: user.uid,
      );
    } else {
      debugPrint('Invalid test type: $testType');
      return false;
    }
  }
}
