import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import 'dart:async';

import '../widgets/audio_preview_player.dart';

/// Köteg (bundle) megjelenítő képernyő prezentáció módban.
/// 
/// Ez a képernyő prezentációszerűen jeleníti meg a kötegben lévő jegyzeteket.
/// A felhasználó navigálhat előre-hátra a jegyzetek között, mint egy diavetítésben.
class BundleViewScreen extends StatefulWidget {
  final String bundleId;

  const BundleViewScreen({super.key, required this.bundleId});

  @override
  State<BundleViewScreen> createState() => _BundleViewScreenState();
}

class _BundleViewScreenState extends State<BundleViewScreen> {
  // Köteg adatai
  DocumentSnapshot? _bundleSnapshot;
  String _bundleName = '';
  List<String> _noteIds = [];
  bool _isLoadingNotes = true; // Flag, hogy ne jelenjen meg az üres üzenet betöltés közben
  bool _isLoadingInProgress = false; // Flag, hogy ne töltse be többször az adatokat
  
  // Jegyzetek adatai
  Map<String, Map<String, dynamic>> _notesData = {};
  int _currentIndex = 0;
  String _currentHtmlContent = '';
  
  // HTML megjelenítés
  late final String _viewId;
  bool _hasContent = false;
  
  // Stream subscriptions
  StreamSubscription<DocumentSnapshot>? _bundleSubscription;
  
  @override
  void initState() {
    super.initState();
    
    // Az ID-t a state objektum hash kódjából generáljuk, hogy mindig egyedi legyen.
    // Így elkerüljük a platform view cache-elési problémákat.
    _viewId = "bundle-view-iframe-$hashCode";
    
    // A view factory-t úgy módosítjuk, hogy mindig új iframe-et hozzon létre
    // az aktuális HTML tartalommal.
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry
        .registerViewFactory(_viewId, (int viewId) {
          final web.HTMLIFrameElement iframeElement = web.HTMLIFrameElement();
          iframeElement
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.border = 'none'
            ..src = 'data:text/html;charset=utf-8,${Uri.encodeComponent(_currentHtmlContent)}';
          return iframeElement;
        });
    
    _loadBundle();
  }
  
  /// Betölti a köteg és a benne lévő jegyzetek adatait
  Future<void> _loadBundle() async {
    _bundleSubscription = FirebaseFirestore.instance
        .collection('bundles')
        .doc(widget.bundleId)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      
      // Ha már betöltés folyamatban van, ne kezdjük el újra
      if (_isLoadingInProgress) return;
      
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        _bundleName = data['name'] ?? 'Névtelen köteg';
        final noteIds = List<String>.from(data['noteIds'] ?? []);
        
        // Betöltés közben ne jelenjen meg az üres üzenet - csak a loading flag-et állítjuk be
        setState(() {
          _isLoadingNotes = true;
          _isLoadingInProgress = true;
          // NE állítsuk be a _bundleSnapshot-ot még, amíg nem töltődtek be az adatok!
        });
        
        // Betöltjük a jegyzetek adatait
          await _loadNotesData();
        if (!mounted) return;
        
        // Beállítjuk a state-et, hogy betöltse az iframe-et
        setState(() {
          _bundleSnapshot = snapshot;
          _noteIds = noteIds;
          // Még nem állítjuk le a loading flag-et, várjuk meg az iframe betöltését
        });
        
        // Betöltjük az aktuális jegyzet tartalmát
        _loadCurrentNote();
        
        // Várunk egy kicsit, hogy az iframe betöltődhessen
        // Az iframe betöltése aszinkron, ezért egy rövid késleltetést használunk
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        
        // Most már beállíthatjuk, hogy a loading screen eltűnjön
        setState(() {
          _isLoadingNotes = false;
          _isLoadingInProgress = false;
        });
      }
    });
  }
  
  /// Betölti az összes jegyzet adatát
  Future<void> _loadNotesData() async {
    if (_noteIds.isEmpty) return;
    
    final notes = await FirebaseFirestore.instance
        .collection('notes')
        .where(FieldPath.documentId, whereIn: _noteIds)
        .get();
    
    _notesData = {
      for (var doc in notes.docs)
        doc.id: doc.data()
    };
  }
  
  /// Betölti az aktuális jegyzet HTML tartalmát
  void _loadCurrentNote() {
    if (_currentIndex >= _noteIds.length) return;
    
    final noteId = _noteIds[_currentIndex];
    final noteData = _notesData[noteId];
    
    String newHtmlContent = '';
    if (noteData != null) {
      final pages = noteData['pages'] as List<dynamic>? ?? [];
      if (pages.isNotEmpty) {
        newHtmlContent = pages.first as String? ?? '';
      }
    }
    
    // Csak az állapotot frissítjük, a build majd újraépíti a view-t
    setState(() {
      _currentHtmlContent = newHtmlContent;
      _hasContent = _currentHtmlContent.isNotEmpty;
    });
  }
  
  /// Navigálás az előző jegyzetre
  void _previousNote() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _loadCurrentNote();
    }
  }
  
  /// Navigálás a következő jegyzetre
  void _nextNote() {
    if (_currentIndex < _noteIds.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _loadCurrentNote();
    }
  }
  
  /// Ugrás egy adott jegyzetre
  void _jumpToNote(int index) {
    if (index >= 0 && index < _noteIds.length) {
      setState(() {
        _currentIndex = index;
      });
      _loadCurrentNote();
    }
  }
  
  /// Teljes képernyős mód váltása
  void _toggleFullScreen() {
    // Implementálható teljes képernyős mód
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teljes képernyős mód hamarosan elérhető lesz'),
        duration: Duration(seconds: 2),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    if (_bundleSnapshot == null || _isLoadingNotes || _noteIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Betöltés...'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/bundles'),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    final currentNoteId = _noteIds[_currentIndex];
    final currentNoteData = _notesData[currentNoteId];
    final currentNoteTitle = currentNoteData?['title'] ?? 'Ismeretlen jegyzet';
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_bundleName),
            Text(
              '${_currentIndex + 1} / ${_noteIds.length} - $currentNoteTitle',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/bundles'),
        ),
        actions: [
          // Jegyzetek lista gomb
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => _showNotesList(),
            tooltip: 'Jegyzetek listája',
          ),
          // Teljes képernyő gomb
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: _toggleFullScreen,
            tooltip: 'Teljes képernyő',
          ),
        ],
      ),
      body: Column(
        children: [
          // Tartalom megjelenítő
          Expanded(
            child: _hasContent
                ? HtmlElementView(
                    key: ValueKey('iframe_$_currentIndex'),
                    viewType: _viewId,
                  )
                : const Center(
                    child: Text(
                      'Nem sikerült betölteni a jegyzet tartalmát',
                      style: TextStyle(color: Colors.red, fontSize: 16),
                    ),
                  ),
          ),
          
          // Audio lejátszó ha van
          if (currentNoteData != null && 
              currentNoteData['audioUrl'] != null &&
              currentNoteData['audioUrl'].toString().isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: AudioPreviewPlayer(audioUrl: currentNoteData['audioUrl']),
            ),
          ],
          
          // Navigációs sáv
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(26),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Előző gomb
                ElevatedButton.icon(
                  onPressed: _currentIndex > 0 ? _previousNote : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Előző'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                
                // Pozíció jelző
                Row(
                  children: [
                    for (int i = 0; i < _noteIds.length; i++)
                      GestureDetector(
                        onTap: () => _jumpToNote(i),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _currentIndex
                                ? Theme.of(context).primaryColor
                                : Colors.grey.shade300,
                          ),
                        ),
                      ),
                  ],
                ),
                
                // Következő gomb
                ElevatedButton.icon(
                  onPressed: _currentIndex < _noteIds.length - 1 
                      ? _nextNote 
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Következő'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
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
  
  /// Jegyzetek listájának megjelenítése dialógusban
  void _showNotesList() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$_bundleName - Jegyzetek'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: _noteIds.length,
            itemBuilder: (context, index) {
              final noteId = _noteIds[index];
              final noteData = _notesData[noteId];
              final title = noteData?['title'] ?? 'Ismeretlen jegyzet';
              final isActive = index == _currentIndex;
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isActive 
                      ? Theme.of(context).primaryColor 
                      : Colors.grey.shade300,
                  foregroundColor: isActive ? Colors.white : Colors.black,
                  child: Text('${index + 1}'),
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isActive,
                onTap: () {
                  Navigator.of(context).pop();
                  _jumpToNote(index);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Bezárás'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _bundleSubscription?.cancel();
    super.dispose();
  }
} 