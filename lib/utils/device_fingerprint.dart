import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceFingerprint {
  /// Webes eszköz ujjlenyomat generálása
  static Future<String> getWebFingerprint() async {
    // Determinisztikus web fingerprint - böngésző jellemzők alapján
    const key = 'device_fingerprint';

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(key);

      if (stored != null && stored.isNotEmpty) {
        return stored; // VISSZAADNI a mentett értéket!
      }

      // Új fingerprint generálása - böngésző jellemzők alapján
      final fingerprint = await _generateStableWebFingerprint();
      await prefs.setString(key, fingerprint);
      return fingerprint;
    } catch (e) {
      // Hiba esetén is új generálás
      final fingerprint = await _generateStableWebFingerprint();
      return fingerprint;
    }
  }

  /// Stabil web fingerprint generálása
  static Future<String> _generateStableWebFingerprint() async {
    try {
      final info = DeviceInfoPlugin();
      final web = await info.webBrowserInfo;
      final ua = web.userAgent ?? '';
      final vendor = web.vendor ?? '';
      final platform = web.platform ?? '';
      final hc = web.hardwareConcurrency?.toString() ?? '';
      final raw = '$ua|$vendor|$platform|$hc';
      final hash = _simpleHash(raw);
      return 'web_$hash';
    } catch (e) {
      // Fallback stabil értékre, ha webBrowserInfo nem elérhető
      return 'web_${_simpleHash('flutter_web_fallback')}';
    }
  }

  /// Egyszerű hash függvény
  static int _simpleHash(String input) {
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash + input.codeUnitAt(i)) & 0xffffffff;
    }
    return hash.abs();
  }

  /// Android eszköz ujjlenyomat generálása (mint a mobil appban)
  static Future<String> getAndroidFingerprint() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    return '${androidInfo.id}_${androidInfo.model}_${androidInfo.brand}_android';
  }

  /// iOS eszköz ujjlenyomat generálása
  static Future<String> getIOSFingerprint() async {
    final deviceInfo = DeviceInfoPlugin();
    final iosInfo = await deviceInfo.iosInfo;

    return '${iosInfo.identifierForVendor}_${iosInfo.model}_${iosInfo.name}_ios';
  }

  /// Platform-specifikus ujjlenyomat
  static Future<String> getCurrentFingerprint() async {
    if (kIsWeb) {
      return await getWebFingerprint();
    } else if (Platform.isAndroid) {
      return await getAndroidFingerprint();
    } else if (Platform.isIOS) {
      return await getIOSFingerprint();
    } else {
      return 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Webes ujjlenyomat törlése (új generáláshoz)
  static Future<void> clearWebFingerprint() async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('device_fingerprint');
      } catch (e) {
        // Ignore error
      }
    }
  }
}
