import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/sidebar.dart';
import '../services/admin_service.dart';
import '../services/web_payment_service.dart';
import '../widgets/admin/user_list_tile.dart';
import '../widgets/admin/user_action_service.dart';

enum UserFilter { all, premium, trial, test, free, expired }

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  UserFilter _selectedFilter = UserFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // science filter
  List<String> _sciences = [];
  String? _selectedScience;

  // Kijelölt felhasználók tömeges műveletekhez
  final Set<String> _selectedUsers = {};
  bool _isSelectModeActive = false;

  @override
  void initState() {
    super.initState();
    _loadSciences();
  }

  Future<void> _loadSciences() async {
    final snap = await FirebaseFirestore.instance.collection('sciences').get();
    final sciences =
        snap.docs.map((d) => (d['name'] as String? ?? '')).toList();
    sciences.sort();
    sciences.insert(0, 'Összes');
    setState(() {
      _sciences = sciences;
      // ensure default selection is 'Összes' (null = all)
      _selectedScience ??= 'Összes';
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _testPayment() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nincs bejelentkezett felhasználó')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fizetés indítása...')),
      );

      final result = await WebPaymentService.initiatePaymentViaCloudFunction(
        planId: 'monthly_premium_prepaid',
        userId: user.uid,
      );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (result.success && result.paymentUrl != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Sikeres! Payment URL: ${result.paymentUrl}')),
        );
        // Itt megnyithatnád a payment URL-t egy új ablakban
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('Hiba: ${result.error ?? 'Ismeretlen hiba'}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hiba: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectModeActive
            ? 'Felhasználók (${_selectedUsers.length} kijelölve)'
            : 'Felhasználók'),
        actions: [
          if (_isSelectModeActive) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Összes kijelölése',
              onPressed: _selectAllVisibleUsers,
            ),
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Kijelölés törlése',
              onPressed: () {
                setState(() {
                  _selectedUsers.clear();
                });
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: _handleBulkAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'bulk_reset',
                  enabled: _selectedUsers.isNotEmpty,
                  child:
                      Text('Alaphelyzetbe állítás (${_selectedUsers.length})'),
                ),
                PopupMenuItem(
                  value: 'bulk_token_cleanup',
                  enabled: _selectedUsers.isNotEmpty,
                  child: Text('Token cleanup (${_selectedUsers.length})'),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Kijelölés mód kilépés',
              onPressed: () {
                setState(() {
                  _isSelectModeActive = false;
                  _selectedUsers.clear();
                });
              },
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: 'Tömeges kijelölés mód',
              onPressed: () {
                setState(() {
                  _isSelectModeActive = true;
                });
              },
            ),
        ],
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'users'),
          Expanded(
            child: Column(
              children: [
                _buildStatsSection(),
                const Divider(),
                Expanded(
                  child: _buildUsersList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // science dropdown filter
          Row(
            children: [
              const Text('Tudomány:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedScience,
                hint: const Text('Összes'),
                items: _sciences
                    .map((s) =>
                        DropdownMenuItem<String>(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedScience = val),
              ),
              const Spacer(),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration:
                      const InputDecoration(labelText: 'Keresés név/email'),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              )
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }

              var docs = snapshot.data!.docs;
              if (_searchQuery.isNotEmpty) {
                final filtered = docs.where((d) {
                  final data = (d.data() as Map<String, dynamic>? ?? {});
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  return email.contains(_searchQuery.toLowerCase()) ||
                      name.contains(_searchQuery.toLowerCase());
                }).toList();
                docs = filtered;
              }

              final totalUsers = docs.length;

              int premiumUsers = 0;
              int trialUsers = 0;
              int testUsers = 0;
              int freeUsers = 0;
              int expiredUsers = 0;

              for (final doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final subscriptionStatus =
                    data['subscriptionStatus'] as String? ?? 'free';
                final userType = data['userType'] as String? ?? 'normal';
                final trialEndDate = data['trialEndDate'] as Timestamp?;
                final isSubscriptionActive =
                    data['isSubscriptionActive'] as bool? ?? false;

                final freeTrialEndDate = data['freeTrialEndDate'] as Timestamp?;

                if (userType == 'test') {
                  testUsers++;
                } else if (isSubscriptionActive &&
                    subscriptionStatus == 'premium') {
                  premiumUsers++;
                } else if (subscriptionStatus == 'expired' ||
                    (!isSubscriptionActive &&
                        subscriptionStatus == 'premium')) {
                  expiredUsers++;
                } else if ((freeTrialEndDate != null &&
                        DateTime.now().isBefore(freeTrialEndDate.toDate())) ||
                    (trialEndDate != null &&
                        DateTime.now().isBefore(trialEndDate.toDate()))) {
                  trialUsers++;
                } else {
                  freeUsers++;
                }
              }

              return Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Összes felhasználó',
                      totalUsers.toString(),
                      Colors.blue,
                      UserFilter.all,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Premium',
                      premiumUsers.toString(),
                      Colors.green,
                      UserFilter.premium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Próbaidő',
                      trialUsers.toString(),
                      Colors.purple,
                      UserFilter.trial,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Teszt',
                      testUsers.toString(),
                      Colors.orange,
                      UserFilter.test,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Lejárt',
                      expiredUsers.toString(),
                      Colors.red,
                      UserFilter.expired,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Ingyenes',
                      freeUsers.toString(),
                      Colors.grey,
                      UserFilter.free,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, Color color, UserFilter filter) {
    final bool selected = _selectedFilter == filter;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minHeight: 80, maxHeight: 80),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersList() {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('users');
    if (_selectedScience != null && _selectedScience != 'Összes') {
      query = query.where('science', isEqualTo: _selectedScience);
    }

    return StreamBuilder<QuerySnapshot>(
      // Nem használunk Firestore oldali rendezést, mert sok
      // felhasználónál hiányzik a 'createdAt' mező. Helyette
      // kliens oldalon rendezzük, így minden dokumentum látható.
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Hiba: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('Nincsenek felhasználók'),
          );
        }

        List<QueryDocumentSnapshot> users = snapshot.data!.docs;

        // Kliens oldali rendezés 'createdAt' szerint (hiányzó érték kezelése)
        users.sort((a, b) {
          final aTs =
              (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final bTs =
              (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final aDt = aTs?.toDate();
          final bDt = bTs?.toDate();
          if (aDt == null && bDt == null) return 0;
          if (aDt == null) return 1; // null értékek a lista végére
          if (bDt == null) return -1;
          return bDt.compareTo(aDt); // csökkenő sorrend
        });

        users = users.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final subscriptionStatus =
              data['subscriptionStatus'] as String? ?? 'free';
          final userType = data['userType'] as String? ?? 'normal';
          final trialEndDate = data['trialEndDate'] as Timestamp?;
          final isSubscriptionActive =
              data['isSubscriptionActive'] as bool? ?? false;
          final freeTrialEndDate = data['freeTrialEndDate'] as Timestamp?;

          switch (_selectedFilter) {
            case UserFilter.premium:
              return isSubscriptionActive && subscriptionStatus == 'premium';
            case UserFilter.trial:
              return (trialEndDate != null &&
                      DateTime.now().isBefore(trialEndDate.toDate())) ||
                  (freeTrialEndDate != null &&
                      DateTime.now().isBefore(freeTrialEndDate.toDate()));
            case UserFilter.test:
              return userType == 'test';
            case UserFilter.expired:
              return subscriptionStatus == 'expired' ||
                  (!isSubscriptionActive && subscriptionStatus == 'premium');
            case UserFilter.free:
              return !isSubscriptionActive &&
                  subscriptionStatus == 'free' &&
                  (trialEndDate == null ||
                      DateTime.now().isAfter(trialEndDate.toDate())) &&
                  userType != 'test';
            case UserFilter.all:
              return true;
          }
        }).toList();

        if (_searchQuery.isNotEmpty) {
          users = users.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final email = data['email'] as String? ?? '';
            return email.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Felhasználók',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _testPayment,
                        icon: const Icon(Icons.payment),
                        label: const Text('Teszt Fizetés'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Keresés e-mail alapján',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: () {
                          setState(() {
                            _searchQuery = _searchController.text;
                          });
                        },
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Találatok: ${users.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final doc = users[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return UserListTile(
                    doc: doc,
                    isSelectModeActive: _isSelectModeActive,
                    isSelected: _selectedUsers.contains(doc.id),
                    onCheckboxChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedUsers.add(doc.id);
                        } else {
                          _selectedUsers.remove(doc.id);
                        }
                      });
                    },
                    onMenuSelected: (action) async {
                      final result = await UserActionService.handleUserAction(
                        context,
                        userId: doc.id,
                        action: action,
                        userData: data,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result['message']),
                            backgroundColor:
                                result['success'] ? Colors.green : Colors.red,
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Összes látható felhasználó kijelölése
  void _selectAllVisibleUsers() {
    // Újra lekérdezzük a látható felhasználókat ugyanazzal a szűrési logikával
    FirebaseFirestore.instance.collection('users').get().then((snapshot) {
      List<QueryDocumentSnapshot> users = snapshot.docs;

      // Ugyanazok a szűrési kritériumok, mint a _buildUsersList-ben
      if (_selectedScience != null && _selectedScience != 'Összes') {
        users = users.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['science'] == _selectedScience;
        }).toList();
      }

      users = users.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final subscriptionStatus =
            data['subscriptionStatus'] as String? ?? 'free';
        final userType = data['userType'] as String? ?? 'normal';
        final trialEndDate = data['trialEndDate'] as Timestamp?;
        final isSubscriptionActive =
            data['isSubscriptionActive'] as bool? ?? false;

        switch (_selectedFilter) {
          case UserFilter.premium:
            return isSubscriptionActive && subscriptionStatus == 'premium';
          case UserFilter.trial:
            return trialEndDate != null &&
                DateTime.now().isBefore(trialEndDate.toDate());
          case UserFilter.test:
            return userType == 'test';
          case UserFilter.expired:
            return subscriptionStatus == 'expired' ||
                (!isSubscriptionActive && subscriptionStatus == 'premium');
          case UserFilter.free:
            return !isSubscriptionActive &&
                subscriptionStatus == 'free' &&
                (trialEndDate == null ||
                    DateTime.now().isAfter(trialEndDate.toDate())) &&
                userType != 'test';
          case UserFilter.all:
            return true;
        }
      }).toList();

      if (_searchQuery.isNotEmpty) {
        users = users.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final email = data['email'] as String? ?? '';
          return email.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();
      }

      setState(() {
        _selectedUsers.clear();
        _selectedUsers.addAll(users.map((doc) => doc.id));
      });
    });
  }

  /// Tömeges műveletek kezelése
  Future<void> _handleBulkAction(String action) async {
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nincs kijelölt felhasználó')),
      );
      return;
    }

    bool confirmed = false;

    switch (action) {
      case 'bulk_reset':
        confirmed = await UserActionService.showConfirmDialog(
              context,
              title: 'Tömeges alaphelyzetbe állítás',
              content:
                  'Biztosan alaphelyzetbe állítod a kijelölt ${_selectedUsers.length} felhasználót?\n\n'
                  '• Előfizetés: FREE-re állítás\n'
                  '• Próbaidőszak: 5 napos újraindítás\n'
                  '• Token cleanup: Google Play tokenek törlése\n'
                  '• Subscription: REFUNDED státuszra\n\n'
                  'Ez a művelet nem vonható vissza!',
            ) ??
            false;
        break;

      case 'bulk_token_cleanup':
        confirmed = await UserActionService.showConfirmDialog(
              context,
              title: 'Tömeges token cleanup',
              content:
                  'Törlöd az összes Google Play token-t a kijelölt ${_selectedUsers.length} felhasználónál?\n\n'
                  'Ez megszakítja az aktív előfizetés-ellenőrzési folyamatokat.',
            ) ??
            false;
        break;
    }

    if (confirmed) {
      // Betöltő dialógus megjelenítése
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Feldolgozás...'),
            ],
          ),
        ),
      );

      Map<String, dynamic> result = {};

      switch (action) {
        case 'bulk_reset':
          result =
              await AdminService.resetMultipleUsers(_selectedUsers.toList());
          break;
        case 'bulk_token_cleanup':
          // Egyszerre hívjuk meg a token cleanup-ot minden felhasználóra
          int successCount = 0;
          for (final userId in _selectedUsers) {
            final individualResult =
                await AdminService.cleanupUserTokens(userId);
            if (individualResult['success']) successCount++;
          }
          result = {
            'success': successCount == _selectedUsers.length,
            'message':
                '$successCount/${_selectedUsers.length} token cleanup sikeres',
          };
          break;
      }

      // Betöltő dialógus bezárása
      if (mounted) Navigator.of(context).pop();

      // Eredmény megjelenítése
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Művelet befejezve'),
            backgroundColor: result['success'] ? Colors.green : Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );

        // Kijelölés mód kikapcsolása sikeres művelet után
        if (result['success']) {
          setState(() {
            _isSelectModeActive = false;
            _selectedUsers.clear();
          });
        }
      }
    }
  }
}
