import 'package:flutter/material.dart';

/// Globális üzenetküldő a SnackBar-ok megjelenítéséhez, navigációtól függetlenül.
class AppMessenger {
  static final GlobalKey<ScaffoldMessengerState> key =
      GlobalKey<ScaffoldMessengerState>();

  static void showSnackBar(SnackBar snackBar) {
    key.currentState?.showSnackBar(snackBar);
  }

  static void showSuccess(String message) {
    key.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static void showError(String message) {
    key.currentState?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
