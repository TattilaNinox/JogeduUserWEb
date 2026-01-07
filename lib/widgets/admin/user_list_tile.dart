import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Felhasználó lista tile widget az admin képernyőhöz
///
/// Megjeleníti:
/// - Felhasználó email és regisztráció dátuma
/// - Előfizetési státusz (premium, próbaidő, lejárt, stb.)
/// - Előfizetési részletek (lejárat dátuma, próbaidő intervallum)
class UserListTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final bool isSelectModeActive;
  final bool isSelected;
  final ValueChanged<bool?>? onCheckboxChanged;
  final PopupMenuItemSelected<String>? onMenuSelected;

  const UserListTile({
    super.key,
    required this.doc,
    required this.isSelectModeActive,
    required this.isSelected,
    this.onCheckboxChanged,
    this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'Ismeretlen email';
    final createdAt = data['createdAt'] as Timestamp?;
    final createdDate =
        createdAt?.toDate().toString().split(' ')[0] ?? 'Ismeretlen dátum';
    final subscriptionStatus = data['subscriptionStatus'] as String? ?? 'free';
    final userType = data['userType'] as String? ?? 'normal';
    final trialEndDate = data['trialEndDate'] as Timestamp?;
    final isSubscriptionActive = data['isSubscriptionActive'] as bool? ?? false;
    final isActive = data['isActive'] as bool? ?? true;

    String statusText = 'Ingyenes';
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.person;

    final subscriptionEndDate = data['subscriptionEndDate'] as Timestamp?;
    final freeTrialStartDate = data['freeTrialStartDate'] as Timestamp?;
    final freeTrialEndDate = data['freeTrialEndDate'] as Timestamp?;

    if (!isActive) {
      statusText = 'Inaktív';
      statusColor = Colors.red.shade300;
      statusIcon = Icons.block;
    } else if (userType == 'test') {
      statusText = 'Teszt felhasználó';
      statusColor = Colors.orange;
      statusIcon = Icons.science;
    } else if (userType == 'admin') {
      statusText = 'Admin';
      statusColor = Colors.red;
      statusIcon = Icons.admin_panel_settings;
    } else if (subscriptionStatus == 'expired' ||
        (!isSubscriptionActive && subscriptionStatus == 'premium')) {
      statusText = 'Lejárt előfizetés';
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
    } else if (isSubscriptionActive && subscriptionStatus == 'premium') {
      statusText = 'Premium aktív';
      if (subscriptionEndDate != null) {
        final remainingDays =
            subscriptionEndDate.toDate().difference(DateTime.now()).inDays;
        statusText += ' ($remainingDays nap)';
      }
      statusColor = Colors.green;
      statusIcon = Icons.star;
    } else if (freeTrialEndDate != null &&
        DateTime.now().isBefore(freeTrialEndDate.toDate())) {
      final remainingDays =
          freeTrialEndDate.toDate().difference(DateTime.now()).inDays;
      statusText = 'Próbaidő: $remainingDays nap';
      statusColor = Colors.purple;
      statusIcon = Icons.schedule;
    } else if (trialEndDate != null &&
        DateTime.now().isBefore(trialEndDate.toDate())) {
      final remainingDays =
          trialEndDate.toDate().difference(DateTime.now()).inDays;
      statusText = 'Próbaidő (legacy): $remainingDays nap';
      statusColor = Colors.purple.shade300;
      statusIcon = Icons.schedule;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        dense: true,
        minVerticalPadding: 4,
        leading: isSelectModeActive
            ? Checkbox(
                value: isSelected,
                onChanged: onCheckboxChanged,
              )
            : CircleAvatar(
                backgroundColor: statusColor,
                child: Icon(
                  statusIcon,
                  color: Colors.white,
                  size: 16,
                ),
              ),
        title: Text(
          email,
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Regisztráció: $createdDate',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (subscriptionEndDate != null) ...[
              Text(
                'Előfizetés vége: ${subscriptionEndDate.toDate().toString().split(' ')[0]}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (freeTrialStartDate != null && freeTrialEndDate != null) ...[
              Text(
                'Próbaidő: ${freeTrialStartDate.toDate().toString().split(' ')[0]} - ${freeTrialEndDate.toDate().toString().split(' ')[0]}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: onMenuSelected,
          itemBuilder: (context) => _buildMenuItems(data),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(Map<String, dynamic> data) {
    return [
      const PopupMenuItem(
        value: 'make_test',
        child: Text('Teszt felhasználó'),
      ),
      const PopupMenuItem(
        value: 'make_normal',
        child: Text('Normál felhasználó'),
      ),
      const PopupMenuItem(
        value: 'activate_premium',
        child: Text('Premium aktiválás (30 nap)'),
      ),
      const PopupMenuItem(
        value: 'set_expired',
        child:
            Text('Előfizetés lejáratása', style: TextStyle(color: Colors.red)),
      ),
      const PopupMenuItem(
        value: 'renew_trial',
        child: Text('5 napos próbaidő újraindítása'),
      ),
      const PopupMenuItem(
        value: 'extend_trial',
        child: Text('Próbaidő meghosszabbítás'),
      ),
      const PopupMenuItem(
        value: 'shorten_trial',
        child: Text('Próbaidő rövidítése (napok)'),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'reset_to_default',
        child: Text('Alaphelyzetbe állítás',
            style:
                TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
      ),
      const PopupMenuItem(
        value: 'token_cleanup',
        child: Text('Token cleanup'),
      ),
      const PopupMenuItem(
        value: 'manual_refund',
        child: Text('Manuális refund'),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: data['isActive'] == false ? 'activate' : 'deactivate',
        child: Text(data['isActive'] == false
            ? 'Felhasználó aktiválása'
            : 'Felhasználó inaktiválása'),
      ),
    ];
  }
}
