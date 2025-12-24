import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/payment_plans.dart';

/// Flutter Web payment service OTP SimplePay v2 API integrációval
///
/// Ez a service kezeli a webes fizetési folyamatokat a SimplePay v2 API-val.
/// Kompatibilis a meglévő Google Play Billing rendszerrel.
class WebPaymentService {
  // Környezeti változók maradhatnak konfigurációs ellenőrzéshez, de külső
  // SimplePay API-hívás már nem történik ebben a fájlban.
  static const String _merchantId =
      String.fromEnvironment('SIMPLEPAY_MERCHANT_ID', defaultValue: '');
  static const String _secretKey =
      String.fromEnvironment('SIMPLEPAY_SECRET_KEY', defaultValue: '');
  static const bool _isProduction =
      bool.fromEnvironment('PRODUCTION', defaultValue: false);

  /// Fizetési csomagok definíciója
  static const Map<String, PaymentPlan> _plans = {
    // Kanonikus azonosító
    kPlanIdMonthlyPremiumPrepaid: PaymentPlan(
      id: kPlanIdMonthlyPremiumPrepaid,
      name: kPlanNameLexgo30DayOpen,
      price: 4350,
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
      popular: true,
    ),
    // Visszafelé kompatibilitás
    kPlanIdMonthlyWeb: PaymentPlan(
      id: kPlanIdMonthlyWeb,
      name: kPlanNameLexgo30DayOpen,
      price: 4350,
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
      popular: false,
    ),
  };

  /// Fizetési csomagok lekérése
  static List<PaymentPlan> get availablePlans => _plans.values.toList();

  // Egyszerűsített verzió: böngészőben már nem hívjuk közvetlenül a SimplePay
  // API-t, hanem átküldjük a kérést a biztonságos Cloud Functionnek, amely
  // már bizonyítottan helyesen működik.
  static Future<PaymentInitiationResult> initiatePayment({
    required String planId,
    required String userId,
    String? customerEmail,
    String? customerName,
  }) async {
    // Irányítás a Cloud Function-re. A plusz paramétereket (email, név) most
    // nem továbbítjuk; a Functon a Firestore-ból olvassa a felhasználó adatait.
    // Alapértelmezett kanonikus planId használata, ha a hívó nem a kanonikusat adja
    final canonicalId = canonicalPlanId(planId);
    return initiatePaymentViaCloudFunction(planId: canonicalId, userId: userId);
  }

  /// Cloud Function hívás a fizetés indításához (alternatív megközelítés)
  static Future<PaymentInitiationResult> initiatePaymentViaCloudFunction({
    required String planId,
    required String userId,
    Map<String, String>? shippingAddress,
  }) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = functions.httpsCallable('initiateWebPaymentLexgo');

      final callData = <String, dynamic>{
        'planId': planId,
        'userId': userId,
      };

      if (shippingAddress != null && shippingAddress.isNotEmpty) {
        callData['shippingAddress'] = shippingAddress;
      }

      final result = await callable.call(callData);

      final data = result.data as Map<String, dynamic>;

      return PaymentInitiationResult(
        success: data['success'] as bool,
        paymentUrl: data['paymentUrl'] as String?,
        orderRef: data['orderRef'] as String?,
        amount: data['amount'] as int?,
        planId: planId,
        error: data['error'] as String?,
      );
    } catch (e) {
      debugPrint('WebPaymentService: Cloud Function error: $e');
      return PaymentInitiationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Fizetési előzmények lekérése
  static Future<List<PaymentHistoryItem>> getPaymentHistory(
      String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('web_payments')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return PaymentHistoryItem(
          id: doc.id,
          orderRef: data['orderRef'] as String? ?? '',
          amount: data['amount'] as int? ?? 0,
          status: (data['status'] as String? ?? 'unknown').toLowerCase(),
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          planId: data['planId'] as String? ?? '',
          transactionId: data['transactionId']?.toString(),
          simplePayTransactionId: data['simplePayTransactionId']?.toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('WebPaymentService: Error fetching payment history: $e');
      return [];
    }
  }

  /// Webhook feldolgozás (Cloud Function-ben fog futni)
  static Future<bool> processWebhook(Map<String, dynamic> webhookData) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = functions.httpsCallable('processWebPaymentWebhook');

      final result = await callable.call(webhookData);
      final data = result.data as Map<String, dynamic>;

      return data['success'] as bool? ?? false;
    } catch (e) {
      debugPrint('WebPaymentService: Webhook processing error: $e');
      return false;
    }
  }

  // Az alábbi helper függvények a közvetlen SimplePay-híváshoz kellettek; most
  // már nem használjuk őket, ezért törölve.

  /// Konfiguráció ellenőrzése
  static bool get isConfigured =>
      _merchantId.isNotEmpty && _secretKey.isNotEmpty;

  static String get configurationStatus {
    if (_merchantId.isEmpty) return 'SIMPLEPAY_MERCHANT_ID hiányzik';
    if (_secretKey.isEmpty) return 'SIMPLEPAY_SECRET_KEY hiányzik';
    return 'Konfigurálva (${_isProduction ? 'Production' : 'Sandbox'})';
  }

  /// Környezet lekérdezése
  static String get environment => _isProduction ? 'production' : 'sandbox';

  /// Környezet szöveges megjelenítése
  static String get environmentDisplayName =>
      _isProduction ? 'Éles' : 'Teszt (Sandbox)';

  /// Színkód a környezethez
  static bool get isProductionEnvironment => _isProduction;
}

/// Fizetési csomag modell
class PaymentPlan {
  final String id;
  final String name;
  final int price;
  final String period;
  final String description;
  final List<String> features;
  final int subscriptionDays;
  final bool popular;

  const PaymentPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.period,
    required this.description,
    required this.features,
    required this.subscriptionDays,
    this.popular = false,
  });

  String get formattedPrice =>
      '${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} Ft';

  String get periodText => '/$period';
}

/// Fizetés indítási eredmény
class PaymentInitiationResult {
  final bool success;
  final String? paymentUrl;
  final String? orderRef;
  final int? amount;
  final String? planId;
  final String? error;

  const PaymentInitiationResult({
    required this.success,
    this.paymentUrl,
    this.orderRef,
    this.amount,
    this.planId,
    this.error,
  });
}

/// Fizetési előzmény elem
class PaymentHistoryItem {
  final String id;
  final String orderRef;
  final int amount;
  final String status;
  final DateTime createdAt;
  final String planId;
  final String? transactionId;
  final String? simplePayTransactionId;

  const PaymentHistoryItem({
    required this.id,
    required this.orderRef,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.planId,
    this.transactionId,
    this.simplePayTransactionId,
  });

  String get formattedAmount =>
      '${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} Ft';

  String get statusText {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Sikeres';
      case 'initiated':
        return 'Folyamatban';
      case 'pending':
        return 'Folyamatban';
      case 'failed':
        return 'Sikertelen';
      case 'notauthorized':
        return 'Sikertelen';
      case 'cancelled':
        return 'Lemondva';
      case 'timeout':
        return 'Időtúllépés';
      default:
        return 'Ismeretlen';
    }
  }
}

/// SimplePay v2 API kérés modell
class SimplePayV2Request {
  final String merchant;
  final String orderRef;
  final String customerEmail;
  final String? customerName;
  final String language;
  final String currency;
  final int total;
  final List<SimplePayItem> items;
  final List<String> methods;
  final String url;
  final String timeout;
  final String invoice;
  final String redirectUrl;

  const SimplePayV2Request({
    required this.merchant,
    required this.orderRef,
    required this.customerEmail,
    this.customerName,
    required this.language,
    required this.currency,
    required this.total,
    required this.items,
    required this.methods,
    required this.url,
    required this.timeout,
    required this.invoice,
    required this.redirectUrl,
  });

  Map<String, dynamic> toJson() => {
        'merchant': merchant,
        'orderRef': orderRef,
        'customerEmail': customerEmail,
        if (customerName != null) 'customerName': customerName,
        'language': language,
        'currency': currency,
        'total': total,
        'items': items.map((item) => item.toJson()).toList(),
        'methods': methods,
        'url': url,
        'timeout': timeout,
        'invoice': invoice,
        'redirectUrl': redirectUrl,
      };
}

/// SimplePay v2 API item modell
class SimplePayItem {
  final String ref;
  final String title;
  final String description;
  final int amount;
  final int price;
  final int quantity;

  const SimplePayItem({
    required this.ref,
    required this.title,
    required this.description,
    required this.amount,
    required this.price,
    required this.quantity,
  });

  Map<String, dynamic> toJson() => {
        'ref': ref,
        'title': title,
        'description': description,
        'amount': amount,
        'price': price,
        'quantity': quantity,
      };
}

/// Payment exception
class PaymentException implements Exception {
  final String message;
  const PaymentException(this.message);

  @override
  String toString() => 'PaymentException: $message';
}
