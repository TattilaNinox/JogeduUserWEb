import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/device_change_service.dart';
import '../utils/device_fingerprint.dart';
import '../services/registration_state_service.dart';

class DeviceChangeScreen extends StatefulWidget {
  const DeviceChangeScreen({super.key});

  @override
  State<DeviceChangeScreen> createState() => _DeviceChangeScreenState();
}

class _DeviceChangeScreenState extends State<DeviceChangeScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  String? _errorMessage;
  String? _successMessage;
  bool _isLoading = false;
  int _cooldown = 0;
  final FocusNode _codeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (RegistrationStateService.newlyRegisteredUserEmail != null) {
      _emailController.text =
          RegistrationStateService.newlyRegisteredUserEmail!;
      RegistrationStateService.newlyRegisteredUserEmail = null;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = 30);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _cooldown > 0) {
        setState(() => _cooldown--);
        _startCooldown();
      }
    });
  }

  Future<void> _requestCode() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Kérjük, adja meg az e-mail címét.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final result = await DeviceChangeService.requestDeviceChange(
        _emailController.text.trim());

    setState(() {
      _isLoading = false;
      if (result['success']) {
        _successMessage = 'Kód elküldve az e-mail címre (15 percig érvényes).';
        _startCooldown();
        // Automatikusan fókusz a kód mezőre
        Future.delayed(const Duration(milliseconds: 500), () {
          _codeFocusNode.requestFocus();
        });
      } else {
        _errorMessage = result['error'] ?? 'Hiba történt a kód küldése során.';
      }
    });
  }

  Future<void> _verifyAndChange() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Kérjük, adja meg az e-mail címét.');
      return;
    }
    if (_codeController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Kérjük, adja meg a 6 jegyű kódot.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final fingerprint = await DeviceFingerprint.getCurrentFingerprint();
    final result = await DeviceChangeService.verifyAndChangeDevice(
      email: _emailController.text.trim(),
      code: _codeController.text.trim(),
      newFingerprint: fingerprint,
    );

    setState(() {
      _isLoading = false;
      if (result['success']) {
        _successMessage =
            'Eszköz sikeresen frissítve. Mostantól ez az eszköz jogosult.';
        final email = Uri.encodeComponent(_emailController.text.trim());
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) context.go('/login?email=$email');
        });
      } else {
        _errorMessage =
            result['error'] ?? 'Hiba történt a kód ellenőrzése során.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Eszköz regisztráció',
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
          onPressed: () {
            // Synchronous logout and navigation
            FirebaseAuth.instance.signOut();
            context.go('/login');
          },
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
                      child: Icon(
                        Icons.devices,
                        size: isMobile ? 50 : 60,
                        color: const Color(0xFF1E3A8A),
                      ),
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    // Cím
                    Text(
                      'Eszköz regisztráció',
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 12 : 16),
                    // Leírás
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: isMobile ? 8 : 0),
                      child: Text(
                        'Biztonsági okokból, az eszközt regisztrálni kell. Minden új regsiztráció esetén, illetve ha új számitógépet, telefont vagy privát böngészőablakot szeretnél használni, először regisztrálnod kell azt. Kérj egy hatjegyű kódot az e-mail címedre, majd írd be a kódot, hogy regisztráld az eszközt',
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          color: const Color(0xFF6B7280),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: isMobile ? 32 : 48),
                    // E-mail mező
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        hintText: 'Email cím',
                        prefixIcon: Icon(Icons.email_outlined,
                            color: Color(0xFF6B7280)),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: Color(0xFF1E3A8A), width: 2),
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    // Kód mező (csak akkor jelenik meg, ha kódot kért)
                    if (_successMessage != null) ...[
                      Pinput(
                        controller: _codeController,
                        length: 6,
                        focusNode: _codeFocusNode,
                        defaultPinTheme: PinTheme(
                          width: isMobile ? 45 : 56,
                          height: isMobile ? 45 : 56,
                          textStyle: TextStyle(
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E3A8A),
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white,
                          ),
                        ),
                        focusedPinTheme: PinTheme(
                          width: isMobile ? 45 : 56,
                          height: isMobile ? 45 : 56,
                          textStyle: TextStyle(
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E3A8A),
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: const Color(0xFF1E3A8A), width: 2),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white,
                          ),
                        ),
                        submittedPinTheme: PinTheme(
                          width: isMobile ? 45 : 56,
                          height: isMobile ? 45 : 56,
                          textStyle: TextStyle(
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E3A8A),
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF1E3A8A)),
                            borderRadius: BorderRadius.circular(8),
                            color: const Color(0x1A1E3A8A),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        onCompleted: (pin) {
                          // Automatikus ellenőrzés, ha 6 számjegy be van írva
                          if (pin.length == 6) {
                            _verifyAndChange();
                          }
                        },
                      ),
                      SizedBox(height: isMobile ? 24 : 32),
                    ],
                    // Kód kérése gomb
                    SizedBox(
                      width: double.infinity,
                      height: isMobile ? 48 : 56,
                      child: ElevatedButton(
                        onPressed:
                            _isLoading || _cooldown > 0 ? null : _requestCode,
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
                            : Text(
                                _cooldown > 0
                                    ? 'Újraküldés $_cooldown s'
                                    : 'Kód kérése',
                                style: TextStyle(
                                  fontSize: isMobile ? 14 : 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    // Váltás gomb (csak akkor jelenik meg, ha kódot kért)
                    if (_successMessage != null) ...[
                      SizedBox(height: isMobile ? 12 : 16),
                      SizedBox(
                        width: double.infinity,
                        height: isMobile ? 48 : 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _verifyAndChange,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
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
                              : Text(
                                  'Eszköz regisztráció',
                                  style: TextStyle(
                                    fontSize: isMobile ? 14 : 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                    SizedBox(height: isMobile ? 16 : 24),
                    // Vissza a bejelentkezéshez link
                    TextButton(
                      onPressed: () {
                        // Synchronous logout and navigation
                        FirebaseAuth.instance.signOut();
                        context.go('/login');
                      },
                      child: Text(
                        'Vissza a bejelentkezéshez',
                        style: TextStyle(
                          color: const Color(0xFF1E3A8A),
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: isMobile ? 24 : 32),
                    // Hiba/siker üzenetek
                    if (_errorMessage != null) ...[
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
                    if (_successMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: Color(0xFF16A34A), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _successMessage!,
                                style: const TextStyle(
                                    color: Color(0xFF16A34A), fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
