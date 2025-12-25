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

    // Típusok leképezése magyar névre és ikonra
    final Map<String, Map<String, dynamic>> typeConfig = {
      'all': {'label': 'Összes típus', 'icon': Icons.filter_list},
      'standard': {'label': 'Szöveg Tags', 'icon': Icons.description},
      'text': {'label': 'Szöveg Tags', 'icon': Icons.description},
      'deck': {'label': 'Tanulókártya', 'icon': Icons.style},
      'dynamic_quiz': {'label': 'Kvíz', 'icon': Icons.quiz},
      'dynamic_quiz_dual': {'label': 'Páros kvíz', 'icon': Icons.quiz_outlined},
      'interactive': {'label': 'Interaktív', 'icon': Icons.touch_app},
      'jogeset': {'label': 'Jogeset', 'icon': Icons.gavel},
      'mp': {'label': 'Memória útvonal', 'icon': Icons.directions_bus},
      'dialogue': {'label': 'Dialógus', 'icon': Icons.mic},
    };

    // Lista szűrése
    final filteredNoteIds = allNoteIds.where((id) {
      if (_selectedType == 'all') return true;
      final docType = _docTypes[id];
      if (_selectedType == 'standard' || _selectedType == 'text') {
        return docType == 'standard' || docType == 'text';
      }
      return docType == _selectedType;
    }).toList();

    final filteredAllomasIds = allAllomasIds.where((id) {
      if (_selectedType == 'all') return true;
      return _selectedType == 'mp';
    }).toList();

    final filteredDialogusIds = allDialogusIds.where((id) {
      if (_selectedType == 'all') return true;
      return _selectedType == 'dialogue';
    }).toList();

    final bool isEmpty = filteredNoteIds.isEmpty &&
        filteredAllomasIds.isEmpty &&
        filteredDialogusIds.isEmpty;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 18 : 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: isMobile ? 18 : 20),
          onPressed: () => context.go('/my-bundles'),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(Icons.edit_outlined, size: isMobile ? 22 : 24),
              onPressed: () =>
                  context.go('/my-bundles/edit/${widget.bundleId}'),
              tooltip: 'Szerkesztés',
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12.0 : 20.0,
          vertical: isMobile ? 16.0 : 24.0,
        ),
        children: [
          // Leírás
          if (description.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: isMobile ? 16 : 18,
                          color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Leírás',
                        style: TextStyle(
                          fontSize: isMobile ? 13 : 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 8 : 12),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 15,
                      height: 1.4,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 16 : 24),
          ],

          // Típusszűrő - Prémium UI
          if (_availableTypes.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: isMobile ? 16.0 : 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                    child: Text(
                      'Tartalom szűrése',
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    height: isMobile ? 48 : 54,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedType,
                        isExpanded: true,
                        icon: Icon(Icons.unfold_more,
                            size: 20, color: Colors.grey.shade600),
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor: Colors.white,
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedType = newValue;
                            });
                          }
                        },
                        items: [
                          DropdownMenuItem<String>(
                            value: 'all',
                            child: Row(
                              children: [
                                Icon(Icons.grid_view_rounded,
                                    size: isMobile ? 16 : 18,
                                    color: Colors.blue.shade700),
                                const SizedBox(width: 12),
                                Text('Összes típus',
                                    style: TextStyle(
                                        fontSize: isMobile ? 13 : 14)),
                              ],
                            ),
                          ),
                          ..._availableTypes.map((type) {
                            final config = typeConfig[type] ??
                                {'label': type, 'icon': Icons.help_outline};
                            return DropdownMenuItem<String>(
                              value: type,
                              child: Row(
                                children: [
                                  Icon(config['icon'] as IconData,
                                      size: isMobile ? 16 : 18,
                                      color: Colors.blue.shade700),
                                  const SizedBox(width: 12),
                                  Text(config['label'] as String,
                                      style: TextStyle(
                                          fontSize: isMobile ? 13 : 14)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Lista szakasz
          if (!isEmpty) ...[
            if (_selectedType != 'all')
              Padding(
                padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
                child: Text(
                  '${typeConfig[_selectedType]?['label'] ?? _selectedType} (${filteredNoteIds.length + filteredAllomasIds.length + filteredDialogusIds.length})',
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2C3E50),
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ...filteredNoteIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'notes',
                        defaultColor: Colors.blue.shade700,
                        isMobile: isMobile,
                      )),
                  ...filteredAllomasIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'memoriapalota_allomasok',
                        defaultColor: Colors.orange.shade700,
                        isMobile: isMobile,
                      )),
                  ...filteredDialogusIds.map((id) => _buildDocumentTile(
                        id: id,
                        collection: 'dialogus_fajlok',
                        defaultColor: Colors.green.shade700,
                        isMobile: isMobile,
                      )),
                ],
              ),
            ),
          ],

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
    required bool isMobile,
  }) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseConfig.firestore.collection(collection).doc(id).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 20,
              vertical: isMobile ? 10 : 16,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: isMobile ? 32 : 40,
                  height: isMobile ? 32 : 40,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: isMobile ? 100 : 140,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
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
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 20,
                    vertical: isMobile ? 10 : 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 8 : 10),
                        decoration: BoxDecoration(
                          color: defaultColor.withOpacity(0.08),
                          borderRadius:
                              BorderRadius.circular(isMobile ? 10 : 12),
                        ),
                        child: Icon(
                          icon,
                          color: defaultColor,
                          size: isMobile ? 18 : 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 15,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF2C3E50),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (isDialogue && (audioUrl?.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: MiniAudioPlayer(
                            audioUrl: audioUrl!,
                            compact: isMobile,
                            large: !isMobile,
                          ),
                        )
                      else if (!isDialogue)
                        Icon(Icons.arrow_forward_ios,
                            color: Colors.grey.shade300, size: 12),
                    ],
                  ),
                ),
                Divider(
                    height: 1,
                    indent: isMobile ? 56 : 68,
                    color: Colors.grey.shade50),
              ],
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade300, size: 20),
                const SizedBox(width: 12),
                const Text(
                  'Dokumentum nem található',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
              ],
            ),
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
