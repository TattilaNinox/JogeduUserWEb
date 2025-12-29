import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'core/firebase_config.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'core/app_messenger.dart';
import 'screens/note_list_screen.dart';
// Felhasználói nézetben az admin képernyők eltávolítva
// import 'screens/registration_screen.dart';
// import 'screens/forgot_password_screen.dart';
// importok eltávolítva: bundle, create/edit képernyők
import 'theme/app_theme.dart'; // <-- AppTheme importálása
// flashcard/kvíz admin képernyők eltávolítva
// import 'screens/verify_otp_screen.dart'; // 2FA csak az admin webben
import 'screens/device_change_screen.dart';
// import 'screens/two_factor_auth_screen.dart';
// public doc admin képernyők eltávolítva
import 'screens/note_read_screen.dart';
import 'screens/flashcard_deck_view_screen.dart';
import 'screens/flashcard_study_screen.dart';
import 'screens/interactive_note_view_screen.dart';
import 'screens/dynamic_quiz_view_screen.dart';
import 'screens/memoriapalota_allomas_view_screen.dart';
import 'screens/study_board_list_screen.dart';
import 'screens/study_board_screen.dart';
import 'screens/jogeset_view_screen.dart';
import 'core/session_guard.dart';
import 'screens/guard_splash_screen.dart';
import 'screens/account_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/terms_acceptance_screen.dart';
import 'screens/user_bundle_list_screen.dart';
import 'screens/user_bundle_edit_screen.dart';
import 'screens/user_bundle_view_screen.dart';
import 'screens/document_selection_screen.dart';
import 'services/version_check_service.dart';
import 'utils/hyphenation.dart'; // Hyphenation import

/// Az alkalmazás fő belépési pontja.
void main() async {
  // Biztosítja, hogy a Flutter widget-kötések inicializálva legyenek,
  // mielőtt bármilyen Flutter-specifikus API hívás történne.
  WidgetsFlutterBinding.ensureInitialized();

  // URL-alapú routing (hash nélküli) beállítása Flutter Web-hez
  // Ez lehetővé teszi a SimplePay visszairányítást tiszta URL-ekkel
  usePathUrlStrategy();

  // Inicializálja a Firebase szolgáltatásokat az alkalmazás indulásakor.
  // Ez egy aszinkron művelet, ezért a `main` függvény `async`-ként van megjelölve.
  await FirebaseConfig.initialize();
  // Initialize intl date formatting for Hungarian locale
  await initializeDateFormatting('hu', null);

  // Pre-initialize hyphenator in background
  unawaited(initHyphenatorHu());

  // Elindítja az alkalmazást a gyökér widget (`MyApp`) megadásával.
  runApp(const MyApp());
}

/// Az alkalmazás navigációs útvonalait kezeli a `go_router` csomag segítségével.
/// Ez a router határozza meg, hogy melyik URL (útvonal) melyik képernyőt (widgetet) töltse be.
final _router = GoRouter(
  initialLocation: '/login',
  refreshListenable: SessionGuard.instance,
  redirect: (context, state) {
    // Gondoskodunk róla, hogy a guard inicializálva legyen
    SessionGuard.instance.ensureInitialized();

    final loc = state.uri.path;
    final qp = state.uri.queryParameters;
    final baseQp = Uri.base.queryParameters; // query a hash előttről

    // SimplePay callback check - KORÁBBAN, mielőtt az auth check fut
    final paymentParam = qp['payment'] ?? baseQp['payment'];
    if (paymentParam != null) {
      if (kDebugMode) {
        debugPrint(
            '[Router] SimplePay payment callback detected: payment=$paymentParam');
      }

      // Payment callback esetén MINDIG engedélyezzük az account oldalt,
      // még akkor is, ha nincs currentUser (mert lehet, hogy még betöltődik)
      // Az account_screen StreamBuilder-rel várja a user-t
      // FONTOS: Ne nézzük meg a device access-t, mert az loading állapotban lehet
      if (loc == '/account') {
        return null; // Engedélyezzük az account oldalt
      } else {
        // Átirányít account-ra query paraméterekkel
        final queryString = state.uri.query;
        return '/account${queryString.isNotEmpty ? '?$queryString' : ''}';
      }
    }

    final auth = SessionGuard.instance.authStatus;
    final device = SessionGuard.instance.deviceAccess;
    final termsAccepted = SessionGuard.instance.termsAccepted;
    final shouldUseBaseParams = {
      '/',
      '/reset-password',
    }.contains(loc);
    final modeParam =
        qp['mode'] ?? (shouldUseBaseParams ? baseQp['mode'] : null);
    final codeParam =
        qp['oobCode'] ?? (shouldUseBaseParams ? baseQp['oobCode'] : null);
    final isAuthRoute = {
      '/login',
      '/register',
      '/guard',
      '/device-change',
      '/forgot-password',
      '/reset-password',
    }.contains(loc);

    if (loc == '/login') {
      // Már a login oldalon vagyunk: ne fussanak az email-link redirectek, különben hurok lesz
      // (mode=oobCode a base URL-ben még megmaradt)
      return null;
    }
    // resetPassword
    if (loc != '/reset-password' &&
        modeParam == 'resetPassword' &&
        codeParam != null) {
      final code = codeParam;
      return '/reset-password?mode=resetPassword&oobCode=$code';
    }

    if (loc == '/' && modeParam == 'resetPassword' && codeParam != null) {
      final code = codeParam;
      return '/reset-password?mode=resetPassword&oobCode=$code';
    }

    if (auth == AuthStatus.loggedOut) {
      final publicRoutes = {
        '/login',
        '/register',
        '/device-change',
        '/forgot-password',
        '/reset-password',
      };

      // A payment callback már fent kezelve van, itt csak a normál eseteket nézzük
      return publicRoutes.contains(loc) ? null : '/login';
    }

    // Payment callback esetén ne nézzük meg a device access-t (már fent kezelve)
    // Csak akkor nézzük meg, ha NEM payment callback
    if (paymentParam == null && device == DeviceAccess.loading) {
      return loc == '/guard' ? null : '/guard';
    }

    // ÁSZF elfogadás ellenőrzése (ha be van lépve és nem loading)
    if (!termsAccepted) {
      return loc == '/terms-acceptance' ? null : '/terms-acceptance';
    }

    if (device == DeviceAccess.denied) {
      return loc == '/device-change' ? null : '/device-change';
    }

    if (isAuthRoute) {
      return '/notes';
    }

    return null;
  },
  routes: [
    // Bejelentkezési képernyő útvonala.
    GoRoute(
      path: '/login',
      builder: (context, state) {
        final qp = state.uri.queryParameters;
        return LoginScreen(initialEmail: qp['email']);
      },
    ),
    // Reset password képernyő (oobCode query param kezelése)
    GoRoute(
      path: '/reset-password',
      builder: (context, state) {
        final qpLocal = state.uri.queryParameters;
        final code = qpLocal['oobCode'] ?? Uri.base.queryParameters['oobCode'];
        if (code == null || code.isEmpty) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Hiányzó vagy érvénytelen visszaállító kód.'),
              ),
            ),
          );
        }
        return ResetPasswordScreen(oobCode: code);
      },
    ),
    // Regisztrációs képernyő útvonala.
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegistrationScreen(),
    ),
    // Guard / splash képernyő
    GoRoute(
      path: '/guard',
      builder: (context, state) => const GuardSplashScreen(),
    ),
    // Eszközváltás képernyő
    GoRoute(
      path: '/device-change',
      builder: (context, state) => const DeviceChangeScreen(),
    ),
    // Felhasználói appban a regisztráció/jelszó elfelejtése elrejtve (ha nem kell)
    // Jegyzetek listájának képernyője.
    GoRoute(
      path: '/notes',
      builder: (context, state) {
        final qp = state.uri.queryParameters;
        // Normalizáljuk az "MP" értéket "memoriapalota_allomasok"-ra már itt, az URL-ből
        final type = qp['type'];
        final normalizedType = type == 'MP' ? 'memoriapalota_allomasok' : type;
        return NoteListScreen(
          initialSearch: qp['q'],
          initialStatus: qp['status'],
          initialCategory: qp['category'],
          initialScience: qp['science'],
          initialTag: qp['tag'],
          initialType: normalizedType,
        );
      },
    ),
    GoRoute(
      path: '/study-boards',
      builder: (context, state) => const StudyBoardListScreen(),
    ),
    GoRoute(
      path: '/study-boards/:boardId',
      builder: (context, state) {
        final boardId = state.pathParameters['boardId']!;
        return StudyBoardScreen(boardId: boardId);
      },
    ),
    // Létrehozó/szerkesztő útvonalak eltávolítva
    // Kvíz admin útvonalak eltávolítva
    // Admin listák/kezelők eltávolítva
    // Admin note pages nézet eltávolítva
    // Felhasználói, csak olvasási nézet a szöveges jegyzethez (admin funkciók nélkül)
    GoRoute(
      path: '/read/note/:noteId',
      builder: (context, state) {
        final noteId = state.pathParameters['noteId']!;
        final from = state.uri.queryParameters['from'];
        return NoteReadScreen(noteId: noteId, from: from);
      },
    ),
    // Kompatibilitási útvonal: /note/:noteId -> felhasználói olvasó nézet
    GoRoute(
      path: '/note/:noteId',
      builder: (context, state) {
        final noteId = state.pathParameters['noteId']!;
        final from = state.uri.queryParameters['from'];
        return NoteReadScreen(noteId: noteId, from: from);
      },
    ),
    // Interaktív jegyzet megtekintése
    GoRoute(
      path: '/interactive-note/:noteId',
      builder: (context, state) {
        final noteId = state.pathParameters['noteId']!;
        final from = state.uri.queryParameters['from'];
        return InteractiveNoteViewScreen(noteId: noteId, from: from);
      },
    ),
    GoRoute(
      path: '/quiz/:noteId',
      builder: (context, state) {
        final noteId = state.pathParameters['noteId']!;
        return DynamicQuizViewScreen(noteId: noteId);
      },
    ),
    // Interaktív jegyzet megtekintés megmaradhat, ha kell – külön request esetén visszahozzuk
    // Szerkesztés útvonal eltávolítva
    // További admin útvonalak eltávolítva
    // 2FA route eltávolítva a felhasználói webből
    // Flashcard deck megtekintés útvonal (csak olvasás)
    GoRoute(
      path: '/deck/:deckId/view',
      builder: (context, state) {
        final deckId = state.pathParameters['deckId']!;
        return FlashcardDeckViewScreen(deckId: deckId);
      },
    ),
    // Flashcard deck tanulás útvonal
    GoRoute(
      path: '/deck/:deckId/study',
      builder: (context, state) {
        final deckId = state.pathParameters['deckId']!;
        return FlashcardStudyScreen(deckId: deckId);
      },
    ),
    // Memóriapalota állomások megtekintése
    GoRoute(
      path: '/memoriapalota-allomas/:noteId',
      builder: (context, state) {
        final noteId = state.pathParameters['noteId']!;
        final from = state.uri.queryParameters['from'];
        return MemoriapalotaAllomasViewScreen(noteId: noteId, from: from);
      },
    ),
    // Memóriapalota fájlok megtekintése
    // Jogeset megtekintése
    // Az ID formátum lehet: "6_519" vagy "6_519#2" (dokumentum ID + jogeset ID)
    GoRoute(
      path: '/jogeset/:documentId',
      builder: (context, state) {
        final documentIdWithJogesetId = state.pathParameters['documentId']!;
        final from = state.uri.queryParameters['from'];

        // Különválasztjuk a dokumentum ID-t és a jogeset ID-t
        final parts = documentIdWithJogesetId.split('#');
        final documentId = parts[0];
        final jogesetIdStr = parts.length > 1 ? parts[1] : null;
        final jogesetId =
            jogesetIdStr != null ? int.tryParse(jogesetIdStr) : null;

        return JogesetViewScreen(
          documentId: documentId,
          jogesetId: jogesetId,
          from: from,
        );
      },
    ),
    GoRoute(
      path: '/account',
      builder: (context, state) => const AccountScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/change-password',
      builder: (context, state) => const ChangePasswordScreen(),
    ),
    GoRoute(
      path: '/terms-acceptance',
      builder: (context, state) => const TermsAcceptanceScreen(),
    ),
    // Felhasználói kötegek útvonalak
    GoRoute(
      path: '/my-bundles',
      builder: (context, state) => const UserBundleListScreen(),
    ),
    GoRoute(
      path: '/my-bundles/create',
      builder: (context, state) => const UserBundleEditScreen(),
    ),
    GoRoute(
      path: '/my-bundles/edit/:bundleId',
      builder: (context, state) {
        final bundleId = state.pathParameters['bundleId']!;
        return UserBundleEditScreen(bundleId: bundleId);
      },
    ),
    GoRoute(
      path: '/my-bundles/view/:bundleId',
      builder: (context, state) {
        final bundleId = state.pathParameters['bundleId']!;
        return UserBundleViewScreen(bundleId: bundleId);
      },
    ),
    // Dokumentum kiválasztás útvonalak (mobil)
    GoRoute(
      path: '/my-bundles/edit/:bundleId/add-notes',
      builder: (context, state) {
        final bundleId = state.pathParameters['bundleId']!;
        return DocumentSelectionScreen(
          bundleId: bundleId,
          documentType: 'notes',
        );
      },
    ),
    GoRoute(
      path: '/my-bundles/edit/:bundleId/add-allomasok',
      builder: (context, state) {
        final bundleId = state.pathParameters['bundleId']!;
        return DocumentSelectionScreen(
          bundleId: bundleId,
          documentType: 'allomasok',
        );
      },
    ),
    GoRoute(
      path: '/my-bundles/edit/:bundleId/add-dialogus',
      builder: (context, state) {
        final bundleId = state.pathParameters['bundleId']!;
        return DocumentSelectionScreen(
          bundleId: bundleId,
          documentType: 'dialogus',
        );
      },
    ),
    GoRoute(
      path: '/my-bundles/edit/:bundleId/add-jogeset',
      builder: (context, state) {
        final bundleId = state.pathParameters['bundleId']!;
        return DocumentSelectionScreen(
          bundleId: bundleId,
          documentType: 'jogeset',
        );
      },
    ),
  ],
);

/// Az alkalmazás gyökér widgetje.
///
/// Ez az osztály felelős a `MaterialApp` beállításáért, amely az egész
/// alkalmazás alapját képezi, beleértve a témát és a navigációt.
class MyApp extends StatefulWidget {
  /// A `MyApp` widget konstruktora.
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _versionCheckService = VersionCheckService();

  @override
  void initState() {
    super.initState();
    // Verzió ellenőrző szolgáltatás indítása (csak web platformon)
    if (kIsWeb) {
      _versionCheckService.start();
      debugPrint('[App] Version check service started');
    }
  }

  @override
  void dispose() {
    // Szolgáltatás leállítása
    if (kIsWeb) {
      _versionCheckService.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A `MaterialApp.router` a `go_router` használatához szükséges.
    // Ez köti össze a router konfigurációt az alkalmazás vizuális rétegével.
    // A DeviceChecker wrappert kivesszük: a router redirect dönti el a képernyőt
    return MaterialApp.router(
      title: 'Lomedu.hu',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: AppMessenger.key,
      routerConfig: _router,
    );
  }
}
