import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../core/firebase_config.dart';

// Top-level függvény a compute-hoz
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
    
    // Kezdeti értékek
    int targetWidth = decodedImage.width > 1200 ? 1200 : decodedImage.width;
    int targetHeight = decodedImage.height > 1200 ? 1200 : decodedImage.height;
    int quality = 80;
    Uint8List? compressed;
    
    // Iteratív tömörítés, amíg nem lesz 200 KB alatt
    int maxIterations = 8;
    int iteration = 0;
    
    while (iteration < maxIterations && (compressed == null || compressed.length > 200 * 1024)) {
      iteration++;
      
      // Kép átméretezése
      img.Image resizedImage;
      if (targetWidth != decodedImage.width || targetHeight != decodedImage.height) {
        resizedImage = img.copyResize(
          decodedImage,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.linear,
        );
      } else {
        resizedImage = decodedImage;
      }
      
      // JPEG formátumban kódolás minőség csökkentéssel
      compressed = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: quality),
      );
      
      // Ha még mindig túl nagy, csökkentjük a minőséget vagy a méretet
      if (compressed.length > 200 * 1024) {
        if (quality > 50) {
          // Először csökkentjük a minőséget
          quality -= 10;
        } else {
          // Ha a minőség már alacsony, csökkentjük a méretet
          targetWidth = (targetWidth * 0.8).round();
          targetHeight = (targetHeight * 0.8).round();
          quality = 70; // Reset minőség
        }
      } else {
        break;
      }
    }
    
    // Ha még mindig túl nagy, akkor hiba
    if (compressed == null || compressed.length > 200 * 1024) {
      throw Exception('A kép mérete még tömörítés után is meghaladja a 200 KB-ot (${(compressed?.length ?? 0) / 1024} KB). Kérlek, válassz egy kisebb képet!');
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
  String? _errorMessage;
  String _currentHtmlContent = '';
  String _viewId = '';
  
  // Képfeltöltés state változók
  String? _currentImageUrl;
  bool _isUploadingImage = false;
  final ImagePicker _imagePicker = ImagePicker();
  
  // Tananyag megnyitás state
  bool _isContentOpen = false;

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
      ..style.border = 'none'
      ..style.backgroundColor = 'transparent';
    
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
    html {
      background-color: transparent;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      font-size: 14px;
      line-height: 1.6;
      color: #333;
      padding: 20px;
      margin: 0;
      background-color: transparent;
      text-align: justify;
    }
    .content-wrapper {
      background-color: #fff;
      padding: 20px;
      border-radius: 8px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      max-width: 100%;
      margin: 0 auto;
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
  <div class="content-wrapper">
    $tartalom
  </div>
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

      // Megjelenítjük az első állomást (ez már betölti a képet is)
      await _displayCurrentAllomas();
    } catch (e) {
      setState(() {
        _errorMessage = 'Hiba történt az állomások betöltésekor: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _displayCurrentAllomas() async {
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
    
    // Betöltjük a felhasználó képét az aktuális állomáshoz és megvárjuk
    await _loadUserImage();
    
    // Frissítjük a tartalmat és újraépítjük a view-t
    if (mounted) {
      setState(() {
        _currentHtmlContent = content;
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
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kép betöltése...')),
                    );
                    
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
                    
                    debugPrint('Starting image processing...');
                    await _processAndUploadImage(bytes);
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
              label: Text(kIsWeb ? 'Fájlból választás' : 'Galériából választás'),
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kép betöltése...')),
      );
      
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
      
      debugPrint('Starting image processing...');
      await _processAndUploadImage(bytes);
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
        imageQuality: 85,
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
          imageQuality: 85,
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
  
  // Kép tömörítése és feltöltése
  Future<void> _processAndUploadImage(Uint8List imageBytes) async {
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
    
    setState(() {
      _isUploadingImage = true;
    });
    
    try {
      debugPrint('Starting compression, original size: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kép tömörítése... (${(imageBytes.length / 1024).toStringAsFixed(1)} KB)')),
        );
      }
      
      // Kép tömörítése 200 KB alá
      final compressedBytes = await _compressImage(imageBytes);
      
      debugPrint('Compression done, compressed size: ${compressedBytes != null ? (compressedBytes.length / 1024).toStringAsFixed(1) : "null"} KB');
      
      if (compressedBytes == null) {
        throw Exception('Nem sikerült tömöríteni a képet');
      }
      
      // Méret ellenőrzés
      if (compressedBytes.length > 200 * 1024) {
        throw Exception('A kép mérete még tömörítés után is meghaladja a 200 KB-ot (${(compressedBytes.length / 1024).toStringAsFixed(1)} KB)');
      }
      
      debugPrint('Starting upload to Firebase Storage');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kép feltöltése... (${(compressedBytes.length / 1024).toStringAsFixed(1)} KB)')),
        );
      }
      
      // Feltöltés
      await _uploadImageToStorage(compressedBytes);
      
      debugPrint('Upload completed successfully');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kép sikeresen feltöltve!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Hiba a képfeltöltéskor: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiba a képfeltöltéskor: $e'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
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
  
  // Kép tömörítése 200 KB alá
  Future<Uint8List?> _compressImage(Uint8List imageBytes) async {
    // Ha már 200 KB alatt van, visszaadja
    if (imageBytes.length <= 200 * 1024) {
      return imageBytes;
    }
    
    try {
      // Web-en a compute nem mindig működik megfelelően, ez okozhat problémákat
      // Közvetlenül futtatjuk a tömörítést, de kis késleltetéssel, hogy az UI frissülhessen
      debugPrint('Starting image compression directly...');
      
      // Kis késleltetés, hogy az UI frissülhessen
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Aszinkron módon futtatjuk, hogy ne blokkolja a UI-t
      final compressed = await Future(() => _compressImageInIsolate(imageBytes));
      
      debugPrint('Compression completed: ${compressed?.length ?? 0} bytes');
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
    if (user == null || _allomasok.isEmpty || _currentIndex < 0 || _currentIndex >= _allomasok.length) {
      return;
    }
    
    final currentAllomas = _allomasok[_currentIndex];
    final allomasId = currentAllomas.id;
    final utvonalId = widget.noteId;
    
    // Régi kép törlése (ha van)
    if (_currentImageUrl != null) {
      try {
        final oldRef = FirebaseStorage.instance.refFromURL(_currentImageUrl!);
        await oldRef.delete();
      } catch (e) {
        // Ha nem sikerül törölni, folytatjuk
      }
    }
    
    // Új kép feltöltése
    final ref = FirebaseStorage.instance.ref(
      'memoriapalota_images/$utvonalId/$allomasId/${user.uid}/image.jpg',
    );
    
    await ref.putData(imageBytes);
    final imageUrl = await ref.getDownloadURL();
    
    // Firestore-ba mentés
    await _saveImageUrlToFirestore(imageUrl);
    
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
    if (user == null || _allomasok.isEmpty || _currentIndex < 0 || _currentIndex >= _allomasok.length) {
      return;
    }
    
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
        .set({
          'imageUrl': imageUrl,
          'uploadedAt': Timestamp.now(),
        });
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
                      color: Colors.black.withOpacity(0.1),
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
                          return const Center(
                            child: Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 48,
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
                        ? Colors.white.withOpacity(0.85) // Félig átlátszó fehér, ha van kép
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
          ),
        ],
      ),
    );
  }
}

