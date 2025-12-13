import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {
  // Admin kulcs a Cloud Function hitelesítéshez
  static const String _adminKey =
      'adminkey_2025_09_09_batch_cleanup_secure_token_v1';

  // Cloud Functions base URL
  static const String _baseUrl =
      'https://europe-west1-orlomed-f8f9f.cloudfunctions.net';

  /// Felhasználó alaphelyzetbe állítása - komplex művelet
  /// - Token cleanup (Google Play tokenek törlése)
  /// - Előfizetési státusz nullázása
  /// - Próbaidőszak újraindítása (5 nap)
  static Future<Map<String, dynamic>> resetUserToDefault(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/adminCleanupUserTokensBatch'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'key': _adminKey,
          'userIds': [userId],
          'resetUser': true,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;

        // További Firestore frissítések a prompt szerint
        await _resetUserSubscriptionData(userId);

        return {
          'success': true,
          'message': 'Felhasználó sikeresen alaphelyzetbe állítva',
          'details': result,
        };
      } else {
        return {
          'success': false,
          'message': 'Cloud Function hiba: ${response.statusCode}',
          'error': response.body,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Hiba a token cleanup során',
        'error': e.toString(),
      };
    }
  }

  /// Tömeges felhasználó alaphelyzetbe állítása
  static Future<Map<String, dynamic>> resetMultipleUsers(
      List<String> userIds) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/adminCleanupUserTokensBatch'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'key': _adminKey,
          'userIds': userIds,
          'resetUser': true,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;

        // Tömeges Firestore frissítések
        for (final userId in userIds) {
          await _resetUserSubscriptionData(userId);
        }

        return {
          'success': true,
          'message':
              '${userIds.length} felhasználó sikeresen alaphelyzetbe állítva',
          'details': result,
        };
      } else {
        return {
          'success': false,
          'message': 'Cloud Function hiba: ${response.statusCode}',
          'error': response.body,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Hiba a tömeges token cleanup során',
        'error': e.toString(),
      };
    }
  }

  /// Előfizetési adatok nullázása és próbaidőszak újraindítása (5 nap)
  static Future<void> _resetUserSubscriptionData(String userId) async {
    final now = DateTime.now();
    final trialEnd = now.add(const Duration(days: 5));

    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      // Előfizetés nullázása
      'subscriptionStatus': 'free',
      'isSubscriptionActive': false,
      'subscriptionEndDate': FieldValue.delete(),

      // Próbaidőszak újraindítása (5 nap)
      'freeTrialStartDate': Timestamp.fromDate(now),
      'freeTrialEndDate': Timestamp.fromDate(trialEnd),

      // Frissítési időbélyeg
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Egyéni token cleanup (csak tokenek, felhasználó adatok nem változnak)
  static Future<Map<String, dynamic>> cleanupUserTokens(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/cleanupUserTokens'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'key': _adminKey,
          'userId': userId,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'message': 'Token cleanup sikeres',
          'details': result,
        };
      } else {
        return {
          'success': false,
          'message': 'Token cleanup hiba: ${response.statusCode}',
          'error': response.body,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Hiba a token cleanup során',
        'error': e.toString(),
      };
    }
  }

  /// Manuális refund feldolgozása
  static Future<Map<String, dynamic>> processManualRefund(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/manualRefund'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'key': _adminKey,
          'userId': userId,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'message': 'Manuális refund sikeres',
          'details': result,
        };
      } else {
        return {
          'success': false,
          'message': 'Refund hiba: ${response.statusCode}',
          'error': response.body,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Hiba a refund során',
        'error': e.toString(),
      };
    }
  }
}
