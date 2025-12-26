import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../core/firebase_config.dart';

/// Köteg szerkesztő képernyő.
///
/// Új köteg létrehozása vagy meglévő szerkesztése.
/// Három típus szerinti csoportosított szekció:
/// - Jegyzetek (notes)
/// - Memóriapalota állomások (memoriapalota_allomasok)
/// - Dialógus fájlok (dialogus_fajlok)
class UserBundleEditScreen extends StatefulWidget {
  final String? bundleId;

  const UserBundleEditScreen({super.key, this.bundleId});

  @override
  State<UserBundleEditScreen> createState() => _UserBundleEditScreenState();
}

class _UserBundleEditScreenState extends State<UserBundleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<String> _noteIds = [];
  List<String> _allomasIds = [];
  List<String> _dialogusIds = [];

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadBundle();
  }

  @override
  void didUpdateWidget(UserBundleEditScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ha a bundleId megváltozott, újratöltjük az adatokat
    if (oldWidget.bundleId != widget.bundleId) {
      _loadBundle();
    }
  }

  Future<void> _loadBundle() async {
    if (widget.bundleId != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .collection('bundles')
          .doc(widget.bundleId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _nameController.text = data['name'] ?? '';
        _descriptionController.text = data['description'] ?? '';
        _noteIds = List<String>.from(data['noteIds'] ?? []);
        _allomasIds = List<String>.from(data['allomasIds'] ?? []);
        _dialogusIds = List<String>.from(data['dialogusIds'] ?? []);
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveBundle() async {
    if (!_formKey.currentState!.validate()) return;

    final totalDocs =
        _noteIds.length + _allomasIds.length + _dialogusIds.length;
    if (totalDocs == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Legalább egy dokumentumot hozzá kell adni!'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Nincs bejelentkezett felhasználó');

      final bundleData = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'noteIds': _noteIds,
        'allomasIds': _allomasIds,
        'dialogusIds': _dialogusIds,
        'modified': FieldValue.serverTimestamp(),
      };

      if (widget.bundleId == null) {
        // Új köteg létrehozása
        bundleData['created'] =
            FieldValue.serverTimestamp(); // Megtartjuk a létrehozás idejét is
        await FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .add(bundleData);
      } else {
        // Meglévő köteg frissítése
        await FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .doc(widget.bundleId)
            .update(bundleData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.bundleId == null
                  ? 'Köteg sikeresen létrehozva!'
                  : 'Köteg sikeresen frissítve!',
            ),
          ),
        );
        context.go('/my-bundles');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba történt: $e')),
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

  Future<void> _deleteBundle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Köteg törlése'),
        content: const Text(
            'Biztosan törölni szeretnéd ezt a köteget? Ez a művelet nem vonható vissza.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _isSaving = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        await FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .doc(widget.bundleId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Köteg sikeresen törölve')),
          );
          context.go('/my-bundles');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hiba a törlés során: $e')),
          );
          setState(() {
            _isSaving = false;
          });
        }
      }
    }
  }

  void _addDocuments(String type) {
    // Teljes képernyős navigáció minden platformon (mobil + desktop)
    final bundleId = widget.bundleId ?? 'create';
    context.go('/my-bundles/edit/$bundleId/add-$type');
  }

  Future<void> _removeDocument(String id, String type) async {
    setState(() {
      if (type == 'notes') {
        _noteIds.remove(id);
      } else if (type == 'allomasok') {
        _allomasIds.remove(id);
      } else if (type == 'dialogus') {
        _dialogusIds.remove(id);
      }
    });

    // Ha szerkesztés módban vagyunk, azonnal mentsük a törlést a Firestore-ba is,
    // különben a DocumentSelectionScreen-ről visszatérve (ami az adatbázisból tölt)
    // újra megjelennének a törölt elemek.
    if (widget.bundleId != null) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        await FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bundles')
            .doc(widget.bundleId)
            .update({
          'noteIds': _noteIds,
          'allomasIds': _allomasIds,
          'dialogusIds': _dialogusIds,
          'modified': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Hiba az elem törlésekor: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Betöltés...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.bundleId == null ? 'Új köteg' : 'Köteg szerkesztése'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/my-bundles'),
        ),
        actions: [
          if (widget.bundleId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _isSaving ? null : _deleteBundle,
              tooltip: 'Köteg törlése',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alapadatok
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                  side: BorderSide(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .primaryColor
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Icon(
                              Icons.edit_note,
                              color: Theme.of(context).primaryColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Alapadatok',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Köteg neve',
                          hintText: 'Pl. Polgári jog vizsga',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'A név megadása kötelező';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: 'Leírás (opcionális)',
                          hintText: 'Rövid leírás a kötegről',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Jegyzetek szekció
              _buildDocumentSection(
                title: 'Tanulókártyák és kvíz kérdések',
                icon: Icons.school,
                count: _noteIds.length,
                type: 'notes',
                ids: _noteIds,
              ),
              const SizedBox(height: 12),

              // Állomások szekció
              _buildDocumentSection(
                title: 'Memóriapalota állomások',
                icon: Icons.route,
                count: _allomasIds.length,
                type: 'allomasok',
                ids: _allomasIds,
              ),
              const SizedBox(height: 12),

              // Dialógusok szekció
              _buildDocumentSection(
                title: 'Dialógus fájlok',
                icon: Icons.headset,
                count: _dialogusIds.length,
                type: 'dialogus',
                ids: _dialogusIds,
              ),
              const SizedBox(height: 24),

              // Mentés gombok - reszponzív elrendezés
              LayoutBuilder(
                builder: (context, constraints) {
                  final isSmallScreen = constraints.maxWidth < 600;

                  if (isSmallScreen) {
                    // Mobil: függőleges elrendezés, teljes szélesség
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          onPressed: _isSaving ? null : _saveBundle,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Text(widget.bundleId == null
                                  ? 'Létrehozás'
                                  : 'Mentés'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => context.go('/my-bundles'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          child: const Text('Mégse'),
                        ),
                      ],
                    );
                  } else {
                    // Desktop: vízszintes elrendezés
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isSaving
                              ? null
                              : () => context.go('/my-bundles'),
                          child: const Text('Mégse'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: _isSaving ? null : _saveBundle,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Text(widget.bundleId == null
                                  ? 'Létrehozás'
                                  : 'Mentés'),
                        ),
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentSection({
    required String title,
    required IconData icon,
    required int count,
    required String type,
    required List<String> ids,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$count elem',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _addDocuments(type),
                  icon: const Icon(Icons.add, size: 16),
                  label:
                      const Text('Hozzáadás', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),

            // Dokumentumok listája
            if (ids.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...ids.map((id) => _buildDocumentListTile(id, icon, type)),
            ] else ...[
              const SizedBox(height: 12),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        size: 32,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Még nincs hozzáadva',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentListTile(
      String id, IconData defaultIcon, String sectionType) {
    // Kollekció név meghatározása
    String collectionName;
    if (sectionType == 'notes') {
      collectionName = 'notes';
    } else if (sectionType == 'allomasok') {
      collectionName = 'memoriapalota_allomasok';
    } else {
      collectionName = 'dialogus_fajlok';
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseConfig.firestore.collection(collectionName).doc(id).get(),
      builder: (context, snapshot) {
        String title = id; // Alapértelmezett: ID
        IconData itemIcon = defaultIcon;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            // Több mezőt is ellenőrzünk a cím megtalálásához
            title = data['title'] ??
                data['name'] ??
                data['utvonalNev'] ??
                data['cím'] ??
                id;

            // Ikon meghatározása típus alapján (csak jegyzetek esetén)
            if (sectionType == 'notes') {
              final type = data['type'] as String?;
              switch (type) {
                case 'deck':
                  itemIcon = Icons.style;
                  break;
                case 'interactive':
                  itemIcon = Icons.touch_app;
                  break;
                case 'dynamic_quiz':
                case 'dynamic_quiz_dual':
                  itemIcon = Icons.quiz;
                  break;
                case 'jogeset':
                  itemIcon = Icons.gavel;
                  break;
                default:
                  itemIcon = Icons.description;
              }
            } else if (sectionType == 'allomasok') {
              itemIcon = Icons.train;
            } else if (sectionType == 'dialogus') {
              itemIcon = Icons.mic;
            }
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Icon(
                  itemIcon,
                  size: 16,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                onPressed: () => _removeDocument(id, sectionType),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
