import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/admin_service.dart';

/// Admin felhasználói műveletek kezelése
///
/// Ez a szolgáltatás kezeli:
/// - Egyéni felhasználói műveleteket (premium aktiválás, teszt felhasználó, stb.)
/// - Dialógusokat a kritikus műveletekhez
/// - Napos input dialógust
class UserActionService {
  /// Megerősítő dialógus kritikus műveletek előtt
  static Future<bool?> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Igen, folytatás'),
          ),
        ],
      ),
    );
  }

  /// Egyszerű párbeszédablak pozitív egész napok megadásához
  static Future<int?> promptDaysDialog(
    BuildContext context, {
    required String title,
    required String label,
    String initialValue = '1',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Mégse'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed <= 0) {
                  Navigator.of(ctx).pop(null);
                } else {
                  Navigator.of(ctx).pop(parsed);
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  /// Felhasználói művelet végrehajtása
  static Future<Map<String, dynamic>> handleUserAction(
    BuildContext context, {
    required String userId,
    required String action,
    required Map<String, dynamic> userData,
  }) async {
    bool success = false;
    String message = '';

    try {
      switch (action) {
        case 'make_test':
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'userType': 'test',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          success = true;
          message = 'Felhasználó teszt típusra állítva';
          break;

        case 'make_normal':
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'userType': 'normal',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          success = true;
          message = 'Felhasználó normál típusra állítva';
          break;

        case 'activate_premium':
          final subscriptionEnd = DateTime.now().add(const Duration(days: 30));
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'subscriptionStatus': 'premium',
            'isSubscriptionActive': true,
            'subscriptionEndDate': Timestamp.fromDate(subscriptionEnd),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          success = true;
          message = 'Premium előfizetés aktiválva (30 nap)';
          break;

        case 'set_expired':
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'subscriptionStatus': 'expired',
            'isSubscriptionActive': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          success = true;
          message = 'Előfizetés lejárt státuszra állítva';
          break;

        case 'renew_trial':
          final now = DateTime.now();
          final trialEnd = now.add(const Duration(days: 5));
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'subscriptionStatus': 'free',
            'isSubscriptionActive': false,
            'freeTrialStartDate': Timestamp.fromDate(now),
            'freeTrialEndDate': Timestamp.fromDate(trialEnd),
            'subscriptionEndDate': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          success = true;
          message = '5 napos próbaidőszak újraindítva';
          break;

        case 'extend_trial':
          final result = await _extendTrial(userId);
          success = result['success'];
          message = result['message'];
          break;

        case 'shorten_trial':
          final days = await promptDaysDialog(
            context,
            title: 'Próbaidő rövidítése',
            label: 'Hány napot vonjunk le? (pozitív egész szám)',
            initialValue: '3',
          );
          if (days == null || days <= 0) {
            return {'success': false, 'message': 'Művelet megszakítva.'};
          }
          final result = await _shortenTrial(userId, days);
          success = result['success'];
          message = result['message'];
          break;

        case 'activate':
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'isActive': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          success = true;
          message = 'Felhasználó aktiválva';
          break;

        case 'deactivate':
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'isActive': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          success = true;
          message = 'Felhasználó inaktiválva';
          break;

        case 'reset_to_default':
          final confirm = await showConfirmDialog(
            context,
            title: 'Felhasználó alaphelyzetbe állítása',
            content: 'Biztosan alaphelyzetbe állítod ezt a felhasználót?\n\n'
                '• Előfizetés: FREE-re állítás\n'
                '• Próbaidőszak: 5 napos újraindítás\n'
                '• Token cleanup: Google Play tokenek törlése\n'
                '• Subscription: REFUNDED státuszra\n\n'
                'Ez a művelet nem vonható vissza!',
          );
          if (confirm == true) {
            final result = await AdminService.resetUserToDefault(userId);
            success = result['success'];
            message = result['message'];
          } else {
            success = false;
            message = 'Alaphelyzetbe állítás megszakítva';
          }
          break;

        case 'token_cleanup':
          final confirm = await showConfirmDialog(
            context,
            title: 'Token cleanup',
            content:
                'Törli az összes Google Play token-t ehhez a felhasználóhoz.\n\n'
                'Ez megszakítja az aktív előfizetés-ellenőrzési folyamatokat.',
          );
          if (confirm == true) {
            final result = await AdminService.cleanupUserTokens(userId);
            success = result['success'];
            message = result['message'];
          } else {
            success = false;
            message = 'Token cleanup megszakítva';
          }
          break;

        case 'manual_refund':
          final confirm = await showConfirmDialog(
            context,
            title: 'Manuális refund',
            content: 'Manuális refund feldolgozása ehhez a felhasználóhoz.\n\n'
                'Ez a subscription státuszt REFUNDED-ra állítja.',
          );
          if (confirm == true) {
            final result = await AdminService.processManualRefund(userId);
            success = result['success'];
            message = result['message'];
          } else {
            success = false;
            message = 'Manuális refund megszakítva';
          }
          break;

        default:
          success = false;
          message = 'Ismeretlen művelet: $action';
      }
    } catch (e) {
      success = false;
      message = 'Hiba történt: $e';
    }

    return {'success': success, 'message': message};
  }

  static Future<Map<String, dynamic>> _extendTrial(String userId) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final userSnap = await userRef.get();
    final currentData = userSnap.data();
    final now = DateTime.now();
    final freeTrialTs = currentData?['freeTrialEndDate'] as Timestamp?;
    final trialTs = currentData?['trialEndDate'] as Timestamp?;

    if (freeTrialTs != null) {
      final base =
          freeTrialTs.toDate().isAfter(now) ? freeTrialTs.toDate() : now;
      final newEnd = base.add(const Duration(days: 7));
      await userRef.update({
        'freeTrialEndDate': Timestamp.fromDate(newEnd),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {'success': true, 'message': 'Próbaidő meghosszabbítva (+7 nap)'};
    } else if (trialTs != null) {
      final base = trialTs.toDate().isAfter(now) ? trialTs.toDate() : now;
      final newEnd = base.add(const Duration(days: 7));
      await userRef.update({
        'trialEndDate': Timestamp.fromDate(newEnd),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {'success': true, 'message': 'Próbaidő meghosszabbítva (+7 nap)'};
    } else {
      return {
        'success': false,
        'message':
            'Nincs aktív próbaidő ehhez a felhasználóhoz. Használd az "5 napos próbaidő újraindítása" opciót.'
      };
    }
  }

  static Future<Map<String, dynamic>> _shortenTrial(
      String userId, int days) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final userSnap = await userRef.get();
    final data = userSnap.data();
    final freeTrialTs = data?['freeTrialEndDate'] as Timestamp?;
    final trialTs = data?['trialEndDate'] as Timestamp?;
    final now = DateTime.now();

    if (freeTrialTs != null) {
      DateTime newEnd = freeTrialTs.toDate().subtract(Duration(days: days));
      if (newEnd.isBefore(now)) {
        newEnd = now;
      }
      await userRef.update({
        'freeTrialEndDate': Timestamp.fromDate(newEnd),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {'success': true, 'message': 'Próbaidő rövidítve (−$days nap).'};
    } else if (trialTs != null) {
      DateTime newEnd = trialTs.toDate().subtract(Duration(days: days));
      if (newEnd.isBefore(now)) {
        newEnd = now;
      }
      await userRef.update({
        'trialEndDate': Timestamp.fromDate(newEnd),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {'success': true, 'message': 'Próbaidő rövidítve (−$days nap).'};
    } else {
      return {
        'success': false,
        'message': 'Nincs beállított próbaidő ehhez a felhasználóhoz.'
      };
    }
  }
}
