import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';

/// Az alkalmazás oldalsó menüsávját (sidebar) megvalósító widget.
///
/// Ez egy `StatelessWidget`, mivel a saját állapotát nem változtatja meg;
/// a megjelenése kizárólag a konstruktorban kapott `selectedMenu`
/// paramétertől függ. Felelős a fő navigációs linkek és a kijelentkezés
/// gomb megjelenítéséért.
class Sidebar extends StatelessWidget {
  /// Annak a menüpontnak az azonosítója, amelyik éppen aktív.
  /// Ezt a szülő widget adja át, és ez határozza meg, hogy melyik
  /// menüpont lesz vizuálisan kiemelve.
  final String selectedMenu;

  /// Opcionális extra panel, amely a menüpontok alatt jelenik meg
  /// (pl. szűrő űrlap a jegyzetek oldalon).
  final Widget? extraPanel;

  /// Jelezze, hogy a Sidebar Drawer-ben van-e.
  final bool isDrawer;

  /// A `Sidebar` widget konstruktora.
  const Sidebar(
      {super.key,
      required this.selectedMenu,
      this.extraPanel,
      this.isDrawer = false});

  void _navigate(BuildContext context, String path) {
    // Ha a Sidebar egy Drawer-ben van, előbb zárjuk be a Drawert
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);

    if (isDrawer && navigator.canPop()) {
      navigator.pop();
      // A pop után ütemezzük a navigációt
      Future.microtask(() => router.go(path));
    } else {
      router.go(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Egy fix szélességű konténer, ami a menüsáv alapját képezi.
    // Reszponzív szélesség: nagyobb képernyőkön szélesebb
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = screenWidth >= 1400
        ? 280.0
        : screenWidth >= 1200
            ? 240.0
            : 200.0;

    return Container(
      width: sidebarWidth,
      color: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: InkWell(
                onTap: () => _navigate(context, '/notes'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Builder(builder: (context) {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      return const Text(
                        'Felhasználó',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E3A8A),
                        ),
                      );
                    }
                    return StreamBuilder(
                      stream: FirebaseConfig.firestore
                          .collection('users')
                          .doc(user.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        String text = 'Felhasználó';
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final data =
                              (snapshot.data!.data() as Map<String, dynamic>);
                          final first = (data['firstName'] ??
                                  data['first_name'] ??
                                  data['givenName'] ??
                                  data['given_name'])
                              ?.toString();
                          final last = (data['lastName'] ??
                                  data['last_name'] ??
                                  data['familyName'] ??
                                  data['family_name'])
                              ?.toString();
                          if (first != null &&
                              first.isNotEmpty &&
                              last != null &&
                              last.isNotEmpty) {
                            text = '$last $first'; // HU: Vezetéknév Keresztnév
                          }
                        }
                        if (text == 'Felhasználó') {
                          final dn = user.displayName;
                          if (dn != null && dn.isNotEmpty) {
                            final parts = dn.trim().split(RegExp(r"\s+"));
                            if (parts.length == 2) {
                              text = '${parts[1]} ${parts[0]}'; // HU sorrend
                            } else {
                              text = dn;
                            }
                          } else if (user.email != null) {
                            text = user.email!;
                          }
                        }
                        return Text(
                          text,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E3A8A),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ),
            ),
            _buildMenuItem(
                context, 'notes', 'Tags Főoldal', selectedMenu == 'notes'),
            if (extraPanel != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: extraPanel!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Egyetlen menüpontot felépítő segédmetódus.
  ///
  /// Ez a metódus a kapott paraméterek alapján létrehoz egy `ListTile` widgetet,
  /// ami egy navigációs menüpontként funkcionál.
  ///
  /// [context] A widget build kontextusa.
  /// [routeName] A menüponthoz tartozó útvonal azonosítója.
  /// [title] A menüponton megjelenő szöveg.
  /// [isSelected] Igaz, ha ez a menüpont van éppen kiválasztva.
  Widget _buildMenuItem(
      BuildContext context, String routeName, String title, bool isSelected) {
    // A `routeName` alapján kiválasztja a megfelelő ikont.
    final IconData iconData;
    switch (routeName) {
      case 'notes':
        iconData = Icons.list_alt;
        break;
      case 'note_create':
        iconData = Icons.note_add;
        break;
      case 'interactive_note_create':
        iconData = Icons.web;
        break;
      case 'dynamic_quiz_create':
        iconData = Icons.quiz;
        break;
      case 'dynamic_quiz_dual_create':
        iconData = Icons.quiz_outlined;
        break;
      case 'bundles':
        iconData = Icons.collections_bookmark;
        break;
      case 'question_banks':
        iconData = Icons.quiz;
        break;
      case 'subjects':
        iconData = Icons.school;
        break;
      case 'sciences':
        iconData = Icons.science;
        break;
      case 'categories':
        iconData = Icons.category;
        break;
      case 'decks':
        iconData = Icons.style;
        break;
      case 'users':
        iconData = Icons.people;
        break;
      case 'public_documents':
        iconData = Icons.article;
        break;
      default:
        iconData = Icons.error;
    }

    // A `ListTile` egy kényelmes widget sorok létrehozására, amelyek
    // általában ikont, szöveget és egy kattintási eseményt tartalmaznak.
    return ListTile(
      leading: Icon(iconData,
          color:
              isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF6B7280)),
      title: Text(
        title,
        // A stílus (szín, vastagság) a `isSelected` állapottól függően változik.
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF6B7280),
        ),
      ),
      // A háttérszín is a `isSelected` állapottól függ.
      tileColor: isSelected ? Colors.black.withAlpha(51) : Colors.transparent,
      // A `onTap` esemény a `go_router` segítségével a megfelelő útvonalra navigál.
      onTap: () {
        if (routeName == 'notes') {
          _navigate(context, '/notes');
        } else if (routeName == 'note_create') {
          _navigate(context, '/notes/create');
        } else if (routeName == 'interactive_note_create') {
          _navigate(context, '/interactive-notes/create');
        } else if (routeName == 'dynamic_quiz_create') {
          _navigate(context, '/dynamic-quiz/create');
        } else if (routeName == 'dynamic_quiz_dual_create') {
          _navigate(context, '/dynamic-quiz-dual/create');
        } else if (routeName == 'bundles') {
          _navigate(context, '/bundles');
        } else if (routeName == 'question_banks') {
          _navigate(context, '/question-banks');
        } else if (routeName == 'categories') {
          _navigate(context, '/categories');
        } else if (routeName == 'sciences') {
          _navigate(context, '/sciences');
        } else if (routeName == 'decks') {
          _navigate(context, '/decks');
        } else if (routeName == 'users') {
          _navigate(context, '/users');
        } else if (routeName == 'public_documents') {
          _navigate(context, '/public-documents');
        }
      },
    );
  }
}
