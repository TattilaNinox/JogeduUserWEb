import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

/// Szállítási cím gyűjtő dialóg
///
/// A fizetés előtt megjelenik, hogy a felhasználó megadja a számlázási címet.
/// Ez a cím csak ideiglenesen tárolódik és a számla generálása után törlődik.
class ShippingAddressDialog {
  /// Megjeleníti a szállítási cím dialógot
  static Future<Map<String, String>?> show(BuildContext context) async {
    return await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ShippingAddressDialogContent(),
    );
  }
}

class _ShippingAddressDialogContent extends StatefulWidget {
  const _ShippingAddressDialogContent();

  @override
  State<_ShippingAddressDialogContent> createState() =>
      _ShippingAddressDialogContentState();
}

class _ShippingAddressDialogContentState
    extends State<_ShippingAddressDialogContent> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxNumberController = TextEditingController();

  bool _isLoading = false;
  bool _isCompany = false; // Magánszemély (false) vagy jogi személy (true)
  bool _isLoadingUserData = true;
  
  // Irányítószám-település adatok
  Map<String, List<String>>? _postalCodes;
  bool _isLoadingPostalCodes = false;
  List<String>? _availableCities; // Több település esetén

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadPostalCodes();
    // Irányítószám változás figyelése
    _zipCodeController.addListener(_onZipCodeChanged);
  }
  
  Future<void> _loadPostalCodes() async {
    try {
      setState(() {
        _isLoadingPostalCodes = true;
      });
      
      final String jsonString = await rootBundle.loadString('assets/postal_codes.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      
      // Konvertálás Map<String, List<String>> formátumba
      _postalCodes = jsonData.map((key, value) => 
        MapEntry(key, List<String>.from(value as List))
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
  
  void _onZipCodeChanged() {
    final zipCode = _zipCodeController.text.trim();
    
    // Csak akkor keresünk, ha pontosan 4 számjegy van
    if (zipCode.length == 4 && RegExp(r'^\d{4}$').hasMatch(zipCode)) {
      _lookupCity(zipCode);
    } else {
      // Ha nem 4 számjegy, eltávolítjuk a település mezőt és a dropdown-t
      if (_availableCities != null) {
        setState(() {
          _availableCities = null;
        });
      }
    }
  }
  
  void _lookupCity(String zipCode) {
    if (_postalCodes == null) return;
    
    final cities = _postalCodes![zipCode];
    
    if (cities != null && cities.isNotEmpty) {
      if (cities.length == 1) {
        // Egy település: automatikusan kitöltjük
        setState(() {
          _cityController.text = cities[0];
          _availableCities = null;
        });
      } else {
        // Több település: lista megjelenítése
        setState(() {
          _availableCities = cities;
          _cityController.clear(); // Töröljük a település mezőt, hogy válasszon
        });
      }
    } else {
      // Nincs találat
      setState(() {
        _availableCities = null;
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists && mounted) {
          final userData = userDoc.data();
          final firstName = userData?['firstName']?.toString() ?? '';
          final lastName = userData?['lastName']?.toString() ?? '';
          final displayName = userData?['displayName']?.toString() ?? '';
          
          // Név összeállítása: lastName firstName vagy displayName vagy email
          String fullName = '';
          if (firstName.isNotEmpty && lastName.isNotEmpty) {
            fullName = '$lastName $firstName';
          } else if (displayName.isNotEmpty) {
            fullName = displayName;
          } else if (user.displayName != null && user.displayName!.isNotEmpty) {
            fullName = user.displayName!;
          } else if (user.email != null) {
            fullName = user.email!.split('@')[0];
          }
          
          if (fullName.isNotEmpty && mounted) {
            _nameController.text = fullName;
          }
        }
      }
    } catch (e) {
      debugPrint('Hiba a felhasználó adatok betöltésekor: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
        });
      }
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

  Future<void> _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
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

        // Teszteléshez: számla generálása közvetlenül
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // Ellenőrizzük, hogy admin felhasználó-e
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          
          final userData = userDoc.data();
          final isAdmin = userData?['isAdmin'] == true || 
                         user.email == 'tattila.ninox@gmail.com';
          
          if (isAdmin) {
            // Admin felhasználó: számla generálása teszteléshez
            try {
              final functions = FirebaseFunctions.instanceFor(
                  region: 'europe-west1');
              final callable =
                  functions.httpsCallable('generateInvoiceManually');

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Számla generálása folyamatban...'),
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
                Navigator.of(context).pop(null); // Bezárjuk a dialógot
                
                if (data['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Számla sikeresen generálva! Számlaszám: ${data['invoiceNumber'] ?? 'N/A'}',
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Hiba: ${data['error'] ?? 'Ismeretlen hiba'}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
              return;
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Hiba történt: $e'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
              return;
            }
          }
        }

        // Nem admin felhasználó vagy hiba esetén: visszaadjuk az adatokat (normál folyamat)
        if (mounted) {
          Navigator.of(context).pop(addressData);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Címsor
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFF1E3A8A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Szállítási adatok megadása',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A számla kiállításához szükséges',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Információs szöveg
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ez az adat csak ideiglenesen tárolódik és a számla generálása után törlődik.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Jogi személy checkbox
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isCompany ? const Color(0xFF1E3A8A) : Colors.grey[300]!,
                    width: _isCompany ? 2 : 1,
                  ),
                ),
                child: CheckboxListTile(
                  title: const Text(
                    'Jogi személyként vásárolok',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _isCompany
                        ? 'Cégnév és adószám megadása kötelező'
                        : 'Magánszemélyként vásárolok',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  value: _isCompany,
                  onChanged: (value) {
                    setState(() {
                      _isCompany = value ?? false;
                      if (!_isCompany) {
                        _taxNumberController.clear();
                      }
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              ),
              const SizedBox(height: 20),
              
              // Név mező
              if (_isLoadingUserData)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                TextFormField(
                  controller: _nameController,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: _isCompany ? 'Cégnév *' : 'Név *',
                    hintText: _isCompany ? 'Kovács Bt.' : 'Kovács János',
                    prefixIcon: Icon(
                      _isCompany ? Icons.business : Icons.person,
                      color: Colors.grey[600],
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'A ${_isCompany ? "cégnév" : "név"} megadása kötelező';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 16),
              
              // Irányítószám és Település sorban
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Stack(
                      children: [
                        TextFormField(
                          controller: _zipCodeController,
                          enabled: !_isLoading,
                          maxLength: 4,
                          decoration: InputDecoration(
                            labelText: 'Irányítószám *',
                            hintText: '2030',
                            prefixIcon: Icon(Icons.pin, color: Colors.grey[600]),
                            suffixIcon: _isLoadingPostalCodes
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.red, width: 2),
                            ),
                            counterText: '', // Elrejtjük a karakter számlálót
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Kötelező';
                            }
                            if (!RegExp(r'^\d{4}$').hasMatch(value.trim())) {
                              return '4 számjegy';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Stack(
                      children: [
                        TextFormField(
                          controller: _cityController,
                          enabled: !_isLoading && _availableCities == null, // Le van tiltva, ha több település van
                          readOnly: _availableCities != null, // Csak olvasható, ha több település van
                          decoration: InputDecoration(
                            labelText: 'Település *',
                            hintText: _availableCities != null 
                                ? 'Válassz települést' 
                                : 'Érd',
                            prefixIcon: Icon(Icons.location_city, color: Colors.grey[600]),
                            suffixIcon: _availableCities != null
                                ? Icon(Icons.arrow_drop_down, color: Colors.grey[600])
                                : null,
                            filled: true,
                            fillColor: _availableCities != null 
                                ? Colors.blue[50] 
                                : Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.red, width: 2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Kötelező';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Település lista, ha több település van
              if (_availableCities != null && _availableCities!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Text(
                              '${_availableCities!.length} település található, válassz egyet:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _availableCities!.length,
                          itemBuilder: (context, index) {
                            final city = _availableCities![index];
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _cityController.text = city;
                                  _availableCities = null;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(Icons.location_city, size: 18, color: Colors.grey[600]),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        city,
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              
              // Utca, házszám
              TextFormField(
                controller: _addressController,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: 'Utca, házszám *',
                  hintText: 'Tárnoki út 23.',
                  prefixIcon: Icon(Icons.home, color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'A cím megadása kötelező';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Adószám
              TextFormField(
                controller: _taxNumberController,
                enabled: !_isLoading && _isCompany,
                decoration: InputDecoration(
                  labelText: _isCompany ? 'Adószám *' : 'Adószám (opcionális)',
                  hintText: '12345678-1-23',
                  prefixIcon: Icon(Icons.badge, color: Colors.grey[600]),
                  filled: true,
                  fillColor: _isCompany ? Colors.grey[50] : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
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
              const SizedBox(height: 24),
              
              // Gombok
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text(
                      'Mégse',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Folytatás',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

