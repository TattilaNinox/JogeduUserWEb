import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../utils/password_validation.dart';
import '../core/app_messenger.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _passwordsVisible = false;
  bool _currentVisible = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppMessenger.showError('Nincs bejelentkezett felhasználó.');
      context.go('/login');
      return;
    }
    final currentPwd = _currentController.text.trim();
    final newPwd = _newController.text.trim();
    final confirmPwd = _confirmController.text.trim();
    final err = PasswordValidation.errorText(newPwd);
    if (err != null) {
      setState(() => _errorMessage = err);
      return;
    }
    if (newPwd != confirmPwd) {
      setState(() => _errorMessage = 'A két jelszó nem egyezik.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    try {
      final email = user.email;
      if (email == null) {
        throw FirebaseAuthException(
            code: 'user-missing-email',
            message: 'A felhasználónak nincs e-mailje.');
      }
      final cred =
          EmailAuthProvider.credential(email: email, password: currentPwd);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPwd);
      if (!mounted) return;
      AppMessenger.showSuccess('Jelszó sikeresen megváltoztatva.');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/account');
      }
    } on FirebaseAuthException catch (e) {
      final hu = {
        'wrong-password': 'A jelenlegi jelszó helytelen.',
        'invalid-credential':
            'A jelenlegi jelszó helytelen vagy a hitelesítési adatok lejártak.',
        'user-mismatch':
            'A megadott hitelesítési adatok nem ehhez a fiókhoz tartoznak.',
        'requires-recent-login':
            'Kérjük, jelentkezz be újra, majd próbáld meg ismét.',
        'too-many-requests': 'Túl sok próbálkozás. Próbáld meg később.',
        'user-missing-email': 'A felhasználói e-mail cím nem elérhető.',
        'network-request-failed': 'Hálózati hiba. Próbáld újra.',
        'weak-password': 'A jelszó nem elég erős.',
      };
      setState(
          () => _errorMessage = hu[e.code] ?? 'Hiba történt: ${e.message}');
    } catch (e) {
      setState(() => _errorMessage = 'Ismeretlen hiba történt: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Jelszó megváltoztatása',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            return SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (isMobile ? 32 : 48),
                ),
                child: Column(
                  children: [
                    SizedBox(height: isMobile ? 24 : 32),
                    // Nagy elegáns ikon
                    Container(
                      width: isMobile ? 100 : 120,
                      height: isMobile ? 100 : 120,
                      decoration: BoxDecoration(
                        color: const Color(0x1A1E3A8A),
                        borderRadius: BorderRadius.circular(isMobile ? 50 : 60),
                      ),
                      child: const Icon(
                        Icons.lock_reset,
                        size: 60,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    // Cím
                    Text(
                      'Jelszó megváltoztatása',
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 12 : 16),
                    // Rövid leírás
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: isMobile ? 8 : 0),
                      child: const Text(
                        'Add meg a jelenlegi jelszavad és állíts be egy új, erős jelszót.\nMin. 8 karakter, nagy+kisbetű, szám, speciális jel.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: isMobile ? 32 : 48),
                    // Mezők
                    TextField(
                      controller: _currentController,
                      obscureText: !_currentVisible,
                      decoration: InputDecoration(
                        hintText: 'Jelenlegi jelszó',
                        prefixIcon: const Icon(Icons.lock_outline,
                            color: Color(0xFF6B7280)),
                        border: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: Color(0xFF1E3A8A), width: 2),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _currentVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF6B7280),
                          ),
                          onPressed: () => setState(
                              () => _currentVisible = !_currentVisible),
                        ),
                      ),
                      autofillHints: const [AutofillHints.password],
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    TextField(
                      controller: _newController,
                      obscureText: !_passwordsVisible,
                      decoration: InputDecoration(
                        hintText: 'Új jelszó',
                        prefixIcon:
                            const Icon(Icons.lock, color: Color(0xFF6B7280)),
                        helperText:
                            'Min. 8 karakter, nagy+kisbetű, szám, speciális jel',
                        border: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: Color(0xFF1E3A8A), width: 2),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordsVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF6B7280),
                          ),
                          onPressed: () => setState(
                              () => _passwordsVisible = !_passwordsVisible),
                        ),
                      ),
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    TextField(
                      controller: _confirmController,
                      obscureText: !_passwordsVisible,
                      decoration: const InputDecoration(
                        hintText: 'Új jelszó megerősítése',
                        prefixIcon:
                            Icon(Icons.lock_outline, color: Color(0xFF6B7280)),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: Color(0xFF1E3A8A), width: 2),
                        ),
                      ),
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    // Hiba banner
                    if (_errorMessage != null) ...[
                      SizedBox(height: isMobile ? 16 : 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Color(0xFFDC2626), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                    color: Color(0xFFDC2626), fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: isMobile ? 24 : 32),
                    // Mentés gomb
                    SizedBox(
                      width: double.infinity,
                      height: isMobile ? 48 : 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _change,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(isMobile ? 24 : 28),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text(
                                'Jelszó megváltoztatása',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    // Vissza link
                    TextButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/account');
                        }
                      },
                      child: const Text(
                        'Vissza',
                        style: TextStyle(
                          color: Color(0xFF1E3A8A),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
