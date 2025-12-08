import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../core/session_guard.dart';
import 'package:url_launcher/url_launcher.dart';

/// A bejelentkezési képernyőt megvalósító widget.
///
/// Ez egy `StatefulWidget`, mivel a beviteli mezők tartalmát, a jelszó
/// láthatóságát és a hibaüzeneteket az állapotában (`State`) kell kezelnie.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  LoginScreenState createState() => LoginScreenState();
}

/// A `LoginScreen` widget állapotát kezelő osztály.
class LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // A beviteli mezők vezérlői (controller), amelyekkel elérhető és módosítható
  // a mezők tartalma.
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _isLoading = false;

  // Focus nodes az input mezők animációihoz
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  // Animációk
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _backgroundOpacityAnimation;
  late Animation<Color?> _gradientAnimation;

  // Input mezők border color animációihoz
  Color _emailBorderColor = const Color(0xFF6B7280);
  Color _passwordBorderColor = const Color(0xFF6B7280);

  // Magyar Firebase Auth hibaüzenetek
  static const Map<String, String> _firebaseErrorHu = {
    'wrong-password': 'A jelszó helytelen. Kérjük, próbáld újra.',
    'user-not-found':
        'Ez az e-mail cím nincs regisztrálva. Kérjük, regisztrálj vagy ellenőrizd az e-mail címet.',
    'invalid-email': 'Az e-mail cím formátuma helytelen.',
    'user-disabled': 'A felhasználói fiók le van tiltva.',
    'too-many-requests':
        'Túl sok sikertelen bejelentkezési kísérlet. Kérjük, próbáld meg később.',
    'invalid-credential':
        'Az e-mail cím vagy jelszó helytelen. Kérjük, ellenőrizd az adataidat.',
  };

  // Egy állapotváltozó a bejelentkezési hibaüzenetek tárolására.
  // Ha értéke `null`, nem jelenik meg hibaüzenet.
  String? _errorMessage;

  late Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();

    // Animáció controller inicializálása
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Fade-in animáció a panelnek
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    // Background opacity animáció
    _backgroundOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 0.15,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeIn),
    ));

    // Gradient color animáció
    _gradientAnimation = ColorTween(
      begin: const Color(0xFFE3F2FD),
      end: const Color(0xFFBBDEFB),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Animáció indítása
    _animationController.forward();

    // Focus listeners az input mezők animációihoz
    _emailFocusNode.addListener(() {
      setState(() {
        _emailBorderColor = _emailFocusNode.hasFocus
            ? const Color(0xFF1E3A8A)
            : const Color(0xFF6B7280);
      });
    });

    _passwordFocusNode.addListener(() {
      setState(() {
        _passwordBorderColor = _passwordFocusNode.hasFocus
            ? const Color(0xFF1E3A8A)
            : const Color(0xFF6B7280);
      });
    });
  }

  /// A bejelentkezési folyamatot kezelő aszinkron metódus.
  Future<void> _signIn() async {
    try {
      debugPrint('=== BEJELENTKEZÉS KEZDETE ===');
      debugPrint('Email: ${_emailController.text.trim()}');
      debugPrint('Password length: ${_passwordController.text.trim().length}');

      setState(() {
        _errorMessage = null;
        _isLoading = true;
      });

      // Megpróbál bejelentkezni a Firebase Authentication szolgáltatással,
      // az e-mail és jelszó mezők aktuális értékét használva.
      // A `.trim()` metódus eltávolítja a felesleges szóközöket a szöveg elejéről és végéről.
      debugPrint('Firebase Auth bejelentkezés megkezdése...');
      final userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      debugPrint('Firebase Auth bejelentkezés sikeres!');

      // Sikeres bejelentkezés után a router automatikusan átirányít
      if (userCredential.user != null && mounted) {
        debugPrint(
            'Bejelentkezés sikeres, várakozás a SessionGuard inicializálására...');

        // Várjuk meg, hogy a SessionGuard inicializálódjon
        await SessionGuard.instance.ensureInitialized();

        // Kis várakozás, hogy a Firestore listener felálljon
        await Future.delayed(const Duration(milliseconds: 300));

        if (!mounted) return;

        debugPrint(
            'SessionGuard inicializálva, átirányítás a /guard képernyőre');
        context.go('/guard');
      }
    } on FirebaseAuthException catch (e) {
      // Ha a bejelentkezés során a Firebase hibát dob (pl. rossz jelszó),
      // akkor a `catch` blokk lefut.
      // A `setState` metódus frissíti a widget állapotát, és beállítja a
      // hibaüzenetet, ami ezután megjelenik a UI-n.
      setState(() {
        _errorMessage = _firebaseErrorHu[e.code] ?? 'Ismeretlen hiba történt.';
        _isLoading = false;
      });
    } on TypeError catch (e) {
      debugPrint("MFA TypeError during login (nem kritikus): $e");
      setState(() {
        _errorMessage = 'Bejelentkezési hiba történt. Kérlek próbáld újra.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Hiba történt a bejelentkezés során: $e';
        _isLoading = false;
      });
    }
  }

  /// A widget életciklusának `dispose` metódusa.
  ///
  /// Akkor hívódik meg, amikor a widget véglegesen eltávolításra kerül a
  /// widget-fáról. Itt kell felszabadítani az erőforrásokat, mint például
  /// a `TextEditingController`-eket, hogy elkerüljük a memóriaszivárgást.
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// A widget felhasználói felületét (UI) felépítő metódus.
  @override
  Widget build(BuildContext context) {
    // A `Scaffold` egy alapvető Material Design vizuális elrendezési struktúra.
    if (kIsWeb) {
      final qp = Uri.base.queryParameters;
      // Eszközváltásból visszatérve előtöltjük az e-mailt, ha üres
      final prefillEmail = widget.initialEmail ?? qp['email'];
      if (prefillEmail != null &&
          prefillEmail.isNotEmpty &&
          _emailController.text.isEmpty) {
        _emailController.text = prefillEmail;
      }
    } else {
      // Nem web környezet: az átadott initialEmail-t használjuk, ha van
      final prefillEmail = widget.initialEmail;
      if (prefillEmail != null &&
          prefillEmail.isNotEmpty &&
          _emailController.text.isEmpty) {
        _emailController.text = prefillEmail;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      // Görgethető, biztonságos terület a kisebb kijelzők és a billentyűzet miatt.
      body: SafeArea(
        child: Stack(
          children: [
            // Animated background gradient
            AnimatedBuilder(
              animation: _gradientAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _gradientAnimation.value ?? const Color(0xFFE3F2FD),
                        const Color(0xFFF5F5F5),
                      ],
                    ),
                  ),
                );
              },
            ),
            // Background illustration
            AnimatedBuilder(
              animation: _backgroundOpacityAnimation,
              builder: (context, child) {
                return Positioned.fill(
                  child: Opacity(
                    opacity: _backgroundOpacityAnimation.value,
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/images/education_background.svg',
                        width: MediaQuery.of(context).size.width * 0.8,
                        height: MediaQuery.of(context).size.height * 0.8,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                );
              },
            ),
            // Main content
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                // A bejelentkezési panel konténere.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: AnimatedBuilder(
                    animation: _fadeAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _fadeAnimation.value,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - _fadeAnimation.value)),
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
                            // A `Column` widget a gyermekeit függőlegesen rendezi el.
                            child: Column(
                              // A `mainAxisSize: MainAxisSize.min` biztosítja, hogy a `Column`
                              // csak annyi helyet foglaljon, amennyi a tartalmához szükséges.
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Cím
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, 20 * (1 - value)),
                                        child: Image.asset(
                                          'assets/images/login_LOGO.png',
                                          height: 207,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, 15 * (1 - value)),
                                        child: const Text(
                                          'Jogedu belépés',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E3A8A),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: 8.0, bottom: 16.0),
                                  child: Center(
                                    child: InkWell(
                                      onTap: () async {
                                        final uri = Uri.parse(
                                            'https://lomedu-public.web.app/');
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.platformDefault,
                                          webOnlyWindowName: '_self',
                                        );
                                      },
                                      hoverColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      splashColor: Colors.transparent,
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Adatvédelmi irányelvek és felhasználási feltételek',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          SizedBox(width: 6),
                                          Icon(
                                            Icons.open_in_new,
                                            size: 14,
                                            color: Colors.black38,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // E-mail beviteli mező
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, 10 * (1 - value)),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          child: TextField(
                                            controller: _emailController,
                                            focusNode: _emailFocusNode,
                                            decoration: InputDecoration(
                                              labelText: 'E-mail',
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                borderSide: BorderSide(
                                                    color: _emailBorderColor),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                borderSide: BorderSide(
                                                    color: _emailBorderColor),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFF1E3A8A),
                                                    width: 2),
                                              ),
                                              prefixIcon: Icon(
                                                Icons.email,
                                                color: _emailBorderColor,
                                              ),
                                            ),
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            autofillHints: const [
                                              AutofillHints.email
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                // Jelszó beviteli mező
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, 10 * (1 - value)),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          child: TextField(
                                            controller: _passwordController,
                                            focusNode: _passwordFocusNode,
                                            obscureText:
                                                !_passwordVisible, // Elrejti a beírt karaktereket
                                            decoration: InputDecoration(
                                              labelText: 'Jelszó',
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                borderSide: BorderSide(
                                                    color:
                                                        _passwordBorderColor),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                borderSide: BorderSide(
                                                    color:
                                                        _passwordBorderColor),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFF1E3A8A),
                                                    width: 2),
                                              ),
                                              prefixIcon: Icon(
                                                Icons.lock,
                                                color: _passwordBorderColor,
                                              ),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _passwordVisible
                                                      ? Icons.visibility_off
                                                      : Icons.visibility,
                                                  color: _passwordBorderColor,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    _passwordVisible =
                                                        !_passwordVisible;
                                                  });
                                                },
                                              ),
                                            ),
                                            autofillHints: const [
                                              AutofillHints.password
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                // Hibaüzenet megjelenítése, ha van.
                                // A feltételes `if` a collection-ön belül csak akkor adja hozzá
                                // a `SizedBox`-ot és a `Text`-et a widget-listához, ha az
                                // `_errorMessage` nem `null`.
                                if (_errorMessage != null) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    _errorMessage!, // A `!` jelzi, hogy biztosak vagyunk benne, itt már nem `null`.
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFE74C3C),
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (_errorMessage!
                                      .contains('nincs regisztrálva')) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Ha új böngészőt használsz vagy törölted a sütiket, használd az Eszközváltás gombot.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFFE74C3C),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 24),
                                // Bejelentkezés gomb
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, 10 * (1 - value)),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          child: ElevatedButton(
                                            onPressed:
                                                _isLoading ? null : _signIn,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF1E3A8A),
                                              foregroundColor: Colors.white,
                                              disabledBackgroundColor:
                                                  const Color(0xFF1E3A8A)
                                                      .withOpacity(0.6),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              elevation: _isLoading ? 2 : 4,
                                            ),
                                            child: _isLoading
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              Colors.white),
                                                    ),
                                                  )
                                                : const Text(
                                                    'Bejelentkezés',
                                                    style: TextStyle(
                                                      fontFamily: 'Inter',
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          context.go('/forgot-password'),
                                      child: const Text('Elfelejtett jelszó?'),
                                    ),
                                    TextButton(
                                      onPressed: () => context.go('/register'),
                                      child: const Text('Regisztráció'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    // Synchronous logout and navigation
                                    FirebaseAuth.instance.signOut();
                                    context.go('/device-change');
                                  },
                                  icon: const Icon(
                                    Icons.devices,
                                    size: 16,
                                    color: Color(0xFF1E3A8A),
                                  ),
                                  label: const Text('Eszköz regisztráció'),
                                ),
                                const SizedBox(height: 24),
                                // Verzió megjelenítés - bal alsó sarok
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 13,
                                        color: const Color(0xFF1E3A8A)
                                            .withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(width: 6),
                                      FutureBuilder<PackageInfo>(
                                        future: _packageInfoFuture,
                                        builder: (context, snapshot) {
                                          // Ha van adat, azt használjuk, egyébként '...' töltésjelző, majd fallback
                                          if (snapshot.hasData) {
                                            String versionText =
                                                'v${snapshot.data!.version}';
                                            // Build számot web-en ritkán használunk, de ha van, megjelenhet
                                            // if (snapshot.data!.buildNumber.isNotEmpty) {
                                            //   versionText += '+${snapshot.data!.buildNumber}';
                                            // }
                                            return Text(
                                              versionText,
                                              style: TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 11,
                                                fontWeight: FontWeight.w400,
                                                color: Colors.black
                                                    .withValues(alpha: 0.4),
                                                letterSpacing: 0.3,
                                              ),
                                            );
                                          }

                                          // Töltés vagy hiba esetén egyelőre ne írjunk ki semmit (vagy a fallback-et)
                                          // De mivel a package_info_plus web-en néha lassú vagy nem ad vissza semmit dev módban,
                                          // érdemes lehet egy konstanst is beállítani, ha a pubspec nem elérhető.
                                          return Text(
                                            'v1.0.11', // Manuális fallback a pubspec.yaml alapján
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 11,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.black
                                                  .withValues(alpha: 0.4),
                                              letterSpacing: 0.3,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
