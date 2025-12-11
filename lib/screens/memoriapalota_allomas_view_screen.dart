import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import '../core/firebase_config.dart';

// Top-level függvény a compute-hoz - gyorsított, egyszerűsített verzió
Future<Uint8List?> _compressImageInIsolate(Uint8List imageBytes) async {
  // Ha már 200 KB alatt van, visszaadja
  if (imageBytes.length <= 200 * 1024) {
    return imageBytes;
  }
  
  try {
    // Kép dekódolása
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw Exception('Nem sikerült dekódolni a képet');
    }
    
    // Agresszív kezdeti beállítások - gyors tömörítés
    final originalSizeKB = imageBytes.length / 1024;
    const targetSizeKB = 200.0;
    final sizeRatio = originalSizeKB / targetSizeKB;
    
    // Kezdeti értékek - agresszívabb tömörítés
    int targetWidth = decodedImage.width;
    int targetHeight = decodedImage.height;
    int quality = 70; // Alacsonyabb kezdeti minőség
    
    // Agresszív méret csökkentés azonnal
    if (sizeRatio > 3) {
      // Nagyon nagy kép: jelentősen csökkentjük
      const scale = 0.5;
      targetWidth = (decodedImage.width * scale).round();
      targetHeight = (decodedImage.height * scale).round();
      quality = 60;
    } else if (sizeRatio > 2) {
      // Nagy kép: mérsékelten csökkentjük
      const scale = 0.65;
      targetWidth = (decodedImage.width * scale).round();
      targetHeight = (decodedImage.height * scale).round();
      quality = 65;
    } else if (sizeRatio > 1.5) {
      // Közepes kép: kicsit csökkentjük
      const scale = 0.8;
      targetWidth = (decodedImage.width * scale).round();
      targetHeight = (decodedImage.height * scale).round();
      quality = 70;
    }
    
    // Maximum méret korlátozás - agresszívabb
    if (targetWidth > 1000) {
      final scale = 1000.0 / targetWidth;
      targetWidth = 1000;
      targetHeight = (targetHeight * scale).round();
    }
    if (targetHeight > 1000) {
      final scale = 1000.0 / targetHeight;
      targetHeight = 1000;
      targetWidth = (targetWidth * scale).round();
    }
    
    // Egyszerű, gyors tömörítés - max 2 iteráció
    Uint8List? compressed;
    int maxIterations = 2; // Csak 2 iteráció a gyorsaságért
    int iteration = 0;
    
    while (iteration < maxIterations && (compressed == null || compressed.length > 200 * 1024)) {
      iteration++;
      
      // Kép átméretezése (ha szükséges) - csak egyszer
      img.Image resizedImage;
      if (iteration == 1 && (targetWidth != decodedImage.width || targetHeight != decodedImage.height)) {
        resizedImage = img.copyResize(
          decodedImage,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.linear,
        );
      } else if (iteration == 1) {
        resizedImage = decodedImage;
      } else {
        // Második iterációban újra átméretezünk kisebbre
        targetWidth = (targetWidth * 0.8).round();
        targetHeight = (targetHeight * 0.8).round();
        resizedImage = img.copyResize(
          decodedImage,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.linear,
        );
        quality = 50; // Alacsony minőség második iterációban
      }
      
      // JPEG formátumban kódolás
      compressed = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: quality),
      );
      
      // Ha még mindig túl nagy, agresszívabb csökkentés
      if (compressed.length > 200 * 1024 && iteration < maxIterations) {
        quality = 40; // Nagyon alacsony minőség
        targetWidth = (targetWidth * 0.7).round();
        targetHeight = (targetHeight * 0.7).round();
      } else {
        break;
      }
    }
    
    // Ha még mindig túl nagy, akkor elfogadjuk (max 250 KB)
    if (compressed != null && compressed.length <= 250 * 1024) {
      return compressed;
    }
    
    // Ha még mindig túl nagy, akkor hiba
    if (compressed == null || compressed.length > 250 * 1024) {
      throw Exception('A kép mérete még tömörítés után is meghaladja a 250 KB-ot (${(compressed?.length ?? 0) / 1024} KB). Kérlek, válassz egy kisebb képet!');
    }
    
    return compressed;
  } catch (e) {
    rethrow;
  }
}

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
  String _currentHtmlContent = '';
  String _viewId = '';
  
  // Képfeltöltés state változók
  String? _currentImageUrl;
  bool _isUploadingImage = false;
  final ImagePicker _imagePicker = ImagePicker();
  
  // Progress dialog state változók
  double _uploadProgress = 0.0;
  String _uploadPhase = ''; // 'loading', 'compressing', 'uploading'
  
  // Tananyag megnyitás state
  bool _isContentOpen = false;

  @override
  void initState() {
    super.initState();
    _loadAllomasok();
  }

  void _setupIframe(String cim, String kulcsszo, String tartalom, {int? sorszam}) {
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
      ..style.border = 'none'
      ..style.backgroundColor = 'transparent';
    
    iframeElement.sandbox.add('allow-scripts');
    iframeElement.sandbox.add('allow-same-origin');
    iframeElement.sandbox.add('allow-forms');
    iframeElement.sandbox.add('allow-popups');
    
    // FONTOS: Teljes HTML dokumentum létrehozása CSS stílusokkal
    // PONTOSAN a dokumentumban leírt CSS-t használjuk (docs/MEMORIA_ALLOMAS_MEGJELENITES_WEB_USER_BEMUTATO.txt)
    final fullHtml = '''
<!DOCTYPE html>
<html lang="hu">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    /* ALAP STÍLUSOK */
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      font-size: 14px;
      line-height: 1.6;
      text-align: justify;
      hyphens: auto;
      padding: 2em;
      word-wrap: break-word;
      max-width: 900px;
      margin: 0 auto;
      color: #333;
      background-color: transparent;
    }

    /* CÍMEK */
    h1 {
      font-size: 1.6em;
      text-align: center;
      border-bottom: 2px solid #333;
      padding-bottom: 0.5em;
      margin-bottom: 1.5em;
    }

    h2 {
      font-size: 1.3em;
      border-bottom: 1px solid #ccc;
      padding-bottom: 5px;
      margin-top: 2em;
      color: #2c3e50;
    }

    h3 {
      font-size: 1.1em;
      margin-top: 1.2em;
      font-weight: 600;
    }

    /* SZÖVEG ELEMEK */
    p {
      margin-bottom: 0.8em;
    }

    ul, ol {
      padding-left: 20px;
      margin-bottom: 1em;
    }

    li {
      margin-bottom: 0.5em;
    }

    /* ÁLLOMÁS BADGE (SORSZÁM JELVÉNY) */
    .allomas-badge {
      display: inline-block;
      color: white;
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 0.8em;
      margin-right: 10px;
      vertical-align: middle;
      font-weight: bold;
      min-width: 20px;
      text-align: center;
    }

    /* EGYEDI SZÍNEK AZ ÁLLOMÁSOKHOZ (1-11, majd ciklikusan) */
    .badge-1 { background-color: #D32F2F; }  /* Piros */
    .badge-2 { background-color: #1976D2; }    /* Kék */
    .badge-3 { background-color: #388E3C; }  /* Zöld */
    .badge-4 { background-color: #E64A19; }  /* Narancs */
    .badge-5 { background-color: #7B1FA2; }  /* Lila */
    .badge-6 { background-color: #0097A7; }  /* Cián */
    .badge-7 { background-color: #C2185B; }  /* Rózsaszín */
    .badge-8 { background-color: #5D4037; }  /* Barna */
    .badge-9 { background-color: #FBC02D; color: #333; }  /* Sárga (sötét szöveg) */
    .badge-10 { background-color: #455A64; } /* Szürke-kék */
    .badge-11 { background-color: #303F9F; } /* Sötétkék */

    /* KULCSSZÓ STÍLUS */
    .kulcsszo {
      font-style: italic;
      color: #555;
      margin-bottom: 1em;
      display: block;
      border-left: 3px solid #ccc;
      padding-left: 10px;
    }

    /* SZÖVEG KIEMELÉSEK */
    .szin-piros {
      color: #D32F2F;
      font-weight: bold;
    }

    .szin-zold {
      color: #388E3C;
      font-weight: bold;
    }

    .szin-kek {
      color: #1976D2;
      font-weight: bold;
    }

    .hatter-sarga {
      background-color: #FFF59D;
      padding: 0.1em 0.3em;
      border-radius: 3px;
    }

    strong {
      font-weight: bold;
    }

    /* JOGSZABÁLY DOBOZ STÍLUS */
    .jogszabaly-doboz {
      background-color: #f0f4f8;
      border-left: 4px solid #2c3e50;
      padding: 10px 15px;
      margin: 15px 0;
      font-style: italic;
      font-size: 0.95em;
      color: #444;
    }

    .jogszabaly-cimke {
      font-weight: bold;
      font-style: normal;
      display: block;
      margin-bottom: 5px;
      color: #2c3e50;
      font-size: 0.9em;
      text-transform: uppercase;
    }

    /* SZEKCIÓ SZÁMOK FORMÁZÁSA - inline style támogatás */
    span[style*="background-color: #dc3545"],
    span[style*="background-color:#dc3545"],
    span[style*="background-color:rgb(220, 53, 69)"],
    span[style*="background-color: rgb(220, 53, 69)"],
    div[style*="background-color: #dc3545"],
    div[style*="background-color:#dc3545"],
    div[style*="background-color:rgb(220, 53, 69)"],
    div[style*="background-color: rgb(220, 53, 69)"],
    .szekcio-piros,
    [class*="szekcio"][class*="piros"] {
      display: inline-block !important;
      background-color: #D32F2F !important;
      color: white !important;
      padding: 4px 10px !important;
      border-radius: 4px !important;
      font-weight: bold !important;
      margin-right: 8px !important;
      font-size: 14px !important;
      min-width: 32px !important;
      text-align: center !important;
    }

    span[style*="background-color: #1976d2"],
    span[style*="background-color:#1976d2"],
    span[style*="background-color:rgb(25, 118, 210)"],
    span[style*="background-color: rgb(25, 118, 210)"],
    div[style*="background-color: #1976d2"],
    div[style*="background-color:#1976d2"],
    div[style*="background-color:rgb(25, 118, 210)"],
    div[style*="background-color: rgb(25, 118, 210)"],
    .szekcio-kek,
    [class*="szekcio"][class*="kek"] {
      display: inline-block !important;
      background-color: #1976D2 !important;
      color: white !important;
      padding: 4px 10px !important;
      border-radius: 4px !important;
      font-weight: bold !important;
      margin-right: 8px !important;
      font-size: 14px !important;
      min-width: 32px !important;
      text-align: center !important;
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

    /* RESPONZÍV DESIGN */
    @media screen and (max-width: 768px) {
      body {
        padding: 1em;
      }
    }
  </style>
</head>
<body>
  <h2>${sorszam != null && sorszam > 0 ? '<span class="allomas-badge badge-${sorszam > 11 ? ((sorszam - 1) % 11) + 1 : sorszam}">$sorszam.</span>' : ''}$cim</h2>
  ${kulcsszo.isNotEmpty ? '<span class="kulcsszo">Kulcsszó: $kulcsszo</span>' : ''}
  ${tartalom.isNotEmpty ? tartalom : '<p>Nincs tartalom.</p>'}
  <script>
    // Automatikus formázás hozzáadása, ha hiányzik
    (function() {
      function formatContent() {
        console.log('Formatting content...');
        
        // Szekció számok keresése és formázása
        const walker = document.createTreeWalker(
          document.body,
          NodeFilter.SHOW_TEXT,
          null,
          false
        );
        
        const textNodes = [];
        let node;
        while (node = walker.nextNode()) {
          textNodes.push(node);
        }
        
        textNodes.forEach(function(textNode) {
          const text = textNode.textContent;
          const parent = textNode.parentElement;
          
          if (!text || !parent) return;
          if (parent.tagName === 'SCRIPT' || parent.tagName === 'STYLE') return;
          if (parent.classList.contains('szekcio-piros') || parent.classList.contains('szekcio-kek') || parent.classList.contains('allomas-badge')) return;
          
          // Keresünk szekció számokat (pl. "1.", "2.") a szöveg elején
          const trimmed = text.trim();
          const sectionMatch = trimmed.match(/^(\\d+)\\./);
          if (sectionMatch) {
            const sectionNumber = parseInt(sectionMatch[1]);
            const badgeNumber = sectionNumber > 11 ? ((sectionNumber - 1) % 11) + 1 : sectionNumber;
            const badgeClass = 'badge-' + badgeNumber;
            
            // Ellenőrizzük, hogy már nincs-e formázva
            if (parent.querySelector('.allomas-badge')) return;
            
            // Létrehozunk egy span elemet a szekció számhoz
            const span = document.createElement('span');
            span.className = 'allomas-badge ' + badgeClass;
            span.textContent = sectionNumber + '.';
            
            // Cseréljük le a szöveget
            const remainingText = text.replace(/^\\s*\\d+\\.\\s*/, '');
            textNode.textContent = remainingText;
            parent.insertBefore(span, textNode);
            console.log('Formatted section number:', sectionNumber);
          }
        });
        
        // Kulcsszavak keresése és formázása
        const allElements = document.querySelectorAll('p, div, span, h1, h2, h3');
        allElements.forEach(function(el) {
          if (el.tagName === 'SCRIPT' || el.tagName === 'STYLE') return;
          const text = el.textContent || '';
          if (text.includes('Kulcsszó:') && !el.classList.contains('kulcsszo')) {
            el.classList.add('kulcsszo');
            console.log('Formatted keyword:', text);
          }
        });
        
        // Idézet dobozok keresése és formázása
        const divs = document.querySelectorAll('div');
        divs.forEach(function(div) {
          if (div.classList.contains('jogszabaly-doboz')) return;
          const text = div.textContent || '';
          // Ha tartalmaz jogszabály számot vagy idézetet
          if (text.match(/\\d+[:\\.]\\s*\\d+/) || text.includes('§') || text.includes('Ptk.') || text.includes('Btk.') || text.includes('Mt.')) {
            div.classList.add('jogszabaly-doboz');
            console.log('Formatted quote box:', text.substring(0, 50));
          }
        });
        
        console.log('Content formatting completed');
      }
      
      // Várunk egy kicsit, hogy a DOM betöltődjön
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', formatContent);
      } else {
        setTimeout(formatContent, 100);
        setTimeout(formatContent, 500);
        setTimeout(formatContent, 1000);
      }
    })();
  </script>
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
    // A widget.noteId az utvonalId (a fő útvonal dokumentum ID-ja)
    final utvonalID = widget.noteId;

    // Betöltjük az összes állomást a subcollection-ből
    // A struktúra: memoriapalota_allomasok/{utvonalId}/allomasok/{allomasId}
    final snapshot = await FirebaseConfig.firestore
        .collection('memoriapalota_allomasok')
        .doc(utvonalID)
        .collection('allomasok')
        .get();

    if (!mounted) return;

    // Rendezzük az állomásokat allomasSorszam alapján
    final allomasok = snapshot.docs.toList();
    allomasok.sort((a, b) {
      final sorszamA = a.data()['allomasSorszam'] as int? ?? 0;
      final sorszamB = b.data()['allomasSorszam'] as int? ?? 0;
      return sorszamA.compareTo(sorszamB);
    });

    // Beállítjuk az állomásokat, de még nem állítjuk le a loading flag-et
    setState(() {
      _allomasok = allomasok;
      _currentIndex = 0;
      // Még nem állítjuk le a loading flag-et, várjuk meg az iframe betöltését
    });

    // Megjelenítjük az első állomást (ez már betölti a képet is)
    await _displayCurrentAllomas();
    
    // Várunk egy kicsit, hogy az iframe betöltődhessen
    // Az iframe betöltése aszinkron, ezért egy rövid késleltetést használunk
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    
    // Most már beállíthatjuk, hogy a loading screen eltűnjön
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _displayCurrentAllomas() async {
    if (_allomasok.isEmpty || _currentIndex < 0 || _currentIndex >= _allomasok.length) {
      return;
    }

    final currentAllomas = _allomasok[_currentIndex];
    final data = currentAllomas.data() as Map<String, dynamic>;
    
    // Az állomások adatai
    final cim = data['cim'] as String? ?? 'Állomás';
    final kulcsszo = data['kulcsszo'] as String? ?? '';
    final tartalom = data['tartalom'] as String? ?? '';
    final sorszam = data['allomasSorszam'] as int?;
    
    // Új iframe-et hozunk létre az új tartalommal (teljes HTML dokumentummal)
    _setupIframe(cim, kulcsszo, tartalom, sorszam: sorszam);
    
    // Betöltjük a felhasználó képét az aktuális állomáshoz és megvárjuk
    await _loadUserImage();
    
    // Frissítjük a tartalmat és újraépítjük a view-t
    if (mounted) {
      setState(() {
        _currentHtmlContent = tartalom.isNotEmpty ? tartalom : '<p>Nincs tartalom.</p>';
      });
    }
  }
  
  // Felhasználó képének betöltése
  Future<void> _loadUserImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _allomasok.isEmpty || _currentIndex < 0 || _currentIndex >= _allomasok.length) {
      setState(() {
        _currentImageUrl = null;
      });
      return;
    }
    
    try {
      final currentAllomas = _allomasok[_currentIndex];
      final allomasId = currentAllomas.id;
      final utvonalId = widget.noteId;
      
      final imageDoc = await FirebaseConfig.firestore
          .collection('memoriapalota_allomasok')
          .doc(utvonalId)
          .collection('allomasok')
          .doc(allomasId)
          .collection('userImages')
          .doc(user.uid)
          .get();
      
      if (imageDoc.exists && mounted) {
        final imageUrl = imageDoc.data()?['imageUrl'] as String?;
        setState(() {
          _currentImageUrl = imageUrl;
          // Ha van kép, alapállapotban a kép látszik (tananyag bezárva)
          // Ha nincs kép, alapállapotban a tananyag látszik
          _isContentOpen = (imageUrl == null);
        });
      } else if (mounted) {
        setState(() {
          _currentImageUrl = null;
          // Ha nincs kép, alapállapotban a tananyag látszik
          _isContentOpen = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentImageUrl = null;
          // Ha nincs kép, alapállapotban a tananyag látszik
          _isContentOpen = true;
        });
      }
    }
  }
  
  // Kép választási dialog megjelenítése
  Future<void> _showImagePickerDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Be kell jelentkezned a képfeltöltéshez!')),
      );
      return;
    }
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kép kiválasztása'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!kIsWeb)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _pickImageFromCamera();
                },
                icon: const Icon(Icons.camera_alt),
                label: const Text('Fotó készítése'),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                debugPrint('=== TextButton onPressed START ===');
                
                // Bezárjuk a dialógust AZONNAL
                Navigator.of(dialogContext).pop();
                debugPrint('Dialog closed');
                
                // Várunk egy kicsit, hogy a dialógus biztosan bezáródjon
                await Future.delayed(const Duration(milliseconds: 300));
                
                if (!mounted) {
                  debugPrint('Not mounted after delay');
                  return;
                }
                
                // Web-en közvetlenül a file_selector-t hívjuk meg
                if (kIsWeb) {
                  debugPrint('Web: Starting file selection directly...');
                  
                  try {
                    debugPrint('Opening file selector...');
                    const typeGroup = XTypeGroup(
                      label: 'Képek',
                      extensions: ['jpg', 'jpeg', 'png', 'webp'],
                    );
                    
                    final file = await openFile(acceptedTypeGroups: [typeGroup]);
                    debugPrint('File selector returned: ${file?.name ?? "NULL"}');
                    
                    if (file == null) {
                      debugPrint('User cancelled');
                      return;
                    }
                    
                    if (!mounted) return;
                    
                    debugPrint('Reading file bytes...');
                    final bytes = await file.readAsBytes();
                    debugPrint('File bytes read: ${bytes.length} bytes');
                    
                    if (bytes.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('A fájl üres!'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return;
                    }
                    
                    if (!mounted) return;
                    
                    // Lokális blob URL létrehozása az optimistic UI-hoz
                    final localImageUrl = _createLocalImageUrl(bytes);
                    
                    debugPrint('Starting image processing...');
                    await _processAndUploadImage(bytes, localImageUrl: localImageUrl);
                    debugPrint('Image processing completed');
                    
                  } catch (e, stackTrace) {
                    debugPrint('ERROR in file selector: $e');
                    debugPrint('Stack trace: $stackTrace');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Hiba: $e'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                } else {
                  // Mobil: image_picker
                  if (mounted) {
                    await _pickImageFromFile();
                  }
                }
                
                debugPrint('=== TextButton onPressed END ===');
              },
              icon: const Icon(Icons.photo_library),
              label: kIsWeb 
                  ? const Text('Fájlból választás')
                  : const Text('Galériából választás'),
            ),
            if (_currentImageUrl != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _deleteImage();
                },
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Kép törlése', style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  // Web fájl kiválasztás közvetlenül (dialógus nélkül)
  Future<void> _pickImageFromFileWebDirect() async {
    debugPrint('=== _pickImageFromFileWebDirect START ===');
    
    if (!mounted) {
      debugPrint('ERROR: Widget not mounted');
      return;
    }
    
    try {
      debugPrint('Opening file selector directly...');
      const typeGroup = XTypeGroup(
        label: 'Képek',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      debugPrint('File selector returned: ${file?.name ?? "NULL"}');
      
      if (file == null) {
        debugPrint('User cancelled');
        return;
      }
      
      if (!mounted) {
        debugPrint('ERROR: Widget not mounted after file selection');
        return;
      }
      
      debugPrint('Reading file bytes...');
      final bytes = await file.readAsBytes();
      debugPrint('File bytes read: ${bytes.length} bytes');
      
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A fájl üres!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      if (!mounted) return;
      
      // Lokális blob URL létrehozása az optimistic UI-hoz
      final localImageUrl = _createLocalImageUrl(bytes);
      
      debugPrint('Starting image processing...');
      await _processAndUploadImage(bytes, localImageUrl: localImageUrl);
      debugPrint('Image processing completed');
      
    } catch (e, stackTrace) {
      debugPrint('ERROR in file selector: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  // Mobil kamera megnyitása
  Future<void> _pickImageFromCamera() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kamera csak mobil eszközökön érhető el!')),
      );
      return;
    }
    
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 70, // Mobil eszközön alacsonyabb minőség a gyorsabb feldolgozásért
      );
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        await _processAndUploadImage(bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a kép készítésekor: $e')),
        );
      }
    }
  }
  
  // Mobil galéria kiválasztás (image_picker)
  Future<void> _pickImageFromFile() async {
    debugPrint('=== _pickImageFromFile START ===');
    debugPrint('kIsWeb: $kIsWeb');
    
    if (!mounted) {
      debugPrint('ERROR: Widget not mounted, returning');
      return;
    }
    
    try {
      Uint8List? bytes;
      
      // Egységesen image_picker-t használunk web-en és mobilon is
      debugPrint('Opening image picker (gallery)...');
      
      try {
        final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: kIsWeb ? 85 : 70, // Mobil eszközön alacsonyabb minőség a gyorsabb feldolgozásért
        );
        
        debugPrint('Image picker returned: ${image?.path ?? "NULL"}');
        
        if (image == null) {
          debugPrint('User cancelled image selection');
          return;
        }
        
        debugPrint('Image path: ${image.path}');
        debugPrint('Image name: ${image.name}');
        
        if (!mounted) {
          debugPrint('ERROR: Widget not mounted after image selection');
          return;
        }
        
        // Azonnal mutassunk üzenetet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kép betöltése...'),
            duration: Duration(seconds: 2),
          ),
        );
        
        debugPrint('Reading image bytes...');
        bytes = await image.readAsBytes();
        debugPrint('Image bytes read: ${bytes.length} bytes');
        
      } catch (e, stackTrace) {
        debugPrint('ERROR in image picker: $e');
        debugPrint('Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hiba a kép kiválasztásakor: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      
      if (bytes.isEmpty) {
        debugPrint('ERROR: Bytes is empty!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A kiválasztott fájl üres!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      if (!mounted) {
        debugPrint('ERROR: Widget not mounted before processing');
        return;
      }
      
      debugPrint('=== Starting _processAndUploadImage ===');
      debugPrint('Bytes length: ${bytes.length}');
      
      await _processAndUploadImage(bytes);
      
      debugPrint('=== _processAndUploadImage COMPLETED ===');
      
    } catch (e, stackTrace) {
      debugPrint('=== FATAL ERROR in _pickImageFromFile ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Váratlan hiba: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
    
    debugPrint('=== _pickImageFromFile END ===');
  }
  
  // Lokális data URL létrehozása web-en (optimistic UI)
  String? _createLocalImageUrl(Uint8List imageBytes) {
    if (!kIsWeb) return null;
    
    try {
      // Base64 kódolás a data URL-hez
      final base64 = base64Encode(imageBytes);
      // MIME típus meghatározása az első bájtok alapján
      String mimeType = 'image/jpeg';
      if (imageBytes.length >= 4) {
        if (imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47) {
          mimeType = 'image/png';
        } else if (imageBytes[0] == 0x47 && imageBytes[1] == 0x49 && imageBytes[2] == 0x46) {
          mimeType = 'image/gif';
        } else if (imageBytes.length >= 12 && 
                   imageBytes[0] == 0x52 && imageBytes[1] == 0x49 && 
                   imageBytes[2] == 0x46 && imageBytes[3] == 0x46 &&
                   imageBytes[8] == 0x57 && imageBytes[9] == 0x45 && 
                   imageBytes[10] == 0x42 && imageBytes[11] == 0x50) {
          mimeType = 'image/webp';
        }
      }
      return 'data:$mimeType;base64,$base64';
    } catch (e) {
      debugPrint('Hiba a lokális kép URL létrehozásakor: $e');
      return null;
    }
  }
  
  // Progress dialog megjelenítése
  void _showUploadProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false, // Nem lehet bezárni
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            // Animált progress bar - folyamatosan mozog, még akkor is, ha a tényleges progress nem frissül
            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _uploadPhase == 'loading'
                        ? 'Kép betöltése...'
                        : _uploadPhase == 'compressing'
                            ? 'Kép tömörítése...'
                            : _uploadPhase == 'uploading'
                                ? 'Kép feltöltése...'
                                : 'Feldolgozás...',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  // Animált progress bar - ha nincs konkrét érték, akkor automatikusan animál
                  LinearProgressIndicator(
                    value: _uploadProgress > 0 ? _uploadProgress : null,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _uploadProgress > 0
                        ? '${(_uploadProgress * 100).toStringAsFixed(0)}%'
                        : 'Feldolgozás...',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
  
  // Progress dialog frissítése
  void _updateUploadProgress(double progress, String phase) {
    if (mounted) {
      setState(() {
        _uploadProgress = progress;
        _uploadPhase = phase;
      });
    }
  }
  
  // Kép tömörítése és feltöltése - optimalizált verzió optimistic UI-val
  Future<void> _processAndUploadImage(Uint8List imageBytes, {String? localImageUrl}) async {
    debugPrint('_processAndUploadImage called, bytes length: ${imageBytes.length}');
    
    if (imageBytes.isEmpty) {
      debugPrint('Image bytes is empty!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A kép üres!')),
        );
      }
      return;
    }
    
    if (!mounted) {
      debugPrint('Widget not mounted, returning');
      return;
    }
    
    // Optimistic UI: azonnal megjelenítjük a képet lokálisan
    String? tempUrl = localImageUrl ?? _createLocalImageUrl(imageBytes);
    String? previousImageUrl = _currentImageUrl;
    
    setState(() {
      _isUploadingImage = true;
      if (tempUrl != null) {
        _currentImageUrl = tempUrl; // Azonnal megjelenítjük (optimistic UI)
      }
      _uploadProgress = 0.0;
      _uploadPhase = 'loading';
    });
    
    // Progress dialog megjelenítése
    _showUploadProgressDialog();
    
    // Animált progress - folyamatosan növekszik, még akkor is, ha a tényleges művelet blokkoló
    StreamSubscription? progressTimer;
    try {
      double simulatedProgress = 0.0;
      progressTimer = Stream.periodic(const Duration(milliseconds: 100), (i) {
        simulatedProgress = (i * 0.01).clamp(0.0, 0.95); // Max 95%-ig, hogy legyen hely a tényleges progressnek
        return simulatedProgress;
      }).listen((progress) {
        if (mounted && progress > _uploadProgress) {
          _updateUploadProgress(progress, _uploadPhase);
        }
      });
      _updateUploadProgress(0.1, 'loading');
      debugPrint('Starting compression, original size: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');
      
      // Kép tömörítése 200 KB alá
      _updateUploadProgress(0.33, 'compressing');
      
      // Timeout hozzáadása mobil eszközön (15 másodperc - rövidebb, hogy gyorsabban jelezzen hibát)
      final compressedBytes = await _compressImage(imageBytes).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('A kép tömörítése túl sokáig tartott. Kérlek, próbálj egy kisebb képet vagy újraindítsd az alkalmazást!');
        },
      );
      
      debugPrint('Compression done, compressed size: ${compressedBytes != null ? (compressedBytes.length / 1024).toStringAsFixed(1) : "null"} KB');
      
      if (compressedBytes == null) {
        throw Exception('Nem sikerült tömöríteni a képet');
      }
      
      // Méret ellenőrzés - 2 MB-ig engedjük
      if (compressedBytes.length > 2 * 1024 * 1024) {
        throw Exception('A kép mérete túl nagy (${(compressedBytes.length / 1024 / 1024).toStringAsFixed(1)} MB). Kérlek, válassz kisebb képet!');
      }
      
      _updateUploadProgress(0.66, 'uploading');
      debugPrint('Starting upload to Firebase Storage');
      
      // Feltöltés
      await _uploadImageToStorage(compressedBytes);
      
      _updateUploadProgress(1.0, 'uploading');
      debugPrint('Upload completed successfully');
      
      // Progress timer leállítása
      progressTimer.cancel();
      
      // Progress dialog bezárása
      if (mounted) {
        Navigator.of(context).pop(); // Progress dialog bezárása
      }
      
      // Sikeres feltöltés után frissítjük a state-et
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
          // _currentImageUrl már frissítve van az _uploadImageToStorage-ban
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kép sikeresen feltöltve!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      // Progress timer leállítása hiba esetén is
      if (progressTimer != null) {
        progressTimer.cancel();
      }
      debugPrint('=== Hiba a képfeltöltéskor ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Progress dialog bezárása
      if (mounted) {
        try {
          Navigator.of(context).pop(); // Progress dialog bezárása
        } catch (navError) {
          debugPrint('Error closing dialog: $navError');
        }
      }
      
      // Hiba esetén visszaállítjuk az előző állapotot
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
          _currentImageUrl = previousImageUrl; // Visszaállítjuk az előző képet
        });
        
        // Részletes hibaüzenet megjelenítése
        String errorMessage = 'Hiba a képfeltöltéskor';
        if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
          errorMessage = 'A művelet túl sokáig tartott. Kérlek, próbáld újra!';
        } else if (e.toString().contains('permission') || e.toString().contains('Permission')) {
          errorMessage = 'Nincs jogosultság a képfeltöltéshez. Ellenőrizd a beállításokat!';
        } else if (e.toString().contains('network') || e.toString().contains('Network')) {
          errorMessage = 'Hálózati hiba. Ellenőrizd az internetkapcsolatot!';
        } else {
          errorMessage = 'Hiba: ${e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Részletek',
              textColor: Colors.white,
              onPressed: () {
                // További részletek megjelenítése (opcionális)
                debugPrint('Full error details: $e');
              },
            ),
          ),
        );
      }
    }
  }
  
  // Kép tömörítése 200 KB alá - gyorsított verzió
  Future<Uint8List?> _compressImage(Uint8List imageBytes) async {
    // Ha már 200 KB alatt van, visszaadja
    if (imageBytes.length <= 200 * 1024) {
      return imageBytes;
    }
    
    try {
      debugPrint('Starting image compression, platform: ${kIsWeb ? "web" : "mobile"}, size: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');
      
      Uint8List? compressed;
      
      if (kIsWeb) {
        // Web-en a compute nem mindig működik megfelelően
        // Kis késleltetés, hogy az UI frissülhessen
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Aszinkron módon futtatjuk, hogy ne blokkolja a UI-t
        compressed = await Future(() => _compressImageInIsolate(imageBytes));
      } else {
        // Mobil eszközön először próbáljuk a compute-ot, de ha nem működik, közvetlenül futtatjuk
        debugPrint('Using compute for mobile compression...');
        try {
          // Kis késleltetés, hogy az UI frissülhessen
          await Future.delayed(const Duration(milliseconds: 100));
          compressed = await compute(_compressImageInIsolate, imageBytes).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Tömörítés timeout');
            },
          );
        } catch (e) {
          debugPrint('Compute failed or timeout, trying direct compression: $e');
          // Ha a compute nem működik vagy timeout, próbáljuk közvetlenül
          // Kis késleltetés, hogy az UI frissülhessen
          await Future.delayed(const Duration(milliseconds: 100));
          compressed = await Future(() => _compressImageInIsolate(imageBytes)).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Tömörítés timeout (közvetlen)');
            },
          );
        }
      }
      
      debugPrint('Compression completed: ${compressed?.length ?? 0} bytes (${(compressed?.length ?? 0) / 1024} KB)');
      return compressed;
    } catch (e, stackTrace) {
      debugPrint('Hiba a tömörítéskor: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  // Firebase Storage-ba feltöltés
  Future<void> _uploadImageToStorage(Uint8List imageBytes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Nincs bejelentkezve felhasználó!');
    }
    
    if (_allomasok.isEmpty || _currentIndex < 0 || _currentIndex >= _allomasok.length) {
      throw Exception('Nincs kiválasztott állomás!');
    }
    
    final currentAllomas = _allomasok[_currentIndex];
    final allomasId = currentAllomas.id;
    final utvonalId = widget.noteId;
    
    debugPrint('Uploading image to Storage: memoriapalota_images/$utvonalId/$allomasId/${user.uid}/image.jpg');
    debugPrint('Image size: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');
    
    // Régi kép törlése (ha van)
    if (_currentImageUrl != null && _currentImageUrl!.startsWith('https://')) {
      try {
        debugPrint('Deleting old image: $_currentImageUrl');
        final oldRef = FirebaseStorage.instance.refFromURL(_currentImageUrl!);
        await oldRef.delete().timeout(const Duration(seconds: 5));
        debugPrint('Old image deleted successfully');
      } catch (e) {
        debugPrint('Could not delete old image (continuing anyway): $e');
        // Ha nem sikerül törölni, folytatjuk
      }
    }
    
    // Új kép feltöltése
    final ref = FirebaseStorage.instance.ref(
      'memoriapalota_images/$utvonalId/$allomasId/${user.uid}/image.jpg',
    );
    
    debugPrint('Starting upload to Firebase Storage...');
    try {
      await ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('A képfeltöltés túl sokáig tartott. Kérlek, próbáld újra!');
        },
      );
      debugPrint('Upload to Storage completed');
    } catch (e) {
      debugPrint('Error uploading to Storage: $e');
      rethrow;
    }
    
    debugPrint('Getting download URL...');
    final imageUrl = await ref.getDownloadURL().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('Nem sikerült lekérni a kép URL-jét. Kérlek, próbáld újra!');
      },
    );
    debugPrint('Download URL obtained: $imageUrl');
    
    // Firestore-ba mentés
    debugPrint('Saving to Firestore...');
    await _saveImageUrlToFirestore(imageUrl);
    debugPrint('Saved to Firestore successfully');
    
    // State frissítése
    if (mounted) {
      setState(() {
        _currentImageUrl = imageUrl;
      });
    }
  }
  
  // Firestore-ba mentés
  Future<void> _saveImageUrlToFirestore(String imageUrl) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Nincs bejelentkezve felhasználó!');
    }
    
    if (_allomasok.isEmpty || _currentIndex < 0 || _currentIndex >= _allomasok.length) {
      throw Exception('Nincs kiválasztott állomás!');
    }
    
    final currentAllomas = _allomasok[_currentIndex];
    final allomasId = currentAllomas.id;
    final utvonalId = widget.noteId;
    
    debugPrint('Saving to Firestore: memoriapalota_allomasok/$utvonalId/allomasok/$allomasId/userImages/${user.uid}');
    
    try {
      await FirebaseConfig.firestore
          .collection('memoriapalota_allomasok')
          .doc(utvonalId)
          .collection('allomasok')
          .doc(allomasId)
          .collection('userImages')
          .doc(user.uid)
          .set({
            'imageUrl': imageUrl,
            'uploadedAt': Timestamp.now(),
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('A Firestore mentés túl sokáig tartott. Kérlek, próbáld újra!');
            },
          );
      debugPrint('Firestore save completed');
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
      rethrow;
    }
  }
  
  // Kép törlése
  Future<void> _deleteImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentImageUrl == null) {
      return;
    }
    
    setState(() {
      _isUploadingImage = true;
    });
    
    try {
      // Storage-ból törlés
      try {
        final ref = FirebaseStorage.instance.refFromURL(_currentImageUrl!);
        await ref.delete();
      } catch (e) {
        // Ha nem sikerül törölni, folytatjuk
      }
      
      // Firestore-ból törlés
      if (_allomasok.isNotEmpty && _currentIndex >= 0 && _currentIndex < _allomasok.length) {
        final currentAllomas = _allomasok[_currentIndex];
        final allomasId = currentAllomas.id;
        final utvonalId = widget.noteId;
        
        await FirebaseConfig.firestore
            .collection('memoriapalota_allomasok')
            .doc(utvonalId)
            .collection('allomasok')
            .doc(allomasId)
            .collection('userImages')
            .doc(user.uid)
            .delete();
      }
      
      if (mounted) {
        setState(() {
          _currentImageUrl = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kép sikeresen törölve!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a kép törlésekor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }
  
  // Tartalom overlay megjelenítése
  void _showContentOverlayDialog() {
    if (_currentHtmlContent.isEmpty || _viewId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nincs megjeleníthető tartalom!')),
      );
      return;
    }
    
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(0),
          ),
          child: Column(
            children: [
              // Fejléc
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tananyag tartalma',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Tartalom
              Expanded(
                child: kIsWeb && _viewId.isNotEmpty
                    ? HtmlElementView(
                        key: ValueKey('overlay_$_viewId'),
                        viewType: _viewId,
                      )
                    : const Center(
                        child: Text('Nem sikerült betölteni a tartalmat'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _goToPrevious() async {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _isContentOpen = false; // Bezárjuk a tananyagot továbblépéskor
      });
      await _displayCurrentAllomas();
    }
  }

  Future<void> _goToNext() async {
    if (_currentIndex < _allomasok.length - 1) {
      setState(() {
        _currentIndex++;
        _isContentOpen = false; // Bezárjuk a tananyagot továbblépéskor
      });
      await _displayCurrentAllomas();
    }
  }
  
  void _toggleContent() {
    debugPrint('_toggleContent called - current state: _isContentOpen=$_isContentOpen');
    setState(() {
      _isContentOpen = !_isContentOpen;
      debugPrint('_toggleContent - new state: _isContentOpen=$_isContentOpen');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _allomasok.isEmpty) {
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
              '$allomasSorszam/${_allomasok.length}',
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
        actions: [
          // Bezárás gomb (csak ha van kép és a tananyag nyitva van)
          if (_currentImageUrl != null && _isContentOpen)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                debugPrint('Close button in AppBar pressed');
                _toggleContent();
              },
              tooltip: 'Tananyag bezárása',
            ),
          // Foto ikon gomb (képfeltöltés)
          IconButton(
            icon: _isUploadingImage
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate),
            onPressed: _isUploadingImage ? null : () {
              debugPrint('=== IconButton onPressed START ===');
              if (kIsWeb) {
                // Web-en közvetlenül a file_selector-t hívjuk meg, dialógus nélkül
                _pickImageFromFileWebDirect();
              } else {
                _showImagePickerDialog();
              }
            },
            tooltip: 'Kép feltöltése',
          ),
          // Tartalom megtekintése gomb (csak ha nincs kép, vagy overlay dialog-hoz)
          if (_currentImageUrl == null)
            IconButton(
              icon: const Icon(Icons.menu_book),
              onPressed: _showContentOverlayDialog,
              tooltip: 'Tartalom megtekintése',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Kép háttérben (ha van)
          if (_currentImageUrl != null)
            Positioned.fill(
              child: Container(
                color: Colors.white,
                child: Stack(
                  children: [
                    Center(
                      child: Image.network(
                        _currentImageUrl!,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('Image load error: $error');
                          return Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Nem sikerült betölteni a képet',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                  ),
                                  if (kIsWeb)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        '(CORS hiba vagy hozzáférési hiba)',
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  // Hiba részletek és URL megjelenítése
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: SelectableText(
                                      'Hiba: $error\n\nKattints az Újrapróbálás gombra!',
                                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        if (_currentImageUrl != null) {
                                          // Cache busting timestamp hozzáadása az URL-hez
                                          final timestamp = DateTime.now().millisecondsSinceEpoch;
                                          if (_currentImageUrl!.contains('cache_bust=')) {
                                            _currentImageUrl = _currentImageUrl!.replaceAll(
                                              RegExp(r'cache_bust=\d+'), 
                                              'cache_bust=$timestamp'
                                            );
                                          } else {
                                            final separator = _currentImageUrl!.contains('?') ? '&' : '?';
                                            _currentImageUrl = '$_currentImageUrl${separator}cache_bust=$timestamp';
                                          }
                                        }
                                      });
                                    },
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Újrapróbálás (Cache törlés)'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Törlés gomb a kép jobb felső sarkában
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Material(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _isUploadingImage ? null : () async {
                            // Megerősítő dialógus
                            final shouldDelete = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Kép törlése'),
                                content: const Text('Biztosan törölni szeretnéd ezt a képet?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Mégse'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Törlés'),
                                  ),
                                ],
                              ),
                            );
                            
                            if (shouldDelete == true && mounted) {
                              await _deleteImage();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: _isUploadingImage
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // HTML tartalom előtérben félig átlátszó háttérrel (ha meg van nyitva VAGY nincs kép)
          if (_isContentOpen || _currentImageUrl == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 80, // Helyet hagyunk a navigációs gomboknak
              child: GestureDetector(
                onTap: _currentImageUrl != null ? _toggleContent : null, // Csak ha van kép, bezárható kattintással
                child: Container(
                  decoration: BoxDecoration(
                    color: _currentImageUrl != null 
                        ? Colors.white.withValues(alpha: 0.85) // Félig átlátszó fehér, ha van kép
                        : Colors.white, // Fehér háttér, ha nincs kép
                  ),
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
              ),
            )
          else
            // Alapállapot: csak a kép és egy gomb a tananyag megnyitásához (ha van kép)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 80,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _toggleContent,
                      icon: const Icon(Icons.menu_book),
                      label: const Text(
                        'Tananyag megnyitása',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          // Navigációs gombok alul
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
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
          ),
        ],
      ),
    );
  }
}

