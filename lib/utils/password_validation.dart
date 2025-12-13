class PasswordValidation {
  static final RegExp _policy =
      RegExp(r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$');

  static bool isStrong(String password) => _policy.hasMatch(password);

  static String? errorText(String password) {
    if (password.length < 8) return 'Legalább 8 karakter szükséges.';
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Legalább egy nagybetű szükséges.';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Legalább egy kisbetű szükséges.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Legalább egy szám szükséges.';
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Legalább egy speciális karakter szükséges.';
    }
    return null;
  }
}
