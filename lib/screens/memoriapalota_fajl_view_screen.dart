import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/audio_preview_player.dart';
import '../widgets/breadcrumb_navigation.dart';
import '../utils/filter_storage.dart';

/// Felhasználói (csak olvasás) nézet memoriapalota_fajlok típusú jegyzetekhez.
///
/// - Csak cím megjelenítés és hanganyag lejátszás
/// - Nincsenek admin műveletek
class MemoriapalotaFajlViewScreen extends StatefulWidget {
  final String noteId;
  final String? from;

  const MemoriapalotaFajlViewScreen({
    super.key,
    required this.noteId,
    this.from,
  });

  @override
  State<MemoriapalotaFajlViewScreen> createState() =>
      _MemoriapalotaFajlViewScreenState();
}

class _MemoriapalotaFajlViewScreenState
    extends State<MemoriapalotaFajlViewScreen> {
  DocumentSnapshot? _noteSnapshot;
  bool _isLoading = true;
  
  // Jegyzet adatok breadcrumb-hoz
  String? _noteTitle;
  String? _noteCategory;
  String? _noteTag;

  @override
  void initState() {
    super.initState();
    // FONTOS: Betöltjük a FilterStorage értékeit az előző oldal URL-jéből (from paraméter)
    _loadFiltersFromUrl();
    _loadNoteData();
    _loadNote();
  }
  
  /// Betölti a FilterStorage értékeit az előző oldal URL-jéből (from paraméter)
  /// Ez biztosítja, hogy a breadcrumb és visszalépés gombok működjenek
  void _loadFiltersFromUrl() {
    if (widget.from != null && widget.from!.isNotEmpty) {
      try {
        final fromUri = Uri.parse(Uri.decodeComponent(widget.from!));
        final queryParams = fromUri.queryParameters;
        
        // Normalizáljuk az "MP" értéket "memoriapalota_allomasok"-ra
        final type = queryParams['type'];
        final normalizedType = type == 'MP' ? 'memoriapalota_allomasok' : type;
        
        // Beállítjuk a FilterStorage értékeit az URL query paramétereiből
        FilterStorage.searchText = queryParams['q'];
        FilterStorage.status = queryParams['status'];
        FilterStorage.category = queryParams['category'];
        FilterStorage.science = queryParams['science'];
        FilterStorage.tag = queryParams['tag'];
        FilterStorage.type = normalizedType;
        
        debugPrint('🔵 MemoriapalotaFajlViewScreen _loadFiltersFromUrl:');
        debugPrint('   from=${widget.from}');
        debugPrint('   tag=${FilterStorage.tag}');
        debugPrint('   category=${FilterStorage.category}');
        debugPrint('   type=${FilterStorage.type}');
      } catch (e) {
        debugPrint('🔴 Hiba a FilterStorage betöltésekor az URL-ből: $e');
      }
    }
  }
  
  /// Betölti a jegyzet adatait breadcrumb-hoz
  /// Először a notes kollekcióból próbálja, ha nem találja, akkor a memoriapalota_fajlok kollekcióból
  Future<void> _loadNoteData() async {
    try {
      // Először próbáljuk a notes kollekcióból
      var noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId)
          .get();
      
      // Ha nem található a notes kollekcióban, próbáljuk a memoriapalota_fajlok kollekcióból
      if (!noteDoc.exists) {
        noteDoc = await FirebaseFirestore.instance
            .collection('memoriapalota_fajlok')
            .doc(widget.noteId)
            .get();
      }
      
      if (noteDoc.exists && mounted) {
        final data = noteDoc.data();
        if (data != null) {
          final title = data['title'] as String?;
          final category = data['category'] as String?;
          final tags = data['tags'] as List<dynamic>?;
          final tag = tags != null && tags.isNotEmpty ? tags.first.toString() : null;
          
          // Debug: ellenőrizzük, hogy milyen adatokat kaptunk
          debugPrint('🔵 MemoriapalotaFajlViewScreen _loadNoteData:');
          debugPrint('   noteId=${widget.noteId}');
          debugPrint('   title=$title');
          debugPrint('   category=$category');
          debugPrint('   tags=$tags');
          debugPrint('   tag=$tag');
          
            setState(() {
              _noteTitle = title;
              // _noteCategory és _noteTag már nem használatosak, mert csak FilterStorage értékeit használjuk
            });
        }
      } else {
        debugPrint('🔴 MemoriapalotaFajlViewScreen: A jegyzet nem található sem a notes, sem a memoriapalota_fajlok kollekcióban (noteId=${widget.noteId})');
      }
    } catch (e) {
      // Csendben kezeljük a hibát, nem akadályozza meg az oldal betöltését
      debugPrint('🔴 Hiba a jegyzet adatainak betöltésekor: $e');
    }
  }

  Future<void> _loadNote() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('memoriapalota_fajlok')
          .doc(widget.noteId)
          .get();

      if (!mounted) return;

      setState(() {
        _noteSnapshot = snapshot;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba a jegyzet betöltésekor: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_noteSnapshot == null || !_noteSnapshot!.exists) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Jegyzet nem található'),
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: Theme.of(context).primaryColor,
            ),
            onPressed: () {
              final uri = Uri(
                path: '/notes',
                queryParameters: {
                  if (FilterStorage.searchText != null &&
                      FilterStorage.searchText!.isNotEmpty)
                    'q': FilterStorage.searchText!,
                  if (FilterStorage.status != null)
                    'status': FilterStorage.status!,
                  if (FilterStorage.category != null)
                    'category': FilterStorage.category!,
                  if (FilterStorage.science != null)
                    'science': FilterStorage.science!,
                  if (FilterStorage.tag != null) 'tag': FilterStorage.tag!,
                  if (FilterStorage.type != null) 'type': FilterStorage.type!,
                },
              );
              context.go(uri.toString());
            },
          ),
        ),
        body: const Center(
          child: Text('Ez a jegyzet nem található.'),
        ),
      );
    }

    final data = _noteSnapshot!.data() as Map<String, dynamic>;
    final title = data['cim'] as String? ?? 'Cím nélkül';
    final audioUrl = data['audioUrl'] as String?;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 16 : 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: Theme.of(context).primaryColor,
            size: isMobile ? 20 : 22,
          ),
          onPressed: () {
            // Breadcrumb navigációval visszalépünk
            // Prioritás: 1. FilterStorage-ban tárolt előző oldal szűrői, 2. Jegyzet aktuális értékei
            // CSAK FilterStorage-ban tárolt előző oldal szűrőit használjuk, SOHA ne a jegyzet aktuális értékeit!
            final effectiveTag = FilterStorage.tag;
            final effectiveCategory = FilterStorage.category;
            
            if (effectiveTag != null && effectiveTag.isNotEmpty) {
              // Először próbáljuk a címkére, ha van
              final uri = Uri(
                path: '/notes',
                queryParameters: {
                  if (FilterStorage.searchText != null &&
                      FilterStorage.searchText!.isNotEmpty)
                    'q': FilterStorage.searchText!,
                  if (FilterStorage.status != null)
                    'status': FilterStorage.status!,
                  if (effectiveCategory != null) 'category': effectiveCategory,
                  if (FilterStorage.science != null)
                    'science': FilterStorage.science!,
                  'tag': effectiveTag,
                  if (FilterStorage.type != null) 'type': FilterStorage.type!,
                },
              );
              context.go(uri.toString());
            } else if (effectiveCategory != null && effectiveCategory.isNotEmpty) {
              // Ha nincs címke, de van kategória, akkor a kategóriára lépünk vissza
              final uri = Uri(
                path: '/notes',
                queryParameters: {
                  if (FilterStorage.searchText != null &&
                      FilterStorage.searchText!.isNotEmpty)
                    'q': FilterStorage.searchText!,
                  if (FilterStorage.status != null)
                    'status': FilterStorage.status!,
                  'category': effectiveCategory,
                  if (FilterStorage.science != null)
                    'science': FilterStorage.science!,
                  if (FilterStorage.type != null) 'type': FilterStorage.type!,
                },
              );
              context.go(uri.toString());
            } else {
              // Ha nincs sem kategória, sem címke, akkor a főoldalra
              final uri = Uri(
                path: '/notes',
                queryParameters: {
                  if (FilterStorage.searchText != null &&
                      FilterStorage.searchText!.isNotEmpty)
                    'q': FilterStorage.searchText!,
                  if (FilterStorage.status != null)
                    'status': FilterStorage.status!,
                  if (FilterStorage.science != null)
                    'science': FilterStorage.science!,
                  if (FilterStorage.type != null) 'type': FilterStorage.type!,
                },
              );
              context.go(uri.toString());
            }
          },
        ),
        actions: const [],
      ),
      body: Column(
        children: [
          // Breadcrumb navigáció
          // A breadcrumb a jegyzet aktuális kategóriáját és címkéjét mutatja
          BreadcrumbNavigation(
            category: _noteCategory,
            tag: _noteTag,
            noteTitle: _noteTitle,
            noteId: widget.noteId,
          ),
          // Tartalom
          Expanded(
            child: Container(
              color: const Color(0xFFF8F9FA),
              child: Column(
                children: [
                  Expanded(
              child: Container(
                margin: EdgeInsets.all(isMobile ? 0 : 16),
                decoration: isMobile
                    ? null
                    : BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.audiotrack,
                          size: isMobile ? 64 : 80,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: isMobile ? 18 : 24,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF202122),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (audioUrl == null || audioUrl.isEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Ez a jegyzet nem tartalmaz hangfájlt.',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
                  if (audioUrl != null && audioUrl.isNotEmpty)
                    Container(
                      margin: EdgeInsets.fromLTRB(
                        isMobile ? 0 : 16,
                        0,
                        isMobile ? 0 : 16,
                        isMobile ? 0 : 16,
                      ),
                      child: AudioPreviewPlayer(audioUrl: audioUrl),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

