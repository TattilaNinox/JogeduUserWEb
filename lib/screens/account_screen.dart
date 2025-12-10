import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/email_notification_service.dart';
import '../widgets/subscription_reminder_banner.dart';
import '../widgets/enhanced_subscription_status_card.dart';
import '../widgets/subscription_renewal_button.dart';
import '../services/account_deletion_service.dart';
import '../widgets/trial_period_banner.dart';
import '../widgets/simplepay_logo.dart';
import '../widgets/web_payment_history.dart';
import '../widgets/shipping_address_form.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Egyszerű fiókadatok képernyő, előfizetési státusszal.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // PostFrameCallback használata - NEM blokkolja a build-et
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePaymentCallback();
    });
  }

  Future<void> _handlePaymentCallback() async {
    if (!mounted) return;

    final qp = GoRouterState.of(context).uri.queryParameters;
    final paymentStatus = qp['payment'];
    final orderRef = qp['orderRef'];

    if (paymentStatus != null && orderRef != null && !_dialogShown) {
      _dialogShown = true;

      // Frissítjük a payment status-t a háttérben (NEM várjuk meg!)
      FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('updatePaymentStatusFromCallback')
          .call({
        'orderRef': orderRef,
        'callbackStatus': paymentStatus,
      }).then((_) {
        debugPrint('[PaymentCallback] Status updated: $paymentStatus');
      }).catchError((e) {
        debugPrint('[PaymentCallback] Update error: $e');
      });

      // Sikeres fizetés esetén megerősítjük a fizetést (confirmWebPayment)
      // Ez biztosítja, hogy az előfizetés aktiválódjon, még ha a SimplePay nem irányított vissza is
      if (paymentStatus == 'success') {
        try {
          FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('confirmWebPayment')
              .call({
            'orderRef': orderRef,
          }).then((result) {
            debugPrint('[PaymentCallback] Payment confirmed: $result');
          }).catchError((e) {
            debugPrint('[PaymentCallback] Confirm error (non-critical): $e');
            // Nem kritikus hiba - a webhook már aktiválhatta az előfizetést
          });
        } catch (e) {
          debugPrint('[PaymentCallback] Confirm call error: $e');
        }
      }

      // Várunk egy kicsit, majd megjelenítjük a dialógot
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;

      // Megjelenítjük a dialógot
      switch (paymentStatus) {
        case 'success':
          await _showPaymentSuccessDialog(context, orderRef);
          break;
        case 'fail':
          await _showPaymentFailedDialog(context, orderRef);
          break;
        case 'timeout':
          _showPaymentTimeoutDialog(context);
          break;
        case 'cancelled':
          _showPaymentCancelledDialog(context);
          break;
        default:
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Fizetés státusz: $paymentStatus')),
            );
          }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ha fizetési visszatérés van (SimplePay callback), akkor engedjük be a felhasználót
    // és mutatjuk a loading állapotot, amíg a user inicializálódik
    final qp = GoRouterState.of(context).uri.queryParameters;
    if (qp.containsKey('payment')) {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(title: const Text('Fiók adatok')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          // Ha valamiért nincs user, de payment callback van (pl. session elveszett),
          // akkor automatikusan átirányítjuk a bejelentkezésre
          if (!snapshot.hasData) {
            // PostFrameCallback használata az átirányításhoz (build közben nem lehet)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                final uri = GoRouterState.of(context).uri;
                final qp = uri.queryParameters;
                final queryString = Uri(queryParameters: qp).query;
                // Átirányítás a loginra, redirect paraméterrel
                context.go('/login?redirect=/account?$queryString');
              }
            });

            // Amíg az átirányítás megtörténik, egy töltőképernyőt mutatunk
            return Scaffold(
              appBar: AppBar(title: const Text('Fiók adatok')),
              body: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Átirányítás a bejelentkezéshez...'),
                  ],
                ),
              ),
            );
          }

          return _buildAccountContent(context, snapshot.data!);
        },
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Ha nincs bejelentkezve, irányítsuk át a loginra
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/login');
        }
      });

      return Scaffold(
        appBar: AppBar(
          title: const Text('Fiók adatok'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/notes'),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Minden bejelentkezett felhasználónak megengedjük a hozzáférést
    return _buildAccountContent(context, user);
  }

  Widget _buildAccountContent(
    BuildContext context,
    User user,
  ) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Fiók adatok'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/notes'),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          // Ellenőrizzük, hogy a widget még mounted-e
          if (!mounted) {
            return const SizedBox.shrink();
          }

          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(
                child: Text('Nincsenek adataink a felhasználóról.'));
          }
          final data = userSnapshot.data!.data()!;

          // Admin ellenőrzés
          final isAdminValue = data['isAdmin'];
          final isAdminBool = isAdminValue is bool && isAdminValue == true;
          final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
          final isAdmin = isAdminBool || isAdminEmail;

          debugPrint(
              '[AccountScreen] Admin check - email: ${user.email}, isAdmin field: $isAdminValue, isAdminBool: $isAdminBool, isAdminEmail: $isAdminEmail, final isAdmin: $isAdmin');

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // Emlékeztető banner
              SubscriptionReminderBanner(
                onRenewPressed: () => context.go('/account'),
              ),

              // Próbaidőszak bannere
              TrialPeriodBanner(userData: data),

              // Felhasználói adatok + műveletek (felső sávban)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: const Color(0xFFB0D4F1),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Kis képernyőn (< 700px) oszlopos elrendezés
                      final isSmallScreen = constraints.maxWidth < 700;

                      if (isSmallScreen) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Felhasználói adatok
                            Text(
                              '${data['lastName'] ?? ''} ${data['firstName'] ?? ''}'
                                  .trim(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF202122),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email ?? '',
                              style: const TextStyle(
                                color: Color(0xFF54595D),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Gombok egymás alatt
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => context.go('/change-password'),
                                icon: const Icon(Icons.password),
                                label: const Text('Jelszó megváltoztatása'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFB0D4F1),
                                    width: 1,
                                  ),
                                  foregroundColor: const Color(0xFF202122),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _confirmAndDelete(context),
                                icon: const Icon(Icons.delete_forever),
                                label: const Text('Fiók végleges törlése'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      // Nagy képernyőn vízszintes elrendezés
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${data['lastName'] ?? ''} ${data['firstName'] ?? ''}'
                                      .trim(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF202122),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user.email ?? '',
                                  style: const TextStyle(
                                    color: Color(0xFF54595D),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => context.go('/change-password'),
                                icon: const Icon(Icons.password),
                                label: const Text('Jelszó megváltoztatása'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFB0D4F1),
                                    width: 1,
                                  ),
                                  foregroundColor: const Color(0xFF202122),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _confirmAndDelete(context),
                                icon: const Icon(Icons.delete_forever),
                                label: const Text('Fiók végleges törlése'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Kétoszlopos elrendezés: Szállítási cím (bal) és Előfizetési állapot (jobb)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isSmallScreen = constraints.maxWidth < 1000;

                  if (isSmallScreen) {
                    // Kis képernyőn: egymás alatt
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Szállítási cím űrlap
                        ShippingAddressForm(
                          userData: data,
                          canEdit: _canEditShippingAddress(data),
                        ),
                        const SizedBox(height: 16),
                        // Fejlesztett előfizetési státusz kártya
                        EnhancedSubscriptionStatusCard(
                          userData: data,
                          onRenewPressed: () => context.go('/account'),
                        ),
                      ],
                    );
                  }

                  // Nagy képernyőn: kétoszlopos elrendezés
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Bal oldali oszlop: Szállítási cím
                        Expanded(
                          flex: 1,
                          child: ShippingAddressForm(
                            userData: data,
                            canEdit: _canEditShippingAddress(data),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Jobb oldali oszlop: Előfizetési állapot
                        Expanded(
                          flex: 1,
                          child: EnhancedSubscriptionStatusCard(
                            userData: data,
                            onRenewPressed: () => context.go('/account'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Megújítási gomb (csak havi) - teljes szélességű, kiemelt
              const SizedBox(
                width: double.infinity,
                child: SubscriptionRenewalButton(
                  showAsCard: false,
                ),
              ),

              const SizedBox(height: 20),

              // SimplePay logó (csak webes platformon - SimplePay követelmény)
              if (kIsWeb) ...[
                // Reszponzív méret mobil/tablet/desktop nézethez
                LayoutBuilder(
                  builder: (context, constraints) {
                    double logoWidth;
                    if (constraints.maxWidth < 600) {
                      // Mobile - nagyobb logó a részletek jobb láthatóságához
                      logoWidth = constraints.maxWidth *
                          0.9; // 90% a képernyő szélességének
                    } else if (constraints.maxWidth < 900) {
                      // Tablet - nagyobb logó
                      logoWidth = 450;
                    } else {
                      // Desktop - nagy logó a részletek jobb láthatóságához
                      logoWidth = 482; // teljes méret
                    }
                    return SimplePayLogo(
                      centered: true,
                      width: logoWidth,
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],

              // Fizetési előzmények
              WebPaymentHistory(
                userData: {...data, 'uid': user.uid},
                onRefresh: () {}, // StreamBuilder automatikusan frissít
              ),

              const SizedBox(height: 20),

              // Admin eszközök - Előfizetés lejárat vezérlő
              // Admin felhasználóknak és lomeduteszt@gmail.com felhasználónak látható
              if (isAdmin || user.email == 'lomeduteszt@gmail.com') ...[
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E6),
                    border: Border.all(
                      color: const Color(0xFFB0D4F1),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.admin_panel_settings,
                                color: Color(0xFFD97706), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Admin eszközök - Előfizetés lejárat vezérlő',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                fontSize: 15,
                                color: Color(0xFF202122),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (!mounted) return;

                                  // ScaffoldMessenger mentése az async művelet előtt
                                  final scaffoldMessenger =
                                      ScaffoldMessenger.maybeOf(context);
                                  if (scaffoldMessenger == null) return;

                                  final confirmed = await showDialog<bool>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (ctx) {
                                          return AlertDialog(
                                            title: const Text(
                                                'Lejárat előtti email teszt'),
                                            content: const Text(
                                                'Ez beállítja az előfizetést 3 napos lejáratra, hogy tesztelhessük a lejárat előtti email értesítéseket.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.of(ctx).pop(false);
                                                },
                                                child: const Text('Mégse'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(ctx).pop(true);
                                                },
                                                child: const Text('Beállítás'),
                                              ),
                                            ],
                                          );
                                        },
                                      ) ??
                                      false;
                                  if (!mounted || !confirmed) return;

                                  final now = DateTime.now();
                                  final expiry =
                                      now.add(const Duration(days: 3));
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .set(
                                      {
                                        'isSubscriptionActive': true,
                                        'subscriptionStatus': 'premium',
                                        'subscriptionEndDate':
                                            Timestamp.fromDate(expiry),
                                        'subscription': {
                                          'status': 'ACTIVE',
                                          'productId': 'test_web_monthly',
                                          'purchaseToken': 'test_expiry_3_days',
                                          'endTime': expiry.toIso8601String(),
                                          'lastUpdateTime':
                                              now.toIso8601String(),
                                          'source': 'test_simulation',
                                        },
                                        'lastPaymentDate':
                                            FieldValue.serverTimestamp(),
                                        'updatedAt':
                                            FieldValue.serverTimestamp(),
                                        // NE töröljük a lastReminder mezőt teszteléskor!
                                        // Csak új előfizetés esetén töröljük
                                      },
                                      SetOptions(merge: true),
                                    );

                                    if (!mounted) return;

                                    // Azonnal mutatjuk a sikeres üzenetet
                                    scaffoldMessenger.showSnackBar(const SnackBar(
                                        content: Text(
                                            'Előfizetés beállítva 3 napos lejáratra!')));

                                    // Email küldése (nem blokkoljuk, ha dispose-olódik)
                                    EmailNotificationService.sendTestEmail(
                                      testType: 'expiry_warning',
                                      daysLeft: 3,
                                    ).then((emailSent) {
                                      if (!mounted) return;
                                      scaffoldMessenger.showSnackBar(SnackBar(
                                          content: Text(emailSent
                                              ? 'Email elküldve!'
                                              : 'Email küldése sikertelen!')));
                                    }).catchError((e) {
                                      debugPrint('Email küldés hiba: $e');
                                    });
                                  } catch (e) {
                                    if (!mounted) return;
                                    scaffoldMessenger.showSnackBar(
                                        SnackBar(content: Text('Hiba: $e')));
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD97706),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                                child: const Text('3 napos lejárat'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (!mounted) return;

                                  // ScaffoldMessenger mentése az async művelet előtt
                                  final scaffoldMessenger =
                                      ScaffoldMessenger.maybeOf(context);
                                  if (scaffoldMessenger == null) return;

                                  final confirmed = await showDialog<bool>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (ctx) {
                                          return AlertDialog(
                                            title: const Text(
                                                'Lejárat utáni email teszt'),
                                            content: const Text(
                                                'Ez beállítja az előfizetést lejárt állapotra, hogy tesztelhessük a lejárat utáni email értesítéseket.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.of(ctx,
                                                          rootNavigator: true)
                                                      .pop(false);
                                                },
                                                child: const Text('Mégse'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(ctx,
                                                          rootNavigator: true)
                                                      .pop(true);
                                                },
                                                child: const Text('Beállítás'),
                                              ),
                                            ],
                                          );
                                        },
                                      ) ??
                                      false;
                                  if (!mounted || !confirmed) return;

                                  final now = DateTime.now();
                                  final expiredDate =
                                      now.subtract(const Duration(days: 1));
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .set(
                                      {
                                        'isSubscriptionActive': false,
                                        'subscriptionStatus': 'expired',
                                        'subscriptionEndDate':
                                            Timestamp.fromDate(expiredDate),
                                        'subscription': {
                                          'status': 'EXPIRED',
                                          'productId': 'test_web_monthly',
                                          'purchaseToken': 'test_expired',
                                          'endTime':
                                              expiredDate.toIso8601String(),
                                          'lastUpdateTime':
                                              now.toIso8601String(),
                                          'source': 'test_simulation',
                                        },
                                        'lastPaymentDate':
                                            FieldValue.serverTimestamp(),
                                        'updatedAt':
                                            FieldValue.serverTimestamp(),
                                        // NE töröljük a lastReminder mezőt teszteléskor!
                                        // Csak új előfizetés esetén töröljük
                                      },
                                      SetOptions(merge: true),
                                    );

                                    if (!mounted) return;

                                    // Azonnal mutatjuk a sikeres üzenetet
                                    scaffoldMessenger.showSnackBar(const SnackBar(
                                        content: Text(
                                            'Előfizetés beállítva lejárt állapotra!')));

                                    // Email küldése (nem blokkoljuk, ha dispose-olódik)
                                    EmailNotificationService.sendTestEmail(
                                      testType: 'expired',
                                    ).then((emailSent) {
                                      if (!mounted) return;
                                      scaffoldMessenger.showSnackBar(SnackBar(
                                          content: Text(emailSent
                                              ? 'Email elküldve!'
                                              : 'Email küldése sikertelen!')));
                                    }).catchError((e) {
                                      debugPrint('Email küldés hiba: $e');
                                    });
                                  } catch (e) {
                                    if (!mounted) return;
                                    scaffoldMessenger.showSnackBar(
                                        SnackBar(content: Text('Hiba: $e')));
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                                child: const Text('Lejárt állapot'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Reset gomb (csak adminnak)
              if (isAdmin || user.email == 'lomeduteszt@gmail.com') ...[
                ElevatedButton(
                  onPressed: () async {
                    if (!mounted) return;

                    // ScaffoldMessenger mentése az async művelet előtt
                    final scaffoldMessenger =
                        ScaffoldMessenger.maybeOf(context);
                    if (scaffoldMessenger == null) return;

                    final confirmed = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) {
                            return AlertDialog(
                              title: const Text('Teszt állapot visszaállítása'),
                              content: const Text(
                                  'Ez visszaállítja az előfizetést ingyenes állapotra.'),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(ctx, rootNavigator: true)
                                        .pop(false);
                                  },
                                  child: const Text('Mégse'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(ctx, rootNavigator: true)
                                        .pop(true);
                                  },
                                  child: const Text('Visszaállítás'),
                                ),
                              ],
                            );
                          },
                        ) ??
                        false;
                    if (!mounted || !confirmed) return;

                    try {
                      final now = DateTime.now();
                      final trialEnd = now.add(const Duration(days: 5));

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .set(
                        {
                          'isSubscriptionActive': false,
                          'subscriptionStatus': 'free',
                          'subscriptionEndDate': null,
                          'subscription': null,
                          'lastPaymentDate': null,
                          'freeTrialEndDate': Timestamp.fromDate(trialEnd),
                          'updatedAt': FieldValue.serverTimestamp(),
                          // Töröljük a lastReminder mezőt, hogy újra küldhessünk emailt
                          'lastReminder': FieldValue.delete(),
                        },
                        SetOptions(merge: true),
                      );
                      if (!mounted) return;
                      scaffoldMessenger.showSnackBar(const SnackBar(
                          content: Text(
                              'Előfizetés visszaállítva ingyenes állapotra! (5 napos próbaidőszak)')));
                    } catch (e) {
                      if (!mounted) return;
                      scaffoldMessenger
                          .showSnackBar(SnackBar(content: Text('Hiba: $e')));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: const Text('Reset (ingyenes állapot)'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Meghatározza, hogy szerkeszthető-e a szállítási cím form
  bool _canEditShippingAddress(Map<String, dynamic> data) {
    final isActive = data['isSubscriptionActive'] == true;
    final endDate = data['subscriptionEndDate'];

    if (!isActive) {
      return true; // Lejárt előfizetés → szerkeszthető
    }

    if (endDate != null) {
      DateTime? endDateTime;
      if (endDate is Timestamp) {
        endDateTime = endDate.toDate();
      } else if (endDate is String) {
        endDateTime = DateTime.tryParse(endDate);
      }

      if (endDateTime != null) {
        final daysUntilExpiry = endDateTime.difference(DateTime.now()).inDays;
        return daysUntilExpiry <= 3; // 3 napon belül lejár → szerkeszthető
      }
    }

    return false; // Aktív előfizetés → NEM szerkeszthető
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nincs bejelentkezett felhasználó.')),
      );
      return;
    }

    final passwordCtrl = TextEditingController();
    String? errorText;
    bool isLoading = false;
    bool obscure = true;

    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (ctx, setState) {
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
                        controller: passwordCtrl,
                        obscureText: obscure,
                        enabled: !isLoading,
                        decoration: InputDecoration(
                          labelText: 'Jelszó',
                          errorText: errorText,
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          isLoading ? null : () => Navigator.of(ctx).pop(false),
                      child: const Text('Mégse'),
                    ),
                    ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              setState(() {
                                isLoading = true;
                                errorText = null;
                              });
                              try {
                                await AccountDeletionService.deleteAccount(
                                  passwordCtrl.text,
                                );
                                if (context.mounted) {
                                  Navigator.of(ctx).pop(true);
                                }
                              } on FirebaseAuthException catch (e) {
                                String msg;
                                switch (e.code) {
                                  case 'wrong-password':
                                    msg = 'Hibás jelszó.';
                                    break;
                                  case 'requires-recent-login':
                                    msg =
                                        'A művelethez friss bejelentkezés szükséges.';
                                    break;
                                  default:
                                    msg =
                                        'Hitelesítési hiba: ${e.message ?? e.code}';
                                }
                                setState(() {
                                  errorText = msg;
                                  isLoading = false;
                                });
                              } catch (e) {
                                setState(() {
                                  errorText = 'Hiba történt: $e';
                                  isLoading = false;
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Végleges törlés'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    if (confirmed) {
      // A szolgáltatás kijelentkeztet; a router redirect a loginra visz.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fiók sikeresen törölve.')),
        );
        // Biztos átirányítás a loginra
        context.go('/login');
      }
    }
  }

  /// Sikeres fizetés dialóg (SimplePay 3.13.4 szerint)
  Future<void> _showPaymentSuccessDialog(
      BuildContext context, String? orderRef) async {
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

          // Ha még nincs számlaszám, várunk egy kicsit és újra próbáljuk (számla generálás aszinkron)
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
  Future<void> _showPaymentFailedDialog(
      BuildContext context, String? orderRef) async {
    // SimplePay transactionId lekérése KÖZVETLENÜL Firestore-ból
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
  void _showPaymentTimeoutDialog(BuildContext context) {
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
                  // Cím
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
                  // Tájékoztatás
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
                  // Biztosítás box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user,
                            color: Colors.green[700], size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Biztosítjuk: Nem történt pénzügyi terhelés.',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Gombok
                  Row(
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Megszakított fizetés dialóg (SimplePay 3.13.1 szerint - KÖTELEZŐ!)
  void _showPaymentCancelledDialog(BuildContext context) {
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
                  // Cím
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
                  // Tartalom
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
                  // Biztosítás box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user,
                            color: Colors.green[700], size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Biztosítjuk: Nem történt pénzügyi terhelés.',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Gombok
                  Row(
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
