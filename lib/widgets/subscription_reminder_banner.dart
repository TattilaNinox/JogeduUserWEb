import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/subscription_reminder_service.dart';

/// Előfizetési emlékeztető banner widget
///
/// Megjeleníti a lejárat előtti emlékeztetőket és értesítéseket
/// a prepaid előfizetési rendszerhez.
class SubscriptionReminderBanner extends StatefulWidget {
  final VoidCallback? onRenewPressed;
  final VoidCallback? onDismissed;

  const SubscriptionReminderBanner({
    super.key,
    this.onRenewPressed,
    this.onDismissed,
  });

  @override
  State<SubscriptionReminderBanner> createState() =>
      _SubscriptionReminderBannerState();
}

class _SubscriptionReminderBannerState
    extends State<SubscriptionReminderBanner> {
  bool _isVisible = false;
  SubscriptionStatusColor _statusColor = SubscriptionStatusColor.free;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _isVisible = false;
      });
      return;
    }

    try {
      final shouldShowReminder =
          await SubscriptionReminderService.shouldShowReminder(user.uid);
      final isExpired =
          await SubscriptionReminderService.isSubscriptionExpired(user.uid);
      final shouldShowExpiryNotification =
          await SubscriptionReminderService.shouldShowExpiryNotification(
              user.uid);

      if (shouldShowReminder || isExpired || shouldShowExpiryNotification) {
        final statusColor =
            await SubscriptionReminderService.getSubscriptionStatusColor(
                user.uid);

        setState(() {
          _isVisible = true;
          _statusColor = statusColor;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isVisible = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isVisible = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFB0D4F1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _statusColor == SubscriptionStatusColor.expired
              ? widget.onRenewPressed
              : null,
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  _getBannerIcon(),
                  color: const Color(0xFF54595D),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getBannerTitle(),
                        style: const TextStyle(
                          color: Color(0xFF202122),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getBannerMessage(),
                        style: const TextStyle(
                          color: Color(0xFF54595D),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_statusColor == SubscriptionStatusColor.expired) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: widget.onRenewPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    child: const Text(
                      'Megújítás',
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isVisible = false;
                    });
                    widget.onDismissed?.call();
                  },
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF54595D),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getBannerIcon() {
    switch (_statusColor) {
      case SubscriptionStatusColor.free:
        return Icons.info_outline;
      case SubscriptionStatusColor.premium:
        return Icons.check_circle_outline;
      case SubscriptionStatusColor.warning:
        return Icons.warning_outlined;
      case SubscriptionStatusColor.expired:
        return Icons.error_outline;
    }
  }

  String _getBannerTitle() {
    switch (_statusColor) {
      case SubscriptionStatusColor.free:
        return 'Ingyenes fiók';
      case SubscriptionStatusColor.premium:
        return 'Premium előfizetés';
      case SubscriptionStatusColor.warning:
        return 'Előfizetés lejárat';
      case SubscriptionStatusColor.expired:
        return 'Előfizetés lejárt';
    }
  }

  String _getBannerMessage() {
    switch (_statusColor) {
      case SubscriptionStatusColor.free:
        return 'Frissítsen premium előfizetésre a teljes hozzáférésért';
      case SubscriptionStatusColor.premium:
        return 'Előfizetése aktív és minden funkció elérhető';
      case SubscriptionStatusColor.warning:
        return 'Előfizetése hamarosan lejár. Érdemes megújítani a folyamatos hozzáférésért';
      case SubscriptionStatusColor.expired:
        return 'Előfizetése lejárt. Frissítse a fizetést a folytatáshoz';
    }
  }
}
