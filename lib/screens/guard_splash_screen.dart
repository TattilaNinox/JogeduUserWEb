import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Rövid splash/guard képernyő az auth + eszköz ellenőrzés idejére.
class GuardSplashScreen extends StatelessWidget {
  const GuardSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final paymentParam = qp['payment'];
    
    // Ha van payment callback, akkor azonnal átirányítunk account-ra
    if (paymentParam != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          final queryString = Uri(queryParameters: qp).query;
          context.go('/account${queryString.isNotEmpty ? '?$queryString' : ''}');
        }
      });
    }

    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(),
            ),
            SizedBox(height: 16),
            Text('Ellenőrzés folyamatban...'),
          ],
        ),
      ),
    );
  }
}
