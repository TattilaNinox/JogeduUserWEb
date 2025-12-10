import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Szállítási cím űrlap komponens az Account képernyőn
///
/// Ez a komponens a számlázáshoz szükséges szállítási adatokat kezeli.
/// Feltételesen szerkeszthető: csak akkor, ha az előfizetés lejárt vagy
/// 3 napon belül lejár, vagy admin felhasználó.
class ShippingAddressForm extends StatefulWidget {
  final Map<String, dynamic> userData;
  final bool canEdit;

  const ShippingAddressForm({
    super.key,
    required this.userData,
    required this.canEdit,
  });

  @override
  State<ShippingAddressForm> createState() => _ShippingAddressFormState();
}

class _ShippingAddressFormState extends State<ShippingAddressForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxNumberController = TextEditingController();

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isAdmin = false;
  bool _isGeneratingInvoice = false;
  bool _isCompany = false;

  // Irányítószám-település adatok
  Map<String, List<String>>? _postalCodes;
  bool _isLoadingPostalCodes = false;
  List<String>? _availableCities;

  @override
  void initState() {
    super.initState();
    _loadPostalCodes();
    _loadUserData();
    _zipCodeController.addListener(_onZipCodeChanged);
  }

  @override
  void didUpdateWidget(ShippingAddressForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ha a userData változott, frissítjük az adatokat
    if (oldWidget.userData['shippingAddress'] != widget.userData['shippingAddress']) {
      _loadUserData();
    }
  }

  @override
  void dispose() {
    _zipCodeController.removeListener(_onZipCodeChanged);
    _nameController.dispose();
    _zipCodeController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _taxNumberController.dispose();
    super.dispose();
  }

  /// Irányítószám adatbázis betöltése
  Future<void> _loadPostalCodes() async {
    try {
      setState(() {
        _isLoadingPostalCodes = true;
      });

      final String jsonString =
          await rootBundle.loadString('assets/postal_codes.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      _postalCodes = jsonData.map(
        (key, value) => MapEntry(
          key,
          List<String>.from(value as List),
        ),
      );

      if (mounted) {
        setState(() {
          _isLoadingPostalCodes = false;
        });
      }
    } catch (e) {
      debugPrint('Hiba az irányítószám adatok betöltésekor: $e');
      if (mounted) {
        setState(() {
          _isLoadingPostalCodes = false;
        });
      }
    }
  }

  /// Felhasználói adatok betöltése
  void _loadUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Admin ellenőrzés
    final isAdmin = widget.userData['isAdmin'] == true ||
        user.email == 'tattila.ninox@gmail.com';
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });
    }

    // Szállítási cím betöltése - TESZTELÉSHEZ KIKOMMENTEZVE
    // A form mindig üresen indul, hogy tesztelni lehessen
    /*
    final shippingAddress = widget.userData['shippingAddress'] as Map<String, dynamic>?;
    if (shippingAddress != null && shippingAddress.isNotEmpty) {
      _nameController.text = shippingAddress['name']?.toString() ?? '';
      _zipCodeController.text = shippingAddress['zipCode']?.toString() ?? '';
      _cityController.text = shippingAddress['city']?.toString() ?? '';
      _addressController.text = shippingAddress['address']?.toString() ?? '';
      _taxNumberController.text = shippingAddress['taxNumber']?.toString() ?? '';
      _isCompany = shippingAddress['isCompany']?.toString() == 'true';
    }
    */
    // A form mindig üresen marad teszteléshez
  }

  /// Irányítószám változás figyelése
  void _onZipCodeChanged() {
    if (!mounted) return;
    
    final zipCode = _zipCodeController.text.trim();

    // Csak akkor keresünk, ha pontosan 4 számjegy van
    if (zipCode.length == 4 && RegExp(r'^\d{4}$').hasMatch(zipCode)) {
      _lookupCity(zipCode);
    } else {
      // Ha nem 4 számjegy, eltávolítjuk a település mezőt és a dropdown-t
      if (_availableCities != null && mounted) {
        setState(() {
          _availableCities = null;
        });
      }
    }
  }

  /// Település keresés irányítószám alapján
  void _lookupCity(String zipCode) {
    if (!mounted || _postalCodes == null) return;

    final cities = _postalCodes![zipCode];

    if (!mounted) return;
    
    if (cities != null && cities.isNotEmpty) {
      if (cities.length == 1) {
        // Egy település: automatikusan kitöltjük
        if (mounted) {
          setState(() {
            _cityController.text = cities[0];
            _availableCities = null;
          });
        }
      } else {
        // Több település: lista megjelenítése
        if (mounted) {
          setState(() {
            _availableCities = cities;
            _cityController.clear(); // Töröljük, hogy válasszon
          });
        }
      }
    } else {
      // Nincs találat
      if (mounted) {
        setState(() {
          _availableCities = null;
        });
      }
    }
  }

  /// Település választó megjelenítése bottom sheet-ben
  Future<void> _showCitySelector() async {
    if (!mounted || _availableCities == null || _availableCities!.isEmpty) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                            '${_availableCities!.length} település található, válassz egyet:',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              itemCount: _availableCities!.length,
              itemBuilder: (context, index) {
                final city = _availableCities![index];
                return ListTile(
                  leading: const Icon(Icons.location_city),
                  title: Text(city),
                  onTap: () {
                    Navigator.of(context).pop(city);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _cityController.text = selected;
        _availableCities = null;
      });
    }
  }

  /// Szerkesztés indítása
  void _startEditing() {
    if (!mounted) return;
    
    // Ha a név mező üres, automatikusan kitöltjük a felhasználó adataiból
    if (_nameController.text.trim().isEmpty) {
      final firstName = widget.userData['firstName']?.toString() ?? '';
      final lastName = widget.userData['lastName']?.toString() ?? '';
      final displayName = widget.userData['displayName']?.toString() ?? '';
      
      String fullName = '';
      if (firstName.isNotEmpty && lastName.isNotEmpty) {
        fullName = '$lastName $firstName';
      } else if (displayName.isNotEmpty) {
        fullName = displayName;
      } else {
        final user = FirebaseAuth.instance.currentUser;
        if (user?.displayName != null && user!.displayName!.isNotEmpty) {
          fullName = user.displayName!;
        } else if (user?.email != null) {
          fullName = user!.email!.split('@')[0];
        }
      }
      
      if (fullName.isNotEmpty) {
        _nameController.text = fullName;
      }
    }
    
    if (mounted) {
      setState(() {
        _isEditing = true;
      });
    }
  }

  /// Szerkesztés megszakítása
  void _cancelEditing() {
    if (!mounted) return;
    
    // Mezők törlése és szerkesztés mód kilépése
    setState(() {
      _nameController.clear();
      _zipCodeController.clear();
      _cityController.clear();
      _addressController.clear();
      _taxNumberController.clear();
      _isCompany = false;
      _availableCities = null;
      _isEditing = false;
    });
  }

  /// Adatok mentése Firestore-ba
  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Szigorú ellenőrzés: minden kötelező mező ki kell legyen töltve
    final name = _nameController.text.trim();
    final zipCode = _zipCodeController.text.trim();
    final city = _cityController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty || zipCode.isEmpty || zipCode.length != 4 || city.isEmpty || address.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kérjük, töltsd ki az összes kötelező mezőt!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Cég esetén adószám kötelező
    if (_isCompany && _taxNumberController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Jogi személy esetén az adószám megadása kötelező!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSaving = true;
    });

    try {
      final addressData = {
        'name': name,
        'zipCode': zipCode,
        'city': city,
        'address': address,
        'isCompany': _isCompany.toString(),
        if (_taxNumberController.text.trim().isNotEmpty)
          'taxNumber': _taxNumberController.text.trim(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'shippingAddress': addressData,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Szállítási cím sikeresen mentve!'),
            backgroundColor: Colors.green,
          ),
        );
        
        setState(() {
          _isEditing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba történt: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Szállítási cím törlése
  Future<void> _deleteShippingAddress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Megerősítés
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Szállítási cím törlése'),
        content: const Text(
          'Biztosan törölni szeretnéd a mentett szállítási címet?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'shippingAddress': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Mezők törlése
      if (mounted) {
        setState(() {
          _nameController.clear();
          _zipCodeController.clear();
          _cityController.clear();
          _addressController.clear();
          _taxNumberController.clear();
          _isCompany = false;
          _availableCities = null;
          _isEditing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Szállítási cím sikeresen törölve!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Hiba a szállítási cím törlése során: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hiba történt a törlés során'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Admin teszt számla generálása
  Future<void> _generateTestInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isGeneratingInvoice = true;
    });

    try {
      final addressData = {
        'name': _nameController.text.trim(),
        'zipCode': _zipCodeController.text.trim(),
        'city': _cityController.text.trim(),
        'address': _addressController.text.trim(),
        'isCompany': _isCompany.toString(),
        if (_taxNumberController.text.trim().isNotEmpty)
          'taxNumber': _taxNumberController.text.trim(),
      };

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = functions.httpsCallable('generateInvoiceManually');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Szamla generalasa folyamatban...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final result = await callable.call({
        'shippingAddress': addressData,
        'planId': 'monthly_premium_prepaid',
        'amount': 4350,
      });

      final data = result.data as Map<String, dynamic>;

      if (mounted) {
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Szamla sikeresen generalva! Szamlaszam: ${data['invoiceNumber'] ?? 'N/A'}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hiba: ${data['error'] ?? 'Ismeretlen hiba'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Hiba a teszt számla generálásakor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba történt: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingInvoice = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.canEdit || _isAdmin;
    final isFormEditable = canEdit && _isEditing;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFB0D4F1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cím és szerkesztés gomb
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Color(0xFF1E3A8A),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Szállítási cím',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF202122),
                        ),
                      ),
                    ],
                  ),
                  if (canEdit && !_isEditing)
                    TextButton.icon(
                      onPressed: _startEditing,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Szerkesztes'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF202122),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Cég/Magánszemély választó (csak szerkesztés módban)
              if (_isEditing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Jogi személyként vásárolok',
                      style: TextStyle(fontSize: 14),
                    ),
                    value: _isCompany,
                    onChanged: isFormEditable
                        ? (value) {
                            setState(() {
                              _isCompany = value ?? false;
                              if (!_isCompany) {
                                _taxNumberController.clear();
                              }
                            });
                          }
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                ),

              // Név/Cégnév mező
              TextFormField(
                controller: _nameController,
                enabled: isFormEditable,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: _isCompany ? 'Cégnév *' : 'Név *',
                  prefixIcon: const Icon(Icons.person, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'A ${_isCompany ? "cégnév" : "név"} megadása kötelező';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 12),

              // Irányítószám és Település sor
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _zipCodeController,
                      enabled: isFormEditable,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Irányítószám *',
                        prefixIcon: const Icon(Icons.markunread_mailbox, size: 20),
                        suffixIcon: _isLoadingPostalCodes
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        isDense: true,
                        counterText: '',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      maxLength: 4,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Kötelező';
                        }
                        if (!RegExp(r'^\d{4}$').hasMatch(value.trim())) {
                          return '4 szamjegy';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _cityController,
                      enabled: isFormEditable && _availableCities == null,
                      readOnly: _availableCities != null,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Település *',
                        prefixIcon: const Icon(Icons.location_city, size: 20),
                        suffixIcon: _availableCities != null
                            ? IconButton(
                                icon: const Icon(Icons.arrow_drop_down, size: 20),
                                onPressed: isFormEditable
                                    ? _showCitySelector
                                    : null,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        isDense: true,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Kötelező';
                        }
                        return null;
                      },
                      onTap: _availableCities != null && isFormEditable
                          ? _showCitySelector
                          : null,
                    ),
                  ),
                ],
              ),

              // Választólista megjelenítése (ha több település van)
              if (_availableCities != null && _availableCities!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_availableCities!.length} telepules talalhato',
                            style: TextStyle(
                              color: Colors.blue[900],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (isFormEditable)
                          TextButton(
                            onPressed: _showCitySelector,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Valasztas',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // Utca, házszám mező
              TextFormField(
                controller: _addressController,
                enabled: isFormEditable,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Utca, házszám *',
                  prefixIcon: const Icon(Icons.home, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Kotelezo';
                  }
                  return null;
                },
              ),

              // Adószám mező (csak cég esetén vagy szerkesztés módban)
              if (_isCompany) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _taxNumberController,
                  enabled: isFormEditable,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: _isCompany ? 'Adószám *' : 'Adószám',
                    prefixIcon: const Icon(Icons.badge, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  validator: _isCompany
                      ? (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Jogi személy esetén az adószám megadása kötelező';
                          }
                          return null;
                        }
                      : null,
                ),
              ],

              const SizedBox(height: 16),

              // Gombok
              if (_isEditing)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () {
                        _formKey.currentState?.reset();
                        _cancelEditing();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Mégse', style: TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveAddress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Mentés', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),

              // Szállítási adatok törlése gomb - minden felhasználónak elérhető
              Builder(
                builder: (context) {
                  final shippingAddress = widget.userData['shippingAddress'] as Map<String, dynamic>?;
                  final hasShippingAddress = shippingAddress != null && shippingAddress.isNotEmpty;
                  
                  if (hasShippingAddress && !_isEditing) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ElevatedButton.icon(
                        onPressed: _deleteShippingAddress,
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text(
                          'Szállítási adatok törlése',
                          style: TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          minimumSize: const Size(double.infinity, 0),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Admin gombok
              if (_isAdmin && !_isEditing) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton.icon(
                    onPressed: _isGeneratingInvoice ? null : _generateTestInvoice,
                    icon: _isGeneratingInvoice
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.receipt, size: 18),
                    label: const Text(
                      'Teszt számla',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      minimumSize: const Size(double.infinity, 0),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

