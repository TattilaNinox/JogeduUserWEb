import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'web_payment_service.dart';

/// Webes fizetési service wrapper - SimplePay integrációhoz
///
/// Ez a service a WebPaymentService-t használja SimplePay fizetésekhez.
class HybridPaymentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Elérhető fizetési csomagok lekérése
  static List<PaymentPlan> getAvailablePlans() {
    return WebPaymentService.availablePlans;
  }

  /// Fizetés indítása SimplePay-jel
  static Future<PaymentInitiationResult> initiatePayment({
    required String planId,
    required String userId,
    Map<String, String>? shippingAddress,
  }) async {
    return await WebPaymentService.initiatePaymentViaCloudFunction(
      planId: planId,
      userId: userId,
      shippingAddress: shippingAddress,
    );
  }

  /// Fizetési előzmények lekérése
  static Future<List<PaymentHistoryItem>> getPaymentHistory(
      String userId) async {
    return await WebPaymentService.getPaymentHistory(userId);
  }

  /// Előfizetési státusz lekérése
  static Future<SubscriptionStatus> getSubscriptionStatus(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (!doc.exists) {
        return SubscriptionStatus.free;
      }

      final data = doc.data()!;
      final subscriptionStatus = data['subscriptionStatus'] ?? 'free';
      final isSubscriptionActive = data['isSubscriptionActive'] ?? false;

      if (subscriptionStatus == 'premium' && isSubscriptionActive) {
        // Ellenőrizzük, hogy nem járt-e le
        final endDate = data['subscriptionEndDate'];
        if (endDate != null) {
          DateTime endDateTime;
          if (endDate is Timestamp) {
            endDateTime = endDate.toDate();
          } else if (endDate is String) {
            endDateTime = DateTime.parse(endDate);
          } else {
            return SubscriptionStatus.free;
          }

          if (DateTime.now().isAfter(endDateTime)) {
            return SubscriptionStatus.expired;
          }
        }

        return SubscriptionStatus.premium;
      } else if (subscriptionStatus == 'expired' ||
          (!isSubscriptionActive && subscriptionStatus == 'premium')) {
        return SubscriptionStatus.expired;
      } else {
        return SubscriptionStatus.free;
      }
    } catch (e) {
      debugPrint('HybridPaymentService: Error getting subscription status: $e');
      return SubscriptionStatus.free;
    }
  }

  /// Próbaidőszak ellenőrzése
  static Future<bool> hasActiveTrial(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (!doc.exists) {
        return false;
      }

      final data = doc.data()!;
      final freeTrialEndDate = data['freeTrialEndDate'];

      if (freeTrialEndDate != null) {
        DateTime trialEndDateTime;
        if (freeTrialEndDate is Timestamp) {
          trialEndDateTime = freeTrialEndDate.toDate();
        } else if (freeTrialEndDate is String) {
          trialEndDateTime = DateTime.parse(freeTrialEndDate);
        } else {
          return false;
        }

        return DateTime.now().isBefore(trialEndDateTime);
      }

      return false;
    } catch (e) {
      debugPrint('HybridPaymentService: Error checking trial: $e');
      return false;
    }
  }

  /// Fizetési forrás lekérése
  static Future<PaymentSource?> getPaymentSource(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data()!;
      final subscription = data['subscription'] as Map<String, dynamic>?;
      final source = subscription?['source'] as String?;

      switch (source) {
        case 'google_play':
          return PaymentSource.googlePlay;
        case 'otp_simplepay':
          return PaymentSource.otpSimplePay;
        case 'registration_trial':
          return PaymentSource.registrationTrial;
        default:
          return null;
      }
    } catch (e) {
      debugPrint('HybridPaymentService: Error getting payment source: $e');
      return null;
    }
  }

  /// Konfiguráció ellenőrzése
  static bool get isConfigured => WebPaymentService.isConfigured;

  static String get configurationStatus =>
      WebPaymentService.configurationStatus;
}

/// Előfizetési státusz enum
enum SubscriptionStatus {
  free,
  premium,
  expired,
}

/// Fizetési forrás enum
enum PaymentSource {
  googlePlay,
  otpSimplePay,
  registrationTrial,
}

/// Előfizetési státusz kiterjesztések
extension SubscriptionStatusExtension on SubscriptionStatus {
  String get displayName {
    switch (this) {
      case SubscriptionStatus.free:
        return 'Ingyenes';
      case SubscriptionStatus.premium:
        return 'Premium';
      case SubscriptionStatus.expired:
        return 'Lejárt';
    }
  }

  String get description {
    switch (this) {
      case SubscriptionStatus.free:
        return 'Korlátozott funkciók elérhetők';
      case SubscriptionStatus.premium:
        return 'Előfizetése aktív és minden funkció elérhető';
      case SubscriptionStatus.expired:
        return 'Előfizetése lejárt, frissítse a fizetést a folytatáshoz';
    }
  }

  Color get color {
    switch (this) {
      case SubscriptionStatus.free:
        return Colors.blue;
      case SubscriptionStatus.premium:
        return Colors.green;
      case SubscriptionStatus.expired:
        return Colors.red;
    }
  }
}

/// Fizetési forrás kiterjesztések
extension PaymentSourceExtension on PaymentSource {
  String get displayName {
    switch (this) {
      case PaymentSource.googlePlay:
        return 'Google Play Store';
      case PaymentSource.otpSimplePay:
        return 'OTP SimplePay';
      case PaymentSource.registrationTrial:
        return 'Regisztrációs próbaidő';
    }
  }

  String get description {
    switch (this) {
      case PaymentSource.googlePlay:
        return 'Mobil alkalmazásban vásárolva';
      case PaymentSource.otpSimplePay:
        return 'Webes böngészőben vásárolva';
      case PaymentSource.registrationTrial:
        return 'Automatikus próbaidőszak';
    }
  }
}
