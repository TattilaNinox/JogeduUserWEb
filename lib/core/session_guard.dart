import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../utils/device_fingerprint.dart';

/// A bejelentkezési és eszköz-hozzáférési állapot központi őre.
///
/// Nem navigál és nem jelentkeztet ki — csak állapotot szolgáltat a routernek.
class SessionGuard extends ChangeNotifier {
  SessionGuard._internal();

  static final SessionGuard instance = SessionGuard._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userDocSubscription;

  AuthStatus _authStatus = AuthStatus.loggedOut;
  DeviceAccess _deviceAccess = DeviceAccess.loading;
  bool _termsAccepted = true; // Kezdetben true, hogy ne villanjon be
  String? _currentFingerprint;
  bool _initialized = false;

  AuthStatus get authStatus => _authStatus;
  DeviceAccess get deviceAccess => _deviceAccess;
  bool get termsAccepted => _termsAccepted;

  /// Egyszeri inicializálás — feliratkozás az auth és user doc változásokra.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    _authSubscription = _auth.authStateChanges().listen((user) async {
      debugPrint('[SessionGuard] authStateChanges -> user=${user?.uid}');
      // Alapértelmezett állapotok
      if (user == null) {
        _authStatus = AuthStatus.loggedOut;
        _deviceAccess = DeviceAccess.loading;
        _termsAccepted = true; // Reset
        await _cancelUserDocSubscription();
        debugPrint('[SessionGuard] user == null -> loggedOut, loading');
        notifyListeners();
        return;
      }

      // Be van jelentkezve
      _authStatus = AuthStatus.loggedIn;
      _deviceAccess = DeviceAccess.loading;
      _termsAccepted = true; // Optimista kezdet
      debugPrint('[SessionGuard] loggedIn -> start device check');
      notifyListeners();

      try {
        // Aktuális fingerprint előkészítése (cache-elve is elég)
        _currentFingerprint = await DeviceFingerprint.getCurrentFingerprint();
        debugPrint('[SessionGuard] currentFingerprint=$_currentFingerprint');

        // Felhasználói dokumentum figyelése
        await _cancelUserDocSubscription();
        _userDocSubscription = _firestore
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen(_onUserDocChanged, onError: (error, _) {
          debugPrint('[SessionGuard] user doc listen error: $error');
          // Hiba esetén ne rúgjuk ki a felhasználót, csak jelezzük, hogy loading
          _deviceAccess = DeviceAccess.loading;
          notifyListeners();
        });
      } catch (_) {
        _deviceAccess = DeviceAccess.loading;
        debugPrint('[SessionGuard] exception during init, set loading');
        notifyListeners();
      }
    });
  }

  Future<void> _cancelUserDocSubscription() async {
    await _userDocSubscription?.cancel();
    _userDocSubscription = null;
  }

  void _onUserDocChanged(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      _deviceAccess = DeviceAccess.loading;
      _termsAccepted = true;
      debugPrint('[SessionGuard] user doc null -> loading');
      notifyListeners();
      return;
    }

    // ÁSZF elfogadás ellenőrzése
    final bool accepted = data['termsAccepted'] as bool? ?? false;
    _termsAccepted = accepted;
    if (!_termsAccepted) {
      debugPrint('[SessionGuard] terms not accepted');
      notifyListeners();
    }

    // Admin esetén ne korlátozzuk az eszközt
    final userType = (data['userType'] as String? ?? '').toLowerCase();
    final isAdmin = userType == 'admin';
    if (isAdmin) {
      _deviceAccess = DeviceAccess.allowed;
      // Adminnak is el kell fogadnia a feltételeket, ha nincs meg
      if (!_termsAccepted) {
        debugPrint(
            '[SessionGuard] admin user -> device allowed BUT terms NOT accepted');
        // Itt hagyjuk, hogy a router döntsön a termsAccepted alapján
        notifyListeners();
        return;
      }
      debugPrint('[SessionGuard] admin user -> allowed');
      notifyListeners();
      return;
    }

    // Teszt fiók esetén ne korlátozzuk az eszközt (ideiglenesen)
    final email = (data['email'] as String? ?? '').toLowerCase();
    if (email == 'lomeduteszt@gmail.com') {
      _deviceAccess = DeviceAccess.allowed;
      debugPrint(
          '[SessionGuard] test account (lomeduteszt@gmail.com) -> allowed');
      notifyListeners();
      return;
    }

    final String? allowedFingerprint =
        data['authorizedDeviceFingerprint'] as String?;

    // Ha nincs regisztrált fingerprint, ne engedjük be azonnal
    // A router átirányít a /device-change képernyőre
    if (allowedFingerprint == null || allowedFingerprint.isEmpty) {
      _deviceAccess = DeviceAccess.denied;
      debugPrint('[SessionGuard] missing allowed fingerprint -> denied');
      notifyListeners();
      return;
    }

    if (_currentFingerprint == null) {
      _deviceAccess = DeviceAccess.loading;
      debugPrint('[SessionGuard] currentFingerprint is null -> loading');
      notifyListeners();
      return;
    }

    final equal = allowedFingerprint == _currentFingerprint;
    _deviceAccess = equal ? DeviceAccess.allowed : DeviceAccess.denied;
    debugPrint(
        '[SessionGuard] compare allowed=$allowedFingerprint vs current=$_currentFingerprint -> ${_deviceAccess.name}');
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userDocSubscription?.cancel();
    super.dispose();
  }
}

enum AuthStatus { loggedOut, loggedIn }

enum DeviceAccess { loading, allowed, denied }
