import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

/// SimplePay fizetési eredmény dialógusok
///
/// A SimplePay 3.13 előírásainak megfelelő kötelező dialógusok:
/// - 3.13.1: Megszakított fizetés
/// - 3.13.2: Időtúllépés
/// - 3.13.3: Sikertelen fizetés
/// - 3.13.4: Sikeres fizetés
class PaymentResultDialogs {
  /// Sikeres fizetés dialóg (SimplePay 3.13.4 szerint)
  static Future<void> showSuccessDialog(
    BuildContext context, {
    String? orderRef,
  }) async {
    // SimplePay transactionId és számlaszám lekérése
    String? transactionId;
    String? invoiceNumber;
    if (orderRef != null) {
      try {
        final paymentDoc = await FirebaseFirestore.instance
            .collection('web_payments')
            .doc(orderRef)
            .get();
        if (paymentDoc.exists) {
          final data = paymentDoc.data();
          transactionId = data?['simplePayTransactionId']?.toString() ??
              data?['transactionId']?.toString();
          invoiceNumber = data?['invoiceNumber']?.toString();
          debugPrint('SimplePay transactionId: $transactionId');
          debugPrint('Invoice number: $invoiceNumber');

          // Ha még nincs számlaszám, várunk egy kicsit és újra próbáljuk
          if (invoiceNumber == null) {
            await Future.delayed(const Duration(seconds: 2));
            final updatedDoc = await FirebaseFirestore.instance
                .collection('web_payments')
                .doc(orderRef)
                .get();
            if (updatedDoc.exists) {
              invoiceNumber = updatedDoc.data()?['invoiceNumber']?.toString();
              debugPrint('Invoice number after wait: $invoiceNumber');
            }
          }
        }
      } catch (e) {
        debugPrint('Hiba a payment adatok lekérdezésekor: $e');
      }
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[600], size: 28),
            const SizedBox(width: 12),
            const Text('Sikeres tranzakció'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A fizetés sikeresen megtörtént!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text(
                'Előfizetése aktiválva lett. Most már teljes hozzáférése van minden funkcióhoz.'),
            if (invoiceNumber != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200] ?? Colors.green),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt, color: Colors.green[700], size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Számlaszám:',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invoiceNumber,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.green[900],
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A számlát emailben is elküldtük.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (transactionId != null || orderRef != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SimplePay tranzakcióazonosító:',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      transactionId ?? orderRef!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Rendben'),
          ),
        ],
      ),
    );
  }

  /// Sikertelen fizetés dialóg (SimplePay 3.13.3 szerint - KÖTELEZŐ!)
  static Future<void> showFailedDialog(
    BuildContext context, {
    String? orderRef,
  }) async {
    // SimplePay transactionId lekérése
    String? transactionId;
    if (orderRef != null) {
      try {
        final paymentDoc = await FirebaseFirestore.instance
            .collection('web_payments')
            .doc(orderRef)
            .get();
        if (paymentDoc.exists) {
          transactionId =
              paymentDoc.data()?['simplePayTransactionId']?.toString();
          debugPrint('SimplePay transactionId (failed): $transactionId');
        }
      } catch (e) {
        debugPrint('Hiba a transactionId lekérdezésekor: $e');
      }
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[600], size: 28),
            const SizedBox(width: 12),
            const Text('Sikertelen tranzakció'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (transactionId != null || orderRef != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SimplePay tranzakcióazonosító:',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      transactionId ?? orderRef!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Kérjük, ellenőrizze a tranzakció során megadott adatok helyességét.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            const Text(
              'Amennyiben minden adatot helyesen adott meg, a visszautasítás okának '
              'kivizsgálása érdekében kérjük, szíveskedjen kapcsolatba lépni '
              'kártyakibocsátó bankjával.',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Bezárás'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/account');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Újrapróbálás'),
          ),
        ],
      ),
    );
  }

  /// Időtúllépés dialóg (SimplePay 3.13.2 szerint - KÖTELEZŐ!)
  static void showTimeoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          color: Colors.orange[600], size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Időtúllépés',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Ön túllépte a tranzakció elindításának lehetséges maximális idejét.',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A fizetési időkeret (30 perc) lejárt, mielőtt elindította volna a fizetést. '
                    'A tranzakció nem jött létre, így bankkártyája nem lett terhelve.',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  _buildNoChargeAssurance(),
                  const SizedBox(height: 24),
                  _buildDialogActions(ctx, context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Megszakított fizetés dialóg (SimplePay 3.13.1 szerint - KÖTELEZŐ!)
  static void showCancelledDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cancel_outlined,
                          color: Colors.grey[600], size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Megszakított fizetés',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Ön megszakította a fizetést.',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A fizetési folyamat megszakításra került (a "Vissza" gomb megnyomásával '
                    'vagy a böngésző bezárásával). A tranzakció nem jött létre.',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  _buildNoChargeAssurance(),
                  const SizedBox(height: 24),
                  _buildDialogActions(ctx, context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Közös widget: "Nem történt pénzügyi terhelés" biztosítás
  static Widget _buildNoChargeAssurance() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user, color: Colors.green[700], size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Biztosítjuk: Nem történt pénzügyi terhelés.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Közös widget: Dialógus gombok (Bezárás + Új fizetés)
  static Widget _buildDialogActions(BuildContext ctx, BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Bezárás'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.go('/account');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
          ),
          child: const Text('Új fizetés indítása'),
        ),
      ],
    );
  }
}
