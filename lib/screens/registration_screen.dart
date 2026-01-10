import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/password_validation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/registration_state_service.dart';
import '../services/app_config_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _passwordsVisible = false;
  bool _termsAccepted = false;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isCheckingRegistration = true;

  @override
  void initState() {
    super.initState();
    _checkRegistrationEnabled();
  }

  Future<void> _checkRegistrationEnabled() async {
    final isEnabled = await AppConfigService().isRegistrationEnabled();
    if (!isEnabled && mounted) {
      // Regisztráció tiltva - átirányítás a login oldalra
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A regisztráció jelenleg nem elérhető.'),
          backgroundColor: Colors.orange,
        ),
      );
      context.go('/login');
      return;
    }
    if (mounted) {
      setState(() => _isCheckingRegistration = false);
    }
  }

  bool _isValidEmail(String email) {
    // Javított regex: raw string + helyes egy backslash-es escape a regexben
    final regExp = RegExp(
        r"^(?:[a-zA-Z0-9_'^&/+-])+(?:\.(?:[a-zA-Z0-9_'^&/+-])+)*@(?:(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,})$");
    return regExp.hasMatch(email);
  }

  /// Firebase hibákat átfordítja felhasználóbarát magyar üzenetekre
  String _getUserFriendlyError(String error) {
    final errorLower = error.toLowerCase();

    // Firebase Auth hibakódok
    if (errorLower.contains('email-already-in-use')) {
      return 'Ez az e-mail cím már regisztrálva van. Kérjük, használj egy másik e-mail címet.';
    }
    if (errorLower.contains('invalid-email') ||
        errorLower.contains('invalid email')) {
      return 'Az e-mail cím formátuma helytelen.';
    }
    if (errorLower.contains('weak-password')) {
      return 'A jelszó túl gyenge. Használj legalább 6 karaktert.';
    }
    if (errorLower.contains('too-many-requests')) {
      return 'Túl sok próbálkozás. Kérjük, próbáld újra később.';
    }
    if (errorLower.contains('operation-not-allowed')) {
      return 'Ez a művelet jelenleg nem elérhető. Kérjük, próbáld újra később.';
    }
    if (errorLower.contains('user-disabled')) {
      return 'A felhasználói fiók le van tiltva.';
    }
    if (errorLower.contains('network')) {
      return 'Hálózati hiba. Ellenőrizd az internetkapcsolatodat és próbáld újra.';
    }

    // Egyéb hibák
    return 'Hiba történt a regisztrációban. Kérjük, próbáld újra később.';
  }

  Future<void> _register() async {
    // Jelszó erősség ellenőrzése
    final pwd = _passwordController.text;
    final confirmPwd = _confirmPasswordController.text;
    final pwdError = PasswordValidation.errorText(pwd);
    if (pwdError != null) {
      setState(() => _errorMessage = pwdError);
      return;
    }
    if (pwd != confirmPwd) {
      setState(() => _errorMessage = 'A két jelszó nem egyezik.');
      return;
    }

    if (!_termsAccepted) {
      setState(() => _errorMessage =
          'A regisztrációhoz el kell fogadni az Általános szerződési feltételeket és az Adatvédelmi irányelveket.');
      return;
    }

    if (_lastNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Vezetéknév kötelező.');
      return;
    }
    if (_firstNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Keresztnév kötelező.');
      return;
    }
    if (!_isValidEmail(_emailController.text.trim())) {
      setState(
          () => _errorMessage = 'Kérjük, adjon meg egy érvényes email címet.');
      return;
    }
    // email/jelszó ellenőrzés fentebb megtörtént

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Email elmentése az állapotba a legelején, hogy a redirect ne írja felül.
      final emailToRegister = _emailController.text.trim();
      RegistrationStateService.newlyRegisteredUserEmail = emailToRegister;

      // 1. Auth fiók létrehozása
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: emailToRegister,
        password: _passwordController.text.trim(),
      )
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('A regisztráció túllépte az időkorlátot.');
      });
      final user = userCredential.user!;

      // 3. Próbaidőszak kiszámítása (most + 5 nap)
      final now = DateTime.now();
      final trialEnd = now.add(const Duration(days: 5));

      // 4. Firestore adatok összeállítása a specifikáció szerint
      // NE állítsuk be az authorizedDeviceFingerprint mezőt itt!
      // Az eszköz ujjlenyomata csak az eszközregisztrációs folyamat során lesz beállítva.

      final newUserDoc = {
        'email': user.email,
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'userType': 'normal',
        'science': 'Jogász',
        'subscriptionStatus': 'free',
        'isSubscriptionActive': false,
        'subscriptionEndDate': null,
        'lastPaymentDate': null,
        'freeTrialStartDate': Timestamp.fromDate(now),
        'freeTrialEndDate': Timestamp.fromDate(trialEnd),
        'deviceRegistrationDate': Timestamp.fromDate(now),
        // 'authorizedDeviceFingerprint': null, // NE állítsuk be itt, az eszközregisztráció során lesz beállítva
        'isActive': true,
        'termsAccepted': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 5. Firestore írás (merge: true opcióval)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(newUserDoc, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('Az adatmentés túllépte az időkorlátot.');
      });

      // 7. Kijelentkezés, hogy a redirect logika ne kavarjon be
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        // Átirányítás az eszközregisztrációra. Az email már az állapotban van.
        context.go('/device-change');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _getUserFriendlyError(e.code);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _getUserFriendlyError(e.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Várakozás a regisztrációs állapot ellenőrzésére
    if (_isCheckingRegistration) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Regisztráció',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _lastNameController,
                      decoration: InputDecoration(
                        labelText: 'Vezetéknév',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              const BorderSide(color: Color(0xFF6B7280)),
                        ),
                        prefixIcon:
                            const Icon(Icons.person, color: Color(0xFF6B7280)),
                      ),
                      autofillHints: const [AutofillHints.familyName],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _firstNameController,
                      decoration: InputDecoration(
                        labelText: 'Keresztnév',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              const BorderSide(color: Color(0xFF6B7280)),
                        ),
                        prefixIcon: const Icon(Icons.person_outline,
                            color: Color(0xFF6B7280)),
                      ),
                      autofillHints: const [AutofillHints.givenName],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'E-mail',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              const BorderSide(color: Color(0xFF6B7280)),
                        ),
                        prefixIcon:
                            const Icon(Icons.email, color: Color(0xFF6B7280)),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_passwordsVisible,
                      decoration: InputDecoration(
                        labelText: 'Jelszó',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              const BorderSide(color: Color(0xFF6B7280)),
                        ),
                        prefixIcon:
                            const Icon(Icons.lock, color: Color(0xFF6B7280)),
                      ),
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: !_passwordsVisible,
                      decoration: InputDecoration(
                        labelText: 'Jelszó megerősítése',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              const BorderSide(color: Color(0xFF6B7280)),
                        ),
                        prefixIcon: const Icon(Icons.lock_outline,
                            color: Color(0xFF6B7280)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordsVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF6B7280),
                          ),
                          onPressed: () {
                            setState(() {
                              _passwordsVisible = !_passwordsVisible;
                            });
                          },
                        ),
                      ),
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _termsAccepted,
                          activeColor: const Color(0xFF1E3A8A),
                          onChanged: (value) {
                            setState(() {
                              _termsAccepted = value ?? false;
                            });
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'Elolvastam, megismertem és elfogadom az Általános szerződési feltételeket és az Adatvédelmi irányelveket',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFE74C3C),
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        disabledBackgroundColor:
                            const Color(0xFF1E3A8A).withValues(alpha: 0.7),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Regisztráció',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('Már van fiókod? Bejelentkezés'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
