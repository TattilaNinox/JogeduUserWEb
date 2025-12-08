import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import '../core/firebase_config.dart';

class MemoriapalotaAllomasViewScreen extends StatefulWidget {
  final String noteId;

  const MemoriapalotaAllomasViewScreen({
    super.key,
    required this.noteId,
  });

  @override
  State<MemoriapalotaAllomasViewScreen> createState() =>
      _MemoriapalotaAllomasViewScreenState();
}

class _MemoriapalotaAllomasViewScreenState
    extends State<MemoriapalotaAllomasViewScreen> {
  List<DocumentSnapshot> _allomasok = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String _currentHtmlContent = '';
  String _viewId = '';

  @override
  void initState() {
    super.initState();
    _loadAllomasok();
  }

  void _setupIframe(String tartalom) {
    // FONTOS: Ellenőrizzük, hogy web platformon vagyunk-e!
    if (!kIsWeb) {
      // Ha nem web platform, nem hozunk létre iframe-et
      return;
    }
    
    // FONTOS: Minden alkalommal egyedi view ID-t kell generálni!
    _viewId = 'memoriapalota-allomas-iframe-${DateTime.now().millisecondsSinceEpoch}';
    
    // Iframe elem létrehozása
    final iframeElement = web.HTMLIFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none';
    
    iframeElement.sandbox.add('allow-scripts');
    iframeElement.sandbox.add('allow-same-origin');
    iframeElement.sandbox.add('allow-forms');
    iframeElement.sandbox.add('allow-popups');
    
    // FONTOS: Teljes HTML dokumentum létrehozása CSS stílusokkal
    // MEGJEGYZÉS: A cím és kulcsszó már az AppBar-ban megjelenik, ezért nem tesszük ide
    final fullHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * {
      box-sizing: border-box;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      font-size: 14px;
      line-height: 1.6;
      color: #333;
      padding: 20px;
      margin: 0;
      background-color: #fff;
      text-align: justify;
    }
    h1, h2, h3 {
      color: #1976d2;
      margin-top: 1.5em;
      margin-bottom: 0.5em;
    }
    h1 {
      font-size: 24px;
    }
    h2 {
      font-size: 20px;
    }
    h3 {
      font-size: 18px;
    }
    .kulcsszo {
      display: inline-block;
      background-color: #e3f2fd;
      padding: 4px 8px;
      border-radius: 4px;
      font-weight: 500;
      margin-bottom: 10px;
    }
    .szin-kek {
      color: #1976d2;
      font-weight: 500;
    }
    .szin-zold {
      color: #388e3c;
      font-weight: 500;
    }
    .hatter-sarga {
      background-color: #fff9c4;
      padding: 2px 4px;
      border-radius: 3px;
    }
    .jogszabaly-doboz {
      background-color: #f5f5f5;
      border-left: 4px solid #1976d2;
      padding: 12px;
      margin: 16px 0;
      border-radius: 4px;
    }
    .jogszabaly-cimke {
      font-weight: bold;
      color: #1976d2;
      display: block;
      margin-bottom: 8px;
    }
    .allomas-badge {
      display: inline-block;
      background-color: #1976d2;
      color: white;
      padding: 4px 10px;
      border-radius: 12px;
      font-weight: bold;
      margin-right: 8px;
    }
    p {
      margin-bottom: 12px;
    }
    ul, ol {
      margin-bottom: 12px;
      padding-left: 24px;
    }
    li {
      margin-bottom: 6px;
    }
    img {
      max-width: 100%;
      height: auto;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 16px;
    }
    table, th, td {
      border: 1px solid #ddd;
    }
    th, td {
      padding: 8px;
      text-align: left;
    }
    /* Reszponzív stílusok */
    @media (max-width: 768px) {
      body {
        font-size: 13px;
        padding: 12px;
      }
      h1 {
        font-size: 20px;
      }
      h2 {
        font-size: 18px;
      }
      h3 {
        font-size: 16px;
      }
      .jogszabaly-doboz {
        padding: 10px;
        margin: 12px 0;
      }
      ul, ol {
        padding-left: 20px;
      }
      table {
        font-size: 12px;
      }
      th, td {
        padding: 6px;
      }
    }
    @media (max-width: 480px) {
      body {
        font-size: 12px;
        padding: 10px;
      }
      h1 {
        font-size: 18px;
      }
      h2 {
        font-size: 16px;
      }
      h3 {
        font-size: 14px;
      }
      .kulcsszo {
        padding: 3px 6px;
        font-size: 11px;
      }
      .allomas-badge {
        padding: 3px 8px;
        font-size: 11px;
      }
      .jogszabaly-doboz {
        padding: 8px;
        margin: 10px 0;
      }
      ul, ol {
        padding-left: 18px;
      }
      table {
        font-size: 11px;
      }
      th, td {
        padding: 4px;
      }
    }
  </style>
</head>
<body>
  $tartalom
</body>
</html>
''';
    
    // FONTOS: Az iframe src-jét data URI formátumban kell beállítani!
    // FONTOS: A HTML tartalmat MINDIG Uri.encodeComponent()-tel kell kódolni!
    iframeElement.src = 'data:text/html;charset=utf-8,${Uri.encodeComponent(fullHtml)}';
    
    // FONTOS: Platform view regisztrálása MINDIG az iframe src beállítása UTÁN!
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => iframeElement,
    );
  }


  Future<void> _loadAllomasok() async {
    try {
      // A widget.noteId az utvonalId (a fő útvonal dokumentum ID-ja)
      final utvonalID = widget.noteId;

      if (utvonalID.isEmpty) {
        setState(() {
          _errorMessage = 'Az útvonal ID nem található.';
          _isLoading = false;
        });
        return;
      }

      // Betöltjük az összes állomást a subcollection-ből
      // A struktúra: memoriapalota_allomasok/{utvonalId}/allomasok/{allomasId}
      final snapshot = await FirebaseConfig.firestore
          .collection('memoriapalota_allomasok')
          .doc(utvonalID)
          .collection('allomasok')
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _errorMessage = 'Nem található állomás ezzel az utvonalID-vel.';
          _isLoading = false;
        });
        return;
      }

      // Rendezzük az állomásokat allomasSorszam alapján
      final allomasok = snapshot.docs.toList();
      allomasok.sort((a, b) {
        final sorszamA = a.data()['allomasSorszam'] as int? ?? 0;
        final sorszamB = b.data()['allomasSorszam'] as int? ?? 0;
        return sorszamA.compareTo(sorszamB);
      });

      setState(() {
        _allomasok = allomasok;
        _currentIndex = 0;
        _isLoading = false;
      });

      // Megjelenítjük az első állomást
      _displayCurrentAllomas();
    } catch (e) {
      setState(() {
        _errorMessage = 'Hiba történt az állomások betöltésekor: $e';
        _isLoading = false;
      });
    }
  }

  void _displayCurrentAllomas() {
    if (_allomasok.isEmpty || _currentIndex < 0 || _currentIndex >= _allomasok.length) {
      return;
    }

    final currentAllomas = _allomasok[_currentIndex];
    final data = currentAllomas.data() as Map<String, dynamic>;
    
    // Az állomások tartalma
    final tartalom = data['tartalom'] as String? ?? '';
    
    // Ha nincs tartalom, alapértelmezett üzenet
    final content = tartalom.isNotEmpty 
        ? tartalom 
        : '<p>Nincs tartalom.</p>';
    
    // Új iframe-et hozunk létre az új tartalommal (teljes HTML dokumentummal)
    _setupIframe(content);
    
    // Frissítjük a tartalmat és újraépítjük a view-t
    setState(() {
      _currentHtmlContent = content;
    });
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _displayCurrentAllomas();
    }
  }

  void _goToNext() {
    if (_currentIndex < _allomasok.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _displayCurrentAllomas();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Memóriapalota Állomások'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/notes'),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Memóriapalota Állomások'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/notes'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/notes'),
                child: const Text('Vissza a jegyzetekhez'),
              ),
            ],
          ),
        ),
      );
    }

    if (_allomasok.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Memóriapalota Állomások'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/notes'),
          ),
        ),
        body: const Center(
          child: Text('Nincsenek állomások ebben a kötegben.'),
        ),
      );
    }

    final currentAllomas = _allomasok[_currentIndex];
    final data = currentAllomas.data() as Map<String, dynamic>;
    // Az állomásoknak 'cim' mezőjük van
    final title = data['cim'] as String? ?? 'Állomás';
    final allomasSorszam = data['allomasSorszam'] as int? ?? 0;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isMobile ? 80 : (isTablet ? 70 : 56),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: isMobile ? 12 : (isTablet ? 14 : 18),
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.visible,
              maxLines: isMobile ? 3 : (isTablet ? 2 : 1),
              softWrap: true,
            ),
            const SizedBox(height: 2),
            Text(
              '${allomasSorszam}/${_allomasok.length}',
              style: TextStyle(
                fontSize: isMobile ? 10 : (isTablet ? 11 : 12),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/notes'),
        ),
      ),
      body: Column(
        children: [
          // HTML tartalom megjelenítése
          Expanded(
            child: kIsWeb && _currentHtmlContent.isNotEmpty && _viewId.isNotEmpty
                ? HtmlElementView(
                    key: ValueKey('iframe_$_viewId'),
                    viewType: _viewId,
                  )
                : const Center(
                    child: Text(
                      'Nem sikerült betölteni a tartalmat',
                      style: TextStyle(color: Colors.red, fontSize: 16),
                    ),
                  ),
          ),
          // Navigációs gombok
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _currentIndex > 0 ? _goToPrevious : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Előző'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                Text(
                  '${_currentIndex + 1} / ${_allomasok.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ElevatedButton.icon(
                  onPressed:
                      _currentIndex < _allomasok.length - 1 ? _goToNext : null,
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
}

