import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../core/firebase_config.dart';
import '../utils/filter_storage.dart';
import '../widgets/mini_audio_player.dart';

/// Köteg megtekintő képernyő.
///
/// Egyszerű lista nézetben jeleníti meg a köteg tartalmát,
/// típusonként csoportosítva expandable szekciókban.
class UserBundleViewScreen extends StatefulWidget {
  final String bundleId;

  const UserBundleViewScreen({super.key, required this.bundleId});

  @override
  State<UserBundleViewScreen> createState() => _UserBundleViewScreenState();
}

class _UserBundleViewScreenState extends State<UserBundleViewScreen> {
  Map<String, dynamic>? _bundleData;
  bool _isLoading = true;

  // Szűréshez szükséges állapot
  Map<String, String> _docTypes = {}; // id -> type
  Set<String> _availableTypes = {};
  String _selectedType = 'all';

  @override
  void initState() {
    super.initState();
    _loadBundle();
  }

  Future<void> _loadBundle() async {
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
      final noteIds = List<String>.from(data['noteIds'] ?? []);
      final allomasIds = List<String>.from(data['allomasIds'] ?? []);
      final dialogusIds = List<String>.from(data['dialogusIds'] ?? []);

      Map<String, String> docTypes = {};
      Set<String> availableTypes = {};

      // Előtöltjük a típusokat a szűréshez
      // Jegyzetek, kvízek, kártyák
      for (String id in noteIds) {
        final d =
            await FirebaseConfig.firestore.collection('notes').doc(id).get();
        if (d.exists) {
          final type = d.data()?['type'] as String? ?? 'standard';
          docTypes[id] = type;
          availableTypes.add(type);
        }
      }

      // Memóriapalota állomások
      for (String id in allomasIds) {
        docTypes[id] = 'mp';
        availableTypes.add('mp');
      }

      // Dialógusok
      for (String id in dialogusIds) {
        docTypes[id] = 'dialogue';
        availableTypes.add('dialogue');
      }

      if (mounted) {
        setState(() {
          _bundleData = data;
          _docTypes = docTypes;
          _availableTypes = availableTypes;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Köteg nem található')),
        );
        context.go('/my-bundles');
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

    if (_bundleData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hiba')),
        body: const Center(child: Text('Köteg nem található')),
      );
    }

    final String name = _bundleData!['name'] ?? 'Névtelen köteg';
    final String description = _bundleData!['description'] ?? '';
    final List<String> allNoteIds =
        List<String>.from(_bundleData!['noteIds'] ?? []);
    final List<String> allAllomasIds =
        List<String>.from(_bundleData!['allomasIds'] ?? []);
    final List<String> allDialogusIds =
        List<String>.from(_bundleData!['dialogusIds'] ?? []);

    // Típusok leképezése magyar névre
    final Map<String, String> typeLabels = {
      'all': 'Összes típus',
      'standard': 'Jegyzet',
      'deck': 'Tanulókártya',
      'dynamic_quiz': 'Kvíz',
      'dynamic_quiz_dual': 'Páros kvíz',
      'interactive': 'Interaktív',
      'jogeset': 'Jogeset',
      'mp': 'Memóriapalota',
      'dialogue': 'Dialógus',
    };

    // Lista szűrése
    final filteredNoteIds = allNoteIds.where((id) {
      if (_selectedType == 'all') return true;
      return _docTypes[id] == _selectedType;
    }).toList();

    final filteredAllomasIds = allAllomasIds.where((id) {
      if (_selectedType == 'all') return true;
      return _docTypes[id] == _selectedType;
    }).toList();

    final filteredDialogusIds = allDialogusIds.where((id) {
      if (_selectedType == 'all') return true;
      return _docTypes[id] == _selectedType;
    }).toList();

    final bool isEmpty = filteredNoteIds.isEmpty &&
        filteredAllomasIds.isEmpty &&
        filteredDialogusIds.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/my-bundles'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.go('/my-bundles/edit/${widget.bundleId}'),
            tooltip: 'Szerkesztés',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Leírás
          if (description.isNotEmpty) ...[
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Típusszűrő
          if (_availableTypes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Szűrés:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedType,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF2C3E50),
                            fontWeight: FontWeight.w500,
                          ),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedType = newValue;
                              });
                            }
                          },
                          items: [
                            const DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('Összes típus'),
                            ),
                            ..._availableTypes.map((type) {
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Text(typeLabels[type] ?? type),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Egyetlen közös lista az összes elemnek
          if (!isEmpty)
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  ...filteredNoteIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'notes',
                        defaultColor: Colors.blue.shade700,
                      )),
                  ...filteredAllomasIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'memoriapalota_allomasok',
                        defaultColor: Colors.orange.shade700,
                      )),
                  ...filteredDialogusIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'dialogus_fajlok',
                        defaultColor: Colors.green.shade700,
                      )),
                ],
              ),
            ),

          // Ha nincs egyetlen dokumentum sem (vagy a szűrés után üres)
          if (isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _selectedType == 'all'
                          ? Icons.folder_open
                          : Icons.filter_list_off,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _selectedType == 'all'
                          ? 'Ez a köteg még üres'
                          : 'Nincs ilyen típusú elem a kötegben',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile({
    required String id,
    required String collection,
    required Color defaultColor,
  }) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseConfig.firestore.collection(collection).doc(id).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            title: Text('Betöltés...'),
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String title = data['title'] ?? data['name'] ?? 'Névtelen';
          final type = data['type'] as String? ?? 'standard';
          IconData icon = Icons.description;
          String? audioUrl;

          if (collection == 'dialogus_fajlok') {
            audioUrl = data['audioUrl'] as String?;
            icon = Icons.mic;
          } else if (collection == 'memoriapalota_allomasok') {
            icon = Icons.directions_bus;
          } else {
            switch (type) {
              case 'deck':
                icon = Icons.style;
                break;
              case 'dynamic_quiz':
                icon = Icons.quiz;
                break;
              case 'dynamic_quiz_dual':
                icon = Icons.quiz_outlined;
                break;
              case 'interactive':
                icon = Icons.touch_app;
                break;
              case 'jogeset':
                icon = Icons.gavel;
                break;
              default:
                icon = Icons.description;
            }
          }

          final bool isDialogue = collection == 'dialogus_fajlok';

          return InkWell(
            onTap:
                !isDialogue ? () => _navigateToDocument(id, collection) : null,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: defaultColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          icon,
                          color: defaultColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                      ),
                      if (isDialogue && (audioUrl?.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: MiniAudioPlayer(
                            audioUrl: audioUrl!,
                            compact: false,
                            large: true,
                          ),
                        )
                      else if (!isDialogue)
                        Icon(Icons.chevron_right,
                            color: Colors.grey.shade400, size: 18),
                    ],
                  ),
                ),
                Divider(height: 1, indent: 70, color: Colors.grey.shade100),
              ],
            ),
          );
        } else {
          return const ListTile(
            leading: Icon(Icons.error_outline, color: Colors.red),
            title: Text('Dokumentum nem található',
                style: TextStyle(color: Colors.red)),
          );
        }
      },
    );
  }

  Future<void> _navigateToDocument(String id, String collection) async {
    try {
      // Megnyitás előtt lekérjük a dokumentum metaadatait a helyes navigációhoz
      final doc =
          await FirebaseConfig.firestore.collection(collection).doc(id).get();

      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dokumentum nem található')),
          );
        }
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      final science = data['science'] as String?;
      final category = data['category'] as String?;
      final tags = data['tags'] as List<dynamic>?;
      final tag =
          tags != null && tags.isNotEmpty ? tags.first.toString() : null;

      // FilterStorage inicializálása, hogy a Jegyzethallgató/Olvasó tudja, hova kell visszalépni
      // és milyen környezetben kell betöltenie a tartalmat
      FilterStorage.science = science;
      FilterStorage.category = category;
      FilterStorage.tag = tag;

      if (!mounted) return;
      if (collection == 'notes') {
        final type = data['type'] as String? ?? 'standard';

        if (type == 'dynamic_quiz' || type == 'dynamic_quiz_dual') {
          // Kvíz esetén követjük a NoteListTile logikáját
          // Itt egyszerűség kedvéért a mobil útvonalat használjuk mindenhol a kötegben,
          // vagy ha nagyon precízek akarunk lenni, átvesszük a NoteListTile elágazását.
          context.go('/quiz/$id?from=bundle&bundleId=${widget.bundleId}');
        } else if (type == 'deck') {
          // Tanulókártya: kötelezően a VIEW (előoldal), nem a STUDY
          context.go('/deck/$id/view?from=bundle&bundleId=${widget.bundleId}');
        } else if (type == 'interactive') {
          context.go(
              '/interactive-note/$id?from=bundle&bundleId=${widget.bundleId}');
        } else if (type == 'jogeset') {
          context.go('/jogeset/$id?from=bundle&bundleId=${widget.bundleId}');
        } else {
          context.go('/note/$id?from=bundle&bundleId=${widget.bundleId}');
        }
      } else if (collection == 'memoriapalota_allomasok') {
        context.go(
            '/memoriapalota-allomas/$id?from=bundle&bundleId=${widget.bundleId}');
      } else if (collection == 'dialogus_fajlok') {
        // Dialógus fájlok esetén nincs navigáció, helyben lejátszhatóak
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a megnyitás során: $e')),
        );
      }
    }
  }
}
