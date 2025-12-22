import 'dart:async';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';

/// Szolgáltatás az alkalmazás verzió automatikus ellenőrzéséhez és frissítéséhez.
///
/// Ez a szolgáltatás:
/// - Periodikusan (5 percenként) ellenőrzi a szerverről a version.json fájlt
/// - Figyeli a felhasználói aktivitást (egér, billentyűzet, scroll)
/// - Automatikusan újratölti az oldalt új verzió esetén, ha a felhasználó inaktív
/// - Nem frissít kritikus műveletek (kvíz, flashcard tanulás) közben
class VersionCheckService {
  /// A jelenlegi alkalmazás verzió (dinamikusan betöltve)
  static String _currentVersion = '...';

  /// Publikus getter a verziószámhoz
  static String get currentVersion => _currentVersion;

  // Private getter a backward compatibility miatt
  static const Duration _checkInterval = Duration(minutes: 5);
  static const Duration _inactivityThreshold = Duration(minutes: 3);
  static const Duration _recentScrollThreshold = Duration(seconds: 10);

  Timer? _versionCheckTimer;
  DateTime _lastActivityTime = DateTime.now();
  DateTime _lastScrollTime = DateTime.now();
  bool _isActive = false;

  /// Singleton instance
  static final VersionCheckService _instance = VersionCheckService._internal();
  factory VersionCheckService() => _instance;
  VersionCheckService._internal();

  /// Elindítja a verzió ellenőrzést és az aktivitás figyelését
  Future<void> start() async {
    if (_isActive) return;
    _isActive = true;

    // Verzió inicializálása
    await _initVersion();

    debugPrint('[VersionCheck] Service started with version: $_currentVersion');

    // Aktivitás figyelő listener-ek beállítása
    _setupActivityListeners();

    // Verzió ellenőrzés indítása
    _startVersionCheck();
  }

  /// Inicializálja a verziót a csomagból
  Future<void> _initVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (e) {
      debugPrint('[VersionCheck] Failed to get package info: $e');
      // Fallback érték hiba esetén
      _currentVersion = '1.0.1+10';
    }
  }

  /// Leállítja a szolgáltatást
  void stop() {
    _isActive = false;
    _versionCheckTimer?.cancel();
    _versionCheckTimer = null;
    debugPrint('[VersionCheck] Service stopped');
  }

  /// Beállítja a felhasználói aktivitás figyelőket
  void _setupActivityListeners() {
    // Egér mozgás
    web.window.addEventListener(
        'mousemove',
        ((web.Event event) {
          _lastActivityTime = DateTime.now();
        }).toJS);

    // Billentyűzet
    web.window.addEventListener(
        'keydown',
        ((web.Event event) {
          _lastActivityTime = DateTime.now();
        }).toJS);

    // Scroll események
    web.window.addEventListener(
        'scroll',
        ((web.Event event) {
          _lastActivityTime = DateTime.now();
          _lastScrollTime = DateTime.now();
        }).toJS);

    // Touch események (mobil)
    web.window.addEventListener(
        'touchstart',
        ((web.Event event) {
          _lastActivityTime = DateTime.now();
        }).toJS);

    // Click események
    web.window.addEventListener(
        'click',
        ((web.Event event) {
          _lastActivityTime = DateTime.now();
        }).toJS);
  }

  /// Elindítja a periodikus verzió ellenőrzést
  void _startVersionCheck() {
    // Első ellenőrzés 1 perc múlva (ne azonnal induláskor)
    Future.delayed(const Duration(minutes: 1), () {
      if (_isActive) _checkVersion();
    });

    // Periodikus ellenőrzés 5 percenként
    _versionCheckTimer = Timer.periodic(_checkInterval, (_) {
      if (_isActive) _checkVersion();
    });
  }

  /// Ellenőrzi a szerverről az elérhető verziót
  Future<void> _checkVersion() async {
    try {
      // Cache bypass timestamp hozzáadása
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = '/version.json?t=$timestamp';

      debugPrint('[VersionCheck] Checking version from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverVersion = data['version'] as String?;

        if (serverVersion != null && serverVersion != _currentVersion) {
          debugPrint(
              '[VersionCheck] New version available: $serverVersion (current: $_currentVersion)');
          _attemptReload();
        } else {
          debugPrint('[VersionCheck] Version up to date: $_currentVersion');
        }
      } else {
        debugPrint(
            '[VersionCheck] Failed to check version: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[VersionCheck] Error checking version: $e');
    }
  }

  /// Megpróbálja újratölteni az oldalt, ha a feltételek teljesülnek
  void _attemptReload() {
    // Ellenőrzi, hogy biztonságos-e a frissítés
    if (!_isSafeToReload()) {
      debugPrint('[VersionCheck] Reload skipped - not safe to reload');
      return;
    }

    // Ellenőrzi az inaktivitást
    final inactiveDuration = DateTime.now().difference(_lastActivityTime);
    if (inactiveDuration < _inactivityThreshold) {
      debugPrint(
          '[VersionCheck] Reload skipped - user is active (inactive for: ${inactiveDuration.inMinutes}m)');
      return;
    }

    // Minden feltétel teljesült, újratöltés
    debugPrint(
        '[VersionCheck] Reloading application - new version detected and user inactive for ${inactiveDuration.inMinutes} minutes');
    _performReload();
  }

  /// Ellenőrzi, hogy biztonságos-e az oldal újratöltése
  bool _isSafeToReload() {
    // Jelenlegi URL ellenőrzése
    final currentPath = web.window.location.pathname;

    // Ne frissítsen kritikus útvonalakon
    final criticalRoutes = [
      '/deck/',
      '/study',
      '/quiz/',
      '/note/', // Jegyzet olvasás
      '/read/note/', // Jegyzet olvasás (alternatív route)
      '/interactive-note/', // Interaktív jegyzet
    ];

    for (final route in criticalRoutes) {
      if (currentPath.contains(route)) {
        debugPrint('[VersionCheck] On critical route: $currentPath');
        return false;
      }
    }

    // Ellenőrzi, hogy van-e fókuszált input mező
    final activeElement = web.document.activeElement;
    if (activeElement?.tagName.toLowerCase() == 'input' ||
        activeElement?.tagName.toLowerCase() == 'textarea') {
      debugPrint('[VersionCheck] Input field is focused');
      return false;
    }

    // Ellenőrzi, hogy volt-e közelmúltbeli scroll
    final timeSinceScroll = DateTime.now().difference(_lastScrollTime);
    if (timeSinceScroll < _recentScrollThreshold) {
      debugPrint('[VersionCheck] Recent scroll detected');
      return false;
    }

    return true;
  }

  /// Végrehajtja az oldal újratöltését
  void _performReload() {
    // Hard reload a teljes cache törléssel
    web.window.location.reload();
  }

  /// Manuális verzió ellenőrzés triggerelése (teszteléshez)
  Future<void> checkNow() async {
    await _checkVersion();
  }

  /// Aktivitás rögzítése (külső komponensek számára, pl. audio player)
  void recordActivity() {
    _lastActivityTime = DateTime.now();
  }
}
