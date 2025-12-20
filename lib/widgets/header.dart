import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Az alkalmazás felső fejlécét (Header) megvalósító widget.
///
/// Ez egy `StatelessWidget`, amely tartalmazza a keresőmezőt,
/// és opcionálisan a jobb oldali akciókat.
class Header extends StatelessWidget {
  /// Keresési callback
  final ValueChanged<String> onSearchChanged;

  /// Megjelenjenek-e a jobb oldali akciógombok
  final bool showActions;

  const Header(
      {super.key, required this.onSearchChanged, this.showActions = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      margin: const EdgeInsets.only(top: 10, left: 2, right: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            spreadRadius: 0,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Keresőmező – teljes szélességre nyúlik
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Keresés...',
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  prefixIcon: const Icon(Icons.search,
                      color: Color(0xFF6B7280), size: 20),
                ),
              ),
            ),
          ),
          if (showActions) ...[
            const SizedBox(width: 12),
            // Jobb oldali akció: "Fiók adatok"
            ElevatedButton(
              onPressed: () {
                context.go('/account');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text('Fiók adatok',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) context.go('/login');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text('Kijelentkezés',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ],
      ),
    );
  }
}
