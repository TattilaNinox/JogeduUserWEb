import 'package:flutter/material.dart';

class LearningStatusBadge extends StatelessWidget {
  final String state;
  final String lastRating;
  final bool isDue;
  
  const LearningStatusBadge({
    super.key,
    required this.state,
    required this.lastRating,
    required this.isDue,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    IconData icon;
    String label;

    switch (state) {
      case 'NEW':
        backgroundColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        icon = Icons.fiber_new;
        label = 'Új';
        break;
      case 'LEARNING':
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        icon = Icons.school;
        label = 'Tanulás';
        break;
      case 'REVIEW':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        icon = Icons.refresh;
        label = 'Ismétlés';
        break;
      default:
        backgroundColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        icon = Icons.help_outline;
        label = 'Ismeretlen';
    }

    // Ha esedékes, akkor kicsit kiemeljük
    if (isDue && state != 'NEW') {
        backgroundColor = backgroundColor.withValues(alpha: 0.8);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: textColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          if (lastRating.isNotEmpty && lastRating != 'Again') ...[
            const SizedBox(width: 4),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _getRatingColor(lastRating),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getRatingColor(String rating) {
    switch (rating) {
      case 'Hard':
        return Colors.orange;
      case 'Good':
        return Colors.green;
      case 'Easy':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
