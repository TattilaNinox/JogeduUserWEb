import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Előfizetési emlékeztető service
///
/// Kezeli a lejárat előtti emlékeztetőket és értesítéseket
/// a prepaid előfizetési rendszerhez.
class SubscriptionReminderService {
  static const String _lastReminderKey = 'last_subscription_reminder';
  static const String _expiryNotificationKey =
      'subscription_expiry_notification';

  /// Ellenőrzi, hogy szükséges-e emlékeztető megjelenítése
  static Future<bool> shouldShowReminder(String userId) async {
    try {
      // Ellenőrizzük, hogy van-e aktív előfizetés
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data()!;
      final subscriptionStatus = data['subscriptionStatus'] ?? 'free';
      final isSubscriptionActive = data['isSubscriptionActive'] ?? false;
      final subscriptionEndDate = data['subscriptionEndDate'];

      // Csak aktív premium előfizetés esetén
      if (subscriptionStatus != 'premium' || !isSubscriptionActive) {
        return false;
      }

      if (subscriptionEndDate == null) return false;

      // Dátum konvertálás
      DateTime endDateTime;
      if (subscriptionEndDate is Timestamp) {
        endDateTime = subscriptionEndDate.toDate();
      } else if (subscriptionEndDate is String) {
        endDateTime = DateTime.parse(subscriptionEndDate);
      } else {
        return false;
      }

      final now = DateTime.now();
      final daysUntilExpiry = endDateTime.difference(now).inDays;

      // 3 nap vagy kevesebb van hátra
      if (daysUntilExpiry <= 3 && daysUntilExpiry > 0) {
        return await _shouldShowReminderForDays(daysUntilExpiry);
      }

      return false;
    } catch (e) {
      debugPrint('SubscriptionReminderService: Error checking reminder: $e');
      return false;
    }
  }

  /// Ellenőrzi, hogy lejárt-e az előfizetés
  static Future<bool> isSubscriptionExpired(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data()!;
      final subscriptionStatus = data['subscriptionStatus'] ?? 'free';
      final isSubscriptionActive = data['isSubscriptionActive'] ?? false;
      final subscriptionEndDate = data['subscriptionEndDate'];

      if (subscriptionStatus != 'premium' || isSubscriptionActive) {
        return false;
      }

      if (subscriptionEndDate == null) return false;

      DateTime endDateTime;
      if (subscriptionEndDate is Timestamp) {
        endDateTime = subscriptionEndDate.toDate();
      } else if (subscriptionEndDate is String) {
        endDateTime = DateTime.parse(subscriptionEndDate);
      } else {
        return false;
      }

      return DateTime.now().isAfter(endDateTime);
    } catch (e) {
      debugPrint('SubscriptionReminderService: Error checking expiry: $e');
      return false;
    }
  }

  /// Hátralévő napok számának lekérése
  static Future<int?> getDaysUntilExpiry(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      final subscriptionEndDate = data['subscriptionEndDate'];

      if (subscriptionEndDate == null) return null;

      DateTime endDateTime;
      if (subscriptionEndDate is Timestamp) {
        endDateTime = subscriptionEndDate.toDate();
      } else if (subscriptionEndDate is String) {
        endDateTime = DateTime.parse(subscriptionEndDate);
      } else {
        return null;
      }

      final now = DateTime.now();
      final days = endDateTime.difference(now).inDays;

      return days > 0 ? days : 0;
    } catch (e) {
      debugPrint(
          'SubscriptionReminderService: Error getting days until expiry: $e');
      return null;
    }
  }

  /// Emlékeztető megjelenítésének ellenőrzése
  static Future<bool> _shouldShowReminderForDays(int days) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastReminder = prefs.getInt(_lastReminderKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 24 óránként maximum egyszer
      if (now - lastReminder < 24 * 60 * 60 * 1000) {
        return false;
      }

      // 3 napos emlékeztető
      if (days == 3) {
        await prefs.setInt(_lastReminderKey, now);
        return true;
      }

      // 1 napos emlékeztető
      if (days == 1) {
        await prefs.setInt(_lastReminderKey, now);
        return true;
      }

      // Lejárat napján
      if (days == 0) {
        await prefs.setInt(_lastReminderKey, now);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint(
          'SubscriptionReminderService: Error checking reminder timing: $e');
      return false;
    }
  }

  /// Lejárat utáni értesítés megjelenítésének ellenőrzése
  static Future<bool> shouldShowExpiryNotification(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastNotification =
          prefs.getInt('${_expiryNotificationKey}_$userId') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 6 óránként maximum egyszer
      if (now - lastNotification < 6 * 60 * 60 * 1000) {
        return false;
      }

      final isExpired = await isSubscriptionExpired(userId);
      if (isExpired) {
        await prefs.setInt('${_expiryNotificationKey}_$userId', now);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint(
          'SubscriptionReminderService: Error checking expiry notification: $e');
      return false;
    }
  }

  /// Emlékeztető státusz törlése (új fizetés után)
  static Future<void> clearReminderStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastReminderKey);
    } catch (e) {
      debugPrint(
          'SubscriptionReminderService: Error clearing reminder status: $e');
    }
  }

  /// Lejárat értesítés státusz törlése (új fizetés után)
  static Future<void> clearExpiryNotificationStatus(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_expiryNotificationKey}_$userId');
    } catch (e) {
      debugPrint(
          'SubscriptionReminderService: Error clearing expiry notification status: $e');
    }
  }

  /// Előfizetési státusz szöveg generálása
  static Future<String> getSubscriptionStatusText(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) return 'Ingyenes';

      final data = doc.data()!;
      final subscriptionStatus = data['subscriptionStatus'] ?? 'free';
      final isSubscriptionActive = data['isSubscriptionActive'] ?? false;
      final subscriptionEndDate = data['subscriptionEndDate'];

      if (subscriptionStatus == 'premium' && isSubscriptionActive) {
        if (subscriptionEndDate != null) {
          DateTime endDateTime;
          if (subscriptionEndDate is Timestamp) {
            endDateTime = subscriptionEndDate.toDate();
          } else if (subscriptionEndDate is String) {
            endDateTime = DateTime.parse(subscriptionEndDate);
          } else {
            return 'Premium (ismeretlen lejárat)';
          }

          final now = DateTime.now();
          final days = endDateTime.difference(now).inDays;

          if (days > 0) {
            return 'Premium ($days nap hátra)';
          } else if (days == 0) {
            return 'Premium (ma jár le)';
          } else {
            return 'Lejárt (${-days} napja)';
          }
        }
        return 'Premium';
      } else if (subscriptionStatus == 'expired' ||
          (!isSubscriptionActive && subscriptionStatus == 'premium')) {
        return 'Lejárt';
      } else {
        return 'Ingyenes';
      }
    } catch (e) {
      debugPrint('SubscriptionReminderService: Error getting status text: $e');
      return 'Ismeretlen';
    }
  }

  /// Előfizetési státusz színének meghatározása
  static Future<SubscriptionStatusColor> getSubscriptionStatusColor(
      String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) return SubscriptionStatusColor.free;

      final data = doc.data()!;
      final subscriptionStatus = data['subscriptionStatus'] ?? 'free';
      final isSubscriptionActive = data['isSubscriptionActive'] ?? false;
      final subscriptionEndDate = data['subscriptionEndDate'];

      if (subscriptionStatus == 'premium' && isSubscriptionActive) {
        if (subscriptionEndDate != null) {
          DateTime endDateTime;
          if (subscriptionEndDate is Timestamp) {
            endDateTime = subscriptionEndDate.toDate();
          } else if (subscriptionEndDate is String) {
            endDateTime = DateTime.parse(subscriptionEndDate);
          } else {
            return SubscriptionStatusColor.premium;
          }

          final now = DateTime.now();
          final days = endDateTime.difference(now).inDays;

          if (days <= 3 && days > 0) {
            return SubscriptionStatusColor.warning;
          } else if (days > 3) {
            return SubscriptionStatusColor.premium;
          } else {
            return SubscriptionStatusColor.expired;
          }
        }
        return SubscriptionStatusColor.premium;
      } else if (subscriptionStatus == 'expired' ||
          (!isSubscriptionActive && subscriptionStatus == 'premium')) {
        return SubscriptionStatusColor.expired;
      } else {
        return SubscriptionStatusColor.free;
      }
    } catch (e) {
      debugPrint('SubscriptionReminderService: Error getting status color: $e');
      return SubscriptionStatusColor.free;
    }
  }
}

/// Előfizetési státusz színek
enum SubscriptionStatusColor {
  free, // Kék - Ingyenes
  premium, // Zöld - Aktív premium
  warning, // Narancs - Lejárat közelében
  expired, // Piros - Lejárt
}

/// Előfizetési státusz szín kiterjesztések
extension SubscriptionStatusColorExtension on SubscriptionStatusColor {
  String get displayName {
    switch (this) {
      case SubscriptionStatusColor.free:
        return 'Ingyenes';
      case SubscriptionStatusColor.premium:
        return 'Premium';
      case SubscriptionStatusColor.warning:
        return 'Lejárat közelében';
      case SubscriptionStatusColor.expired:
        return 'Lejárt';
    }
  }

  String get description {
    switch (this) {
      case SubscriptionStatusColor.free:
        return 'Korlátozott funkciók elérhetők';
      case SubscriptionStatusColor.premium:
        return 'Előfizetése aktív és minden funkció elérhető';
      case SubscriptionStatusColor.warning:
        return 'Előfizetése hamarosan lejár, érdemes megújítani';
      case SubscriptionStatusColor.expired:
        return 'Előfizetése lejárt, frissítse a fizetést a folytatáshoz';
    }
  }
}
