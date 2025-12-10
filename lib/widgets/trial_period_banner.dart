import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Egy bannert jelenít meg, ami a felhasználó ingyenes próbaidejéből hátralévő időt mutatja.
/// Csak akkor jelenik meg, ha a felhasználó ingyenes státuszban van és a próbaidőszaka még nem járt le.
class TrialPeriodBanner extends StatelessWidget {
  final Map<String, dynamic> userData;

  const TrialPeriodBanner({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    final status = userData['subscriptionStatus'] as String?;
    final trialEndDate = userData['freeTrialEndDate'] as Timestamp?;

    // Csak akkor jelenítjük meg, ha a felhasználó "free" státuszban van
    // és a próbaidőszak lejárati dátuma a jövőben van.
    if (status != 'free' ||
        trialEndDate == null ||
        trialEndDate.toDate().isBefore(DateTime.now())) {
      return const SizedBox.shrink(); // Ne jelenítsen meg semmit
    }

    final daysLeft = trialEndDate.toDate().difference(DateTime.now()).inDays;

    // Ha kevesebb mint egy nap van hátra, 1 napot írunk ki.
    final displayDays = daysLeft < 1 ? 1 : daysLeft + 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFB0D4F1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF54595D), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ingyenes próbaidőszakodból még $displayDays nap van hátra.',
              style: const TextStyle(
                color: Color(0xFF202122),
                fontWeight: FontWeight.w400,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



