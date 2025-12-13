import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../utils/password_validation.dart';
import '../core/app_messenger.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.oobCode});
  final String oobCode;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _passwordsVisible = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final pwd = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();
    final err = PasswordValidation.errorText(pwd);
    if (err != null) {
      setState(() => _errorMessage = err);
      return;
    }
    if (pwd != confirm) {
      setState(() => _errorMessage = 'A két jelszó nem egyezik.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    try {
      await FirebaseAuth.instance.verifyPasswordResetCode(widget.oobCode);
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: pwd,
      );
      if (!mounted) return;
      AppMessenger.showSuccess('Jelszó sikeresen frissítve. Jelentkezz be.');
      context.go('/login');
    } on FirebaseAuthException catch (e) {
      final hu = {
        'expired-action-code': 'A visszaállítási link lejárt. Kérj újat.',
        'invalid-action-code': 'Érvénytelen visszaállítási link.',
        'user-disabled': 'A fiók le van tiltva.',
        'user-not-found': 'A felhasználó nem található.',
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
          'Jelszó visszaállítása',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/login'),
        ),
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
                    // Nagy ikon
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
                      'Új jelszó beállítása',
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 12 : 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Add meg az új jelszót a szabályok szerint, majd erősítsd meg.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: isMobile ? 32 : 48),
                    TextField(
                      controller: _passwordController,
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
                    SizedBox(
                      width: double.infinity,
                      height: isMobile ? 48 : 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _reset,
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
                                'Jelszó beállítása',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
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
