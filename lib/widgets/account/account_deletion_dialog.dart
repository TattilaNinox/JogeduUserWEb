import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../services/account_deletion_service.dart';

/// Fiók törlés megerősítő dialógus
///
/// Újrahasználható widget, amely kezeli:
/// - Jelszó bekérést
/// - Törlés folyamatot
/// - Hibaüzeneteket
class AccountDeletionDialog extends StatefulWidget {
  const AccountDeletionDialog({super.key});

  /// Megjeleníti a dialógust és végrehajtja a törlést ha megerősítették
  static Future<bool> show(BuildContext context) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nincs bejelentkezett felhasználó.')),
      );
      return false;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const AccountDeletionDialog(),
        ) ??
        false;

    if (confirmed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fiók sikeresen törölve.')),
      );
      context.go('/login');
    }

    return confirmed;
  }

  @override
  State<AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<AccountDeletionDialog> {
  final _passwordCtrl = TextEditingController();
  String? _errorText;
  bool _isLoading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await AccountDeletionService.deleteAccount(_passwordCtrl.text);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'wrong-password':
          msg = 'Hibás jelszó.';
          break;
        case 'requires-recent-login':
          msg = 'A művelethez friss bejelentkezés szükséges.';
          break;
        default:
          msg = 'Hitelesítési hiba: ${e.message ?? e.code}';
      }
      setState(() {
        _errorText = msg;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorText = 'Hiba történt: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fiók végleges törlése'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Biztosan törölni szeretnéd a fiókodat?\n\n'
            'A törlés végleges. A profilod és az adataid eltávolításra kerülnek.\n'
            'A későbbiekben nem tudjuk visszaállítani.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: 'Jelszó',
              errorText: _errorText,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Mégse'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleDelete,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[700],
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Végleges törlés'),
        ),
      ],
    );
  }
}
