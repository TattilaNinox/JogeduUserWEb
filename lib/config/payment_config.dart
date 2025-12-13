import 'package:flutter/foundation.dart';

/// Fizetési konfiguráció kezelő
///
/// Ez az osztály kezeli a SimplePay és egyéb fizetési szolgáltatások
/// konfigurációját environment változók alapján.
class PaymentConfig {
  // SimplePay konfiguráció
  static const String simplePayMerchantId = String.fromEnvironment(
    'SIMPLEPAY_MERCHANT_ID',
    defaultValue: '',
  );

  static const String simplePaySecretKey = String.fromEnvironment(
    'SIMPLEPAY_SECRET_KEY',
    defaultValue: '',
  );

  static const bool isProduction = bool.fromEnvironment(
    'PRODUCTION',
    defaultValue: false,
  );

  // Firebase konfiguráció
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'orlomed-f8f9f',
  );

  // NextAuth konfiguráció (webes alkalmazáshoz)
  static const String nextAuthUrl = String.fromEnvironment(
    'NEXTAUTH_URL',
    defaultValue: 'https://lomedu-user-web.web.app',
  );

  static const String nextAuthSecret = String.fromEnvironment(
    'NEXTAUTH_SECRET',
    defaultValue: '',
  );

  // Google OAuth konfiguráció
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleClientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
    defaultValue: '',
  );

  // SimplePay API URL-ek
  static String get simplePayBaseUrl {
    return isProduction
        ? 'https://secure.simplepay.hu/payment/v2/'
        : 'https://sandbox.simplepay.hu/payment/v2/';
  }

  // Webhook URL-ek
  static String get webhookUrl {
    return '$nextAuthUrl/api/webhook/simplepay';
  }

  static String get successUrl {
    return '$nextAuthUrl/subscription?success=true';
  }

  static String get cancelUrl {
    return '$nextAuthUrl/subscription?canceled=true';
  }

  // Konfiguráció ellenőrzések
  static bool get isSimplePayConfigured {
    return simplePayMerchantId.isNotEmpty && simplePaySecretKey.isNotEmpty;
  }

  static bool get isGoogleOAuthConfigured {
    return googleClientId.isNotEmpty && googleClientSecret.isNotEmpty;
  }

  static bool get isNextAuthConfigured {
    return nextAuthUrl.isNotEmpty && nextAuthSecret.isNotEmpty;
  }

  static bool get isFullyConfigured {
    return isSimplePayConfigured &&
        isGoogleOAuthConfigured &&
        isNextAuthConfigured;
  }

  // Konfiguráció státusz üzenetek
  static String get configurationStatus {
    final issues = <String>[];

    if (!isSimplePayConfigured) {
      issues.add('SimplePay konfiguráció hiányzik');
    }

    if (!isGoogleOAuthConfigured) {
      issues.add('Google OAuth konfiguráció hiányzik');
    }

    if (!isNextAuthConfigured) {
      issues.add('NextAuth konfiguráció hiányzik');
    }

    if (issues.isEmpty) {
      return 'Teljesen konfigurálva (${isProduction ? 'Production' : 'Sandbox'})';
    } else {
      return 'Hiányzó konfiguráció: ${issues.join(', ')}';
    }
  }

  // Konfiguráció részletek lekérése
  static Map<String, dynamic> getConfigurationDetails() {
    return {
      'simplePay': {
        'merchantId': simplePayMerchantId.isNotEmpty
            ? '***${simplePayMerchantId.substring(simplePayMerchantId.length - 4)}'
            : 'Nincs beállítva',
        'secretKey': simplePaySecretKey.isNotEmpty
            ? '***${simplePaySecretKey.substring(simplePaySecretKey.length - 4)}'
            : 'Nincs beállítva',
        'baseUrl': simplePayBaseUrl,
        'configured': isSimplePayConfigured,
      },
      'firebase': {
        'projectId': firebaseProjectId,
        'configured': true,
      },
      'nextAuth': {
        'url': nextAuthUrl,
        'secret': nextAuthSecret.isNotEmpty
            ? '***${nextAuthSecret.substring(nextAuthSecret.length - 4)}'
            : 'Nincs beállítva',
        'configured': isNextAuthConfigured,
      },
      'googleOAuth': {
        'clientId': googleClientId.isNotEmpty
            ? '***${googleClientId.substring(googleClientId.length - 4)}'
            : 'Nincs beállítva',
        'clientSecret': googleClientSecret.isNotEmpty
            ? '***${googleClientSecret.substring(googleClientSecret.length - 4)}'
            : 'Nincs beállítva',
        'configured': isGoogleOAuthConfigured,
      },
      'environment': {
        'isProduction': isProduction,
        'isWeb': kIsWeb,
        'isMobile': !kIsWeb,
      },
      'urls': {
        'webhookUrl': webhookUrl,
        'successUrl': successUrl,
        'cancelUrl': cancelUrl,
      },
    };
  }

  // Debug információk
  static void printConfigurationStatus() {
    if (kDebugMode) {
      print('=== PAYMENT CONFIGURATION STATUS ===');
      print('SimplePay: ${isSimplePayConfigured ? "✓" : "✗"}');
      print('Google OAuth: ${isGoogleOAuthConfigured ? "✓" : "✗"}');
      print('NextAuth: ${isNextAuthConfigured ? "✓" : "✗"}');
      print('Environment: ${isProduction ? "Production" : "Sandbox"}');
      print('Platform: ${kIsWeb ? "Web" : "Mobile"}');
      print('Status: $configurationStatus');
      print('=====================================');
    }
  }

  // Konfigurációs hibák lekérése
  static List<String> getConfigurationErrors() {
    final errors = <String>[];

    if (!isSimplePayConfigured) {
      errors.add(
          'SimplePay konfiguráció hiányzik (SIMPLEPAY_MERCHANT_ID, SIMPLEPAY_SECRET_KEY)');
    }

    if (!isGoogleOAuthConfigured) {
      errors.add(
          'Google OAuth konfiguráció hiányzik (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET)');
    }

    if (!isNextAuthConfigured) {
      errors.add(
          'NextAuth konfiguráció hiányzik (NEXTAUTH_URL, NEXTAUTH_SECRET)');
    }

    return errors;
  }

  // Konfigurációs figyelmeztetések
  static List<String> getConfigurationWarnings() {
    final warnings = <String>[];

    if (isProduction && !isFullyConfigured) {
      warnings.add('Production környezetben nem teljes a konfiguráció');
    }

    if (kIsWeb && !isSimplePayConfigured) {
      warnings.add('Webes platformon SimplePay konfiguráció szükséges');
    }

    if (!kIsWeb && !isGoogleOAuthConfigured) {
      warnings.add('Mobil platformon Google OAuth konfiguráció szükséges');
    }

    return warnings;
  }
}
