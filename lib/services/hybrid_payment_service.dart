import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'web_payment_service.dart';

/// Hibrid fizetési service - kezeli a webes és mobil fizetéseket
///
/// Ez a service automatikusan detektálja a platformot és a megfelelő
/// fizetési módszert használja (Web: SimplePay, Mobile: Google Play Billing).
class HybridPaymentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Platform detection
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb;

  /// Elérhető fizetési csomagok lekérése platform alapján
  static List<PaymentPlan> getAvailablePlans() {
    if (isWeb) {
      return WebPaymentService.availablePlans;
    } else {
      // Mobil esetén Google Play Billing csomagok
      return _getMobilePlans();
    }
  }

  /// Fizetés indítása platform-specifikus módszerrel
  static Future<PaymentInitiationResult> initiatePayment({
    required String planId,
    required String userId,
    Map<String, String>? shippingAddress,
  }) async {
    if (isWeb) {
      return await _initiateWebPayment(planId, userId, shippingAddress);
    } else {
      return await _initiateMobilePayment(planId, userId);
    }
  }

  /// Fizetési előzmények lekérése
  static Future<List<PaymentHistoryItem>> getPaymentHistory(
      String userId) async {
    if (isWeb) {
      return await WebPaymentService.getPaymentHistory(userId);
    } else {
      return await _getMobilePaymentHistory(userId);
    }
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

  /// Webes fizetés indítása
  static Future<PaymentInitiationResult> _initiateWebPayment(String planId,
      String userId, Map<String, String>? shippingAddress) async {
    if (!isWeb) {
      return const PaymentInitiationResult(
        success: false,
        error: 'Webes fizetés csak webes platformon érhető el',
      );
    }

    return await WebPaymentService.initiatePaymentViaCloudFunction(
      planId: planId,
      userId: userId,
      shippingAddress: shippingAddress,
    );
  }

  /// Mobil fizetés indítása (Google Play Billing)
  static Future<PaymentInitiationResult> _initiateMobilePayment(
      String planId, String userId) async {
    if (!isMobile) {
      return const PaymentInitiationResult(
        success: false,
        error: 'Mobil fizetés csak mobil platformon érhető el',
      );
    }

    // Google Play Billing integráció (mobil alkalmazásban)
    // Ez a meglévő subscription service része lesz
    return const PaymentInitiationResult(
      success: false,
      error: 'Mobil fizetés még nincs implementálva',
    );
  }

  /// Mobil fizetési előzmények lekérése
  static Future<List<PaymentHistoryItem>> _getMobilePaymentHistory(
      String userId) async {
    // Google Play Billing előzmények (mobil alkalmazásban)
    return [];
  }

  /// Mobil csomagok definíciója
  static List<PaymentPlan> _getMobilePlans() {
    return [
      const PaymentPlan(
        id: 'monthly_premium_prepaid',
        name: '30 napos előfizetés',
        price: 2990,
        period: '30 nap',
        description: 'Teljes hozzáférés minden funkcióhoz',
        features: [
          'Korlátlan jegyzet hozzáférés',
          'Interaktív kvízek',
          'Flashcard csomagok',
          'Audio tartalmak',
          'Offline letöltés',
          'Elsődleges támogatás'
        ],
        subscriptionDays: 30,
      ),
      const PaymentPlan(
        id: 'yearly_premium_prepaid',
        name: 'Éves előfizetés',
        price: 29900,
        period: 'év',
        description: '2 hónap ingyen a havi árhoz képest',
        features: [
          'Korlátlan jegyzet hozzáférés',
          'Interaktív kvízek',
          'Flashcard csomagok',
          'Audio tartalmak',
          'Offline letöltés',
          'Elsődleges támogatás',
          'Korai hozzáférés új funkciókhoz',
          'Exkluzív tartalmak'
        ],
        subscriptionDays: 365,
        popular: true,
      ),
    ];
  }

  /// Konfiguráció ellenőrzése
  static bool get isConfigured {
    if (isWeb) {
      return WebPaymentService.isConfigured;
    } else {
      // Google Play Billing konfiguráció (mobil alkalmazásban)
      return true;
    }
  }

  static String get configurationStatus {
    if (isWeb) {
      return WebPaymentService.configurationStatus;
    } else {
      return 'Google Play Billing konfigurálva';
    }
  }
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
