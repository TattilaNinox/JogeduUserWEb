import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/web_payment_service.dart';
import 'data_transfer_consent_dialog.dart';
import 'simplepay_logo.dart';

/// Webes fizetési csomagok widget
///
/// Megjeleníti a rendelkezésre álló fizetési csomagokat és kezeli a fizetés indítását.
class WebPaymentPlans extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final VoidCallback? onPaymentInitiated;

  const WebPaymentPlans({
    super.key,
    required this.userData,
    this.onPaymentInitiated,
  });

  @override
  State<WebPaymentPlans> createState() => _WebPaymentPlansState();
}

class _WebPaymentPlansState extends State<WebPaymentPlans> {
  String? _selectedPlan;
  bool _isProcessing = false;

  /// Admin ellenőrzés
  bool _isAdmin() {
    if (widget.userData == null) return false;
    final userData = widget.userData!;
    final isAdminValue = userData['isAdmin'];
    final isAdminBool = isAdminValue is bool && isAdminValue == true;
    final email = userData['email'];
    final isAdminEmail = email == 'tattila.ninox@gmail.com';
    return isAdminBool || isAdminEmail;
  }

  /// Admin ár számítása
  String _getFormattedPrice(PaymentPlan plan) {
    final isAdmin = _isAdmin();
    final price = isAdmin ? 5 : plan.price;
    return '${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} Ft';
  }

  @override
  Widget build(BuildContext context) {
    // Ha a felhasználó már prémium, ne jelenítsük meg a csomagokat
    final subscriptionStatus = widget.userData?['subscriptionStatus'] ?? 'free';
    final isSubscriptionActive =
        widget.userData?['isSubscriptionActive'] ?? false;

    if (subscriptionStatus == 'premium' && isSubscriptionActive) {
      return _buildActiveSubscriptionCard();
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Icon(
                Icons.credit_card,
                size: 24,
                color: Color(0xFF1E3A8A),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Fizetési csomagok',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Csomagok listája
          ...WebPaymentService.availablePlans
              .map((plan) => _buildPlanCard(plan)),

          const SizedBox(height: 20),

          // Információk
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.security, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      'Biztonságos fizetés',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• OTP SimplePay biztonságos fizetési rendszer\n'
                  '• Bankkártya adatok nem tárolódnak nálunk\n'
                  '• 30 napos pénzvisszafizetési garancia\n'
                  '• Bármikor lemondható',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // SimplePay logó (kötelező a SimplePay szabályok szerint)
          const SimplePayLogo(
            centered: true,
            margin: EdgeInsets.symmetric(vertical: 8),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSubscriptionCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle,
            size: 48,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          const Text(
            'Aktív előfizetés',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ön már rendelkezik aktív előfizetéssel.\n'
            'A csomag kezeléséhez látogasson el a Google Play Store-ba.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(PaymentPlan plan) {
    final isSelected = _selectedPlan == plan.id;
    final isProcessing = _isProcessing && _selectedPlan == plan.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: plan.popular
              ? Colors.blue
              : (isSelected ? Colors.blue : Colors.grey[300]!),
          width: plan.popular ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color:
            plan.popular ? Colors.blue.withValues(alpha: 0.02) : Colors.white,
      ),
      child: Column(
        children: [
          // Popular badge
          if (plan.popular)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: const Text(
                'Legnépszerűbb',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            plan.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _getFormattedPrice(plan),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        Text(
                          plan.periodText,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Features
                ...plan.features.map((feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.green[600],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),

                const SizedBox(height: 20),

                // Action button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        isProcessing ? null : () => _handlePlanSelection(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          plan.popular ? Colors.blue[600] : Colors.grey[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isProcessing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Feldolgozás...'),
                            ],
                          )
                        : Text(
                            'Választás - ${_getFormattedPrice(plan)}${plan.periodText}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePlanSelection(PaymentPlan plan) async {
    if (!kIsWeb) {
      _showError('Ez a funkció csak webes böngészőben érhető el');
      return;
    }

    if (!WebPaymentService.isConfigured) {
      _showError(
          'SimplePay konfiguráció hiányzik. Kérjük, lépjen kapcsolatba a támogatással.');
      return;
    }

    // ELŐSZÖR: Szállítási cím ellenőrzése (MINDEN MÁS ELŐTT!)
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      _showError('Nincs bejelentkezett felhasználó');
      return;
    }
    final uid = authUser.uid;

    DocumentSnapshot<Map<String, dynamic>>? userDoc;
    try {
      userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      
      if (!userDoc.exists) {
        debugPrint('[WebPaymentPlans] ❌ User document does not exist');
        _showError('Kérjük, töltsd ki a szállítási adatokat!');
        return;
      }

      final shippingAddress = userDoc.data()?['shippingAddress'] as Map<String, dynamic>?;
      
      debugPrint('[WebPaymentPlans] Shipping address check: ${shippingAddress != null ? 'exists' : 'null'}');
      debugPrint('[WebPaymentPlans] Shipping address content: $shippingAddress');
      
      // SZIGORÚ ELLENŐRZÉS: Minden kötelező mező ki kell legyen töltve
      bool isValid = false;
      
      if (shippingAddress != null && 
          shippingAddress.isNotEmpty) {
        final name = (shippingAddress['name']?.toString() ?? '').trim();
        final zipCode = (shippingAddress['zipCode']?.toString() ?? '').trim();
        final city = (shippingAddress['city']?.toString() ?? '').trim();
        final address = (shippingAddress['address']?.toString() ?? '').trim();
        
        debugPrint('[WebPaymentPlans] Address fields - name: "$name", zipCode: "$zipCode", city: "$city", address: "$address"');
        
        // MINDEN kötelező mező NEM ÜRES kell legyen ÉS érvényes formátumú
        final nameValid = name.isNotEmpty && name.length >= 2;
        final zipCodeValid = zipCode.isNotEmpty && 
                            zipCode.length == 4 && 
                            RegExp(r'^\d{4}$').hasMatch(zipCode);
        final cityValid = city.isNotEmpty && city.length >= 2;
        final addressValid = address.isNotEmpty && address.length >= 5;
        
        debugPrint('[WebPaymentPlans] Validation - name: $nameValid, zipCode: $zipCodeValid, city: $cityValid, address: $addressValid');
        
        isValid = nameValid && zipCodeValid && cityValid && addressValid;
        
        debugPrint('[WebPaymentPlans] Final validation result: $isValid');
      } else {
        debugPrint('[WebPaymentPlans] ❌ Shipping address is null or empty');
      }

      // HA NEM ÉRVÉNYES → BLOKKOLJUK A FIZETÉST
      if (!isValid) {
        debugPrint('[WebPaymentPlans] ❌❌❌ BLOCKING PAYMENT - Shipping address invalid or missing');
        _showError('Kérjük, töltsd ki a szállítási adatokat!');
        return;
      }
      
      debugPrint('[WebPaymentPlans] ✅ Shipping address validation PASSED');
    } catch (e) {
      debugPrint('[WebPaymentPlans] ❌ Error checking shipping address: $e');
      _showError('Kérjük, töltsd ki a szállítási adatokat!');
      return;
    }

    // Most már beállítjuk a loading állapotot, mert minden ellenőrzésen túl vagyunk
    if (!mounted) return;
    setState(() {
      _selectedPlan = plan.id;
      _isProcessing = true;
    });

    try {
      // 2. KÖTELEZŐ: Adattovábbítási nyilatkozat elfogadása
      final consentAccepted = await DataTransferConsentDialog.show(context);
      if (!consentAccepted) {
        // Felhasználó nem fogadta el a nyilatkozatot
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _selectedPlan = null;
          });
        }
        _showError(
            'A fizetés folytatásához el kell fogadnia az adattovábbítási nyilatkozatot.');
        return;
      }

      // 3. Firestore frissítése: consent elfogadás dátumának rögzítése
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'dataTransferConsentLastAcceptedDate': FieldValue.serverTimestamp(),
      });

      // 4. Szállítási cím lekérése (már validálva van)
      // userDoc biztosan nem null és létezik, mert ha nem, akkor már a validáció során return-öltünk volna
      final addressData = userDoc.data()?['shippingAddress'] as Map<String, dynamic>?;
      Map<String, String>? shippingAddressMap;
      if (addressData != null && addressData.isNotEmpty) {
        shippingAddressMap = Map<String, String>.from(
          addressData.map((key, value) => MapEntry(key, value.toString())),
        );
      }

      // 5. Fizetés indítása Cloud Function-nel
      final result = await WebPaymentService.initiatePaymentViaCloudFunction(
        planId: plan.id,
        userId: uid,
        shippingAddress: shippingAddressMap,
      );

      if (result.success && result.paymentUrl != null) {
        // Átirányítás a SimplePay fizetési oldalra
        if (kIsWeb) {
          // Web esetén payment dialog megjelenítése
          _showPaymentDialog(result.paymentUrl!);
        }
      } else {
        throw Exception(result.error ?? 'Fizetés indítása sikertelen');
      }
    } catch (e) {
      _showError('Hiba történt a fizetés indítása során: $e');
    } finally {
      setState(() {
        _isProcessing = false;
        _selectedPlan = null;
      });
    }
  }

  void _showPaymentDialog(String paymentUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Fizetés'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Átirányítjuk a biztonságos fizetési oldalra...'),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Manuális átirányítás
                _openPaymentUrl(paymentUrl);
              },
              child: const Text('Manuális átirányítás'),
            ),
          ],
        ),
      ),
    );
  }

  void _openPaymentUrl(String url) {
    if (!kIsWeb) return;
    launchUrlString(url, mode: LaunchMode.platformDefault);
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red[600],
        ),
      );
    }
  }
}
