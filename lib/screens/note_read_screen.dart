import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import 'dart:js_interop';

import '../widgets/audio_preview_player.dart';
import '../widgets/breadcrumb_navigation.dart';
import '../utils/filter_storage.dart';
import '../utils/hyphenation.dart'; // Hyphenation import

/// Felhasználói (csak olvasás) nézet szöveges jegyzetekhez.
///
/// - Csak megjelenítés és hanganyag lejátszás
/// - Nincsenek admin műveletek
class NoteReadScreen extends StatefulWidget {
  final String noteId;
  final String? from;

  const NoteReadScreen({super.key, required this.noteId, this.from});

  @override
  State<NoteReadScreen> createState() => _NoteReadScreenState();
}

class _NoteReadScreenState extends State<NoteReadScreen> {
  DocumentSnapshot? _noteSnapshot;
  final int _currentPageIndex = 0;
  String _viewId = '';
  bool _hasContent = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    debugPrint('🔵 [_loadNote] START - noteId: ${widget.noteId}');

    final snapshot = await FirebaseFirestore.instance
        .collection('notes')
        .doc(widget.noteId)
        .get();

    if (!mounted) {
      debugPrint('🔴 [_loadNote] NOT MOUNTED - returning');
      return;
    }

    final data = snapshot.data();
    String? htmlContent;
    bool isPreProcessed = false;

    if (data != null) {
      final processedPages = data['processed_pages'] as List<dynamic>? ?? [];
      final pages = data['pages'] as List<dynamic>? ?? [];

      debugPrint(
          '🔵 [_loadNote] Pages count: ${pages.length}, Processed count: ${processedPages.length}');

      if (processedPages.isNotEmpty &&
          processedPages.length > _currentPageIndex &&
          (processedPages[_currentPageIndex] as String?)?.isNotEmpty == true) {
        htmlContent = processedPages[_currentPageIndex] as String;
        isPreProcessed = true;
        debugPrint('🔵 [_loadNote] Loaded content from processed_pages');
      } else if (pages.isNotEmpty) {
        htmlContent = pages[_currentPageIndex] as String? ?? '';
        debugPrint('🔵 [_loadNote] Loaded content from pages (raw)');
      }

      if (htmlContent != null) {
        debugPrint('🔵 [_loadNote] HTML content length: ${htmlContent.length}');
      }
    }

    if (htmlContent != null && htmlContent.isNotEmpty) {
      String contentToRender = htmlContent;

      if (!isPreProcessed) {
        debugPrint('🟢 [_loadNote] Calling hyphenateHtmlHu');
        contentToRender = await hyphenateHtmlHu(htmlContent);
      } else {
        debugPrint('🟢 [_loadNote] Skipping hyphenation (pre-processed)');
      }

      debugPrint('🟢 [_loadNote] Calling _setupIframe');
      _setupIframe(contentToRender);
    } else {
      debugPrint('🔴 [_loadNote] No HTML content - NOT calling _setupIframe');
    }

    setState(() {
      _noteSnapshot = snapshot;
      _hasContent = htmlContent != null && htmlContent.isNotEmpty;
    });
  }

  void _setupIframe(String htmlContent) {
    debugPrint('🟢 [_setupIframe] START - HTML length: ${htmlContent.length}');

    // Minden alkalommal új view ID-t generálunk, amikor a tartalom változik
    _viewId =
        'note-read-iframe-${widget.noteId}-${DateTime.now().millisecondsSinceEpoch}';

    // Iframe elem létrehozása
    final iframeElement = web.HTMLIFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none';

    iframeElement.sandbox.add('allow-scripts');
    iframeElement.sandbox.add('allow-same-origin');
    iframeElement.sandbox.add('allow-forms');
    iframeElement.sandbox.add('allow-popups');

    // HTML tartalom CSS-szel ellátva - sötét szöveg, jól olvasható mobil eszközön is
    String styledHtmlContent = htmlContent;
    if (htmlContent.isNotEmpty) {
      // Ellenőrizzük, hogy van-e már <style> tag
      if (!htmlContent.toLowerCase().contains('<style')) {
        // CSS hozzáadása a szöveg sötét színéhez és olvashatóságához
        const cssStyle = '''
        <style>
          * {
            box-sizing: border-box;
          }
          /* Teszt stílus - ha ez látszik, akkor a CSS betöltődik */
          body::before {
            content: "CSS loaded" !important;
            display: none !important;
          }
          body {
            color: #202122 !important;
            background-color: #ffffff !important;
            font-family: Verdana, sans-serif !important;
            font-size: 13px !important;
            line-height: 1.6 !important;
            padding: 16px !important;
            margin: 0 !important;
            text-align: justify !important;
            hyphens: auto !important;
            -webkit-hyphens: auto !important;
            -ms-hyphens: auto !important;
            overflow-wrap: break-word !important;
            word-break: break-word !important;
            letter-spacing: 0.3px !important;
          }
          p, div, span, li, td, th {
            color: #202122 !important;
            text-align: justify !important;
            hyphens: auto !important;
            -webkit-hyphens: auto !important;
            -ms-hyphens: auto !important;
            overflow-wrap: break-word !important;
            word-break: break-word !important;
            letter-spacing: 0.3px !important;
          }
          h1, h2, h3, h4, h5, h6 {
            color: #202122 !important;
            font-weight: 600 !important;
            text-align: left !important;
            overflow-wrap: break-word !important;
            word-break: break-word !important;
            letter-spacing: 0.3px !important;
            margin-top: 1.5em !important;
            margin-bottom: 0.5em !important;
          }
          h1 {
            font-size: 24px !important;
          }
          h2 {
            font-size: 20px !important;
          }
          h3 {
            font-size: 18px !important;
          }
          /* UNIVERZÁLIS SZELEKTOROK - Szekció számok színes dobozokban - piros */
          /* Minden lehetséges kombinációt kezelünk */
          span[style*="#dc3545"],
          span[style*="220, 53, 69"],
          span[style*="rgb(220"],
          span[style*="rgba(220"],
          div[style*="#dc3545"],
          div[style*="220, 53, 69"],
          div[style*="rgb(220"],
          div[style*="rgba(220"],
          span[style*="background-color: #dc3545"],
          span[style*="background-color:rgb(220, 53, 69)"],
          span[style*="background-color: rgb(220, 53, 69)"],
          span[style*="background-color:#dc3545"],
          div[style*="background-color: #dc3545"],
          div[style*="background-color:rgb(220, 53, 69)"],
          div[style*="background-color: rgb(220, 53, 69)"],
          div[style*="background-color:#dc3545"],
          .szekcio-piros,
          [class*="szekcio"][class*="piros"] {
            display: inline-block !important;
            background-color: #dc3545 !important;
            color: white !important;
            padding: 4px 10px !important;
            border-radius: 4px !important;
            font-weight: bold !important;
            margin-right: 8px !important;
            font-size: 14px !important;
            min-width: 32px !important;
            text-align: center !important;
          }
          /* Szekció számok színes dobozokban - kék */
          span[style*="background-color: #1976d2"],
          span[style*="background-color:rgb(25, 118, 210)"],
          span[style*="background-color: rgb(25, 118, 210)"],
          span[style*="background-color:#1976d2"],
          div[style*="background-color: #1976d2"],
          div[style*="background-color:rgb(25, 118, 210)"],
          div[style*="background-color: rgb(25, 118, 210)"],
          div[style*="background-color:#1976d2"],
          .szekcio-kek,
          [class*="szekcio"][class*="kek"] {
            display: inline-block !important;
            background-color: #1976d2 !important;
            color: white !important;
            padding: 4px 10px !important;
            border-radius: 4px !important;
            font-weight: bold !important;
            margin-right: 8px !important;
            font-size: 14px !important;
            min-width: 32px !important;
            text-align: center !important;
          }
          /* Kulcsszavak */
          .kulcsszo,
          [class*="kulcsszo"],
          div.kulcsszo,
          span.kulcsszo {
            display: inline-block !important;
            background-color: #e3f2fd !important;
            padding: 4px 8px !important;
            border-radius: 4px !important;
            font-weight: 500 !important;
            margin-bottom: 10px !important;
            color: #1976d2 !important;
          }
          /* Színezés */
          .szin-kek {
            color: #1976d2 !important;
            font-weight: 500 !important;
          }
          .szin-zold {
            color: #388e3c !important;
            font-weight: 500 !important;
          }
          .hatter-sarga {
            background-color: #fff9c4 !important;
            padding: 2px 4px !important;
            border-radius: 3px !important;
          }
          /* Idézet dobozok */
          .jogszabaly-doboz,
          [class*="jogszabaly-doboz"],
          [class*="jogszabaly"],
          div[style*="background-color: #f5f5f5"],
          div[style*="background-color:#f5f5f5"],
          div[style*="background-color: rgb(245, 245, 245)"],
          div[style*="background-color:rgb(245, 245, 245)"] {
            background-color: #f5f5f5 !important;
            border-left: 4px solid #1976d2 !important;
            padding: 12px !important;
            margin: 16px 0 !important;
            border-radius: 4px !important;
          }
          .jogszabaly-cimke,
          [class*="jogszabaly-cimke"] {
            font-weight: bold !important;
            color: #1976d2 !important;
            display: block !important;
            margin-bottom: 8px !important;
          }
          /* Listák */
          ul, ol {
            margin-bottom: 12px !important;
            padding-left: 24px !important;
          }
          li {
            margin-bottom: 6px !important;
          }
          /* Táblázatok */
          table {
            width: 100% !important;
            border-collapse: collapse !important;
            margin-bottom: 16px !important;
          }
          table, th, td {
            border: 1px solid #ddd !important;
          }
          th, td {
            padding: 8px !important;
            text-align: left !important;
          }
          /* Képek */
          img {
            max-width: 100% !important;
            height: auto !important;
          }
          /* Reszponzív stílusok */
          @media (max-width: 768px) {
            body {
              font-size: 13px !important;
              padding: 12px !important;
            }
            h1 {
              font-size: 20px !important;
            }
            h2 {
              font-size: 18px !important;
            }
            h3 {
              font-size: 16px !important;
            }
            .jogszabaly-doboz {
              padding: 10px !important;
              margin: 12px 0 !important;
            }
            ul, ol {
              padding-left: 20px !important;
            }
            table {
              font-size: 12px !important;
            }
            th, td {
              padding: 6px !important;
            }
          }
          @media (max-width: 480px) {
            body {
              font-size: 12px !important;
              padding: 10px !important;
            }
            h1 {
              font-size: 18px !important;
            }
            h2 {
              font-size: 16px !important;
            }
            h3 {
              font-size: 14px !important;
            }
            .kulcsszo {
              padding: 3px 6px !important;
              font-size: 11px !important;
            }
            .jogszabaly-doboz {
              padding: 8px !important;
              margin: 10px 0 !important;
            }
            ul, ol {
              padding-left: 18px !important;
            }
            table {
              font-size: 11px !important;
            }
            th, td {
              padding: 4px !important;
            }
          }
        </style>
        ''';
        // Hozzáadjuk a lang="hu" attribútumot az html vagy body taghez magyar szóelválasztáshoz
        String htmlWithLang = htmlContent;
        if (htmlContent.toLowerCase().contains('<html')) {
          // Ha van html tag, hozzáadjuk a lang attribútumot
          htmlWithLang = htmlContent.replaceAllMapped(
            RegExp(r'<html([^>]*)>', caseSensitive: false),
            (match) {
              final attrs = match.group(1) ?? '';
              if (attrs.toLowerCase().contains('lang=')) {
                return match.group(0)!; // Ha már van lang, nem módosítjuk
              }
              return '<html lang="hu"$attrs>';
            },
          );
          // Ha van body tag is, annak is adjuk hozzá
          if (htmlWithLang.toLowerCase().contains('<body')) {
            htmlWithLang = htmlWithLang.replaceAllMapped(
              RegExp(r'<body([^>]*)>', caseSensitive: false),
              (match) {
                final attrs = match.group(1) ?? '';
                if (attrs.toLowerCase().contains('lang=')) {
                  return match.group(0)!;
                }
                return '<body lang="hu"$attrs>';
              },
            );
          }
        } else if (htmlContent.toLowerCase().contains('<body')) {
          // Ha nincs html tag, de van body, akkor html taget is hozzáadunk
          htmlWithLang = htmlContent.replaceAllMapped(
            RegExp(r'<body([^>]*)>', caseSensitive: false),
            (match) {
              final attrs = match.group(1) ?? '';
              if (attrs.toLowerCase().contains('lang=')) {
                return match.group(0)!;
              }
              return '<body lang="hu"$attrs>';
            },
          );
          htmlWithLang = '<html lang="hu">$htmlWithLang</html>';
        } else {
          // Ha nincs html vagy body tag, hozzáadjuk mindkettőt lang attribútummal
          htmlWithLang =
              '<html lang="hu"><body lang="hu">$htmlContent</body></html>';
        }
        styledHtmlContent = cssStyle + htmlWithLang;
      } else {
        // Ha már van style tag, hozzáadjuk a body stílust és az html lang attribútumot
        debugPrint('🟢 [_setupIframe] Modifying existing style/lang settings');

        String htmlWithLang = htmlContent;
        // Hozzáadjuk a lang attribútumot az html taghez
        if (htmlContent.toLowerCase().contains('<html')) {
          htmlWithLang = htmlContent.replaceAllMapped(
            RegExp(r'<html([^>]*)>', caseSensitive: false),
            (match) {
              final attrs = match.group(1) ?? '';
              if (attrs.toLowerCase().contains('lang=')) {
                return match.group(0)!;
              }
              return '<html lang="hu"$attrs>';
            },
          );
        } else {
          // Ha nincs html tag, hozzáadjuk
          htmlWithLang = '<html lang="hu">$htmlContent</html>';
        }
        // Hozzáadjuk a body stílust és lang attribútumot
        htmlWithLang = htmlWithLang.replaceAll(
          RegExp(r'<body[^>]*>', caseSensitive: false),
          '<body lang="hu" style="color: #202122 !important; background-color: #ffffff !important; font-family: Verdana, sans-serif !important; font-size: 13px !important; line-height: 1.6 !important; padding: 16px !important; margin: 0 !important; text-align: justify !important; hyphens: auto !important; -webkit-hyphens: auto !important; -ms-hyphens: auto !important; overflow-wrap: break-word !important; word-break: break-word !important; letter-spacing: 0.3px !important;">',
        );

        // Hozzáadjuk a hiányzó CSS stílusokat a meglévő style tag után
        const additionalCss = '''
          /* Szekció számok színes dobozokban - piros */
          span[style*="background-color: #dc3545"],
          span[style*="background-color:rgb(220, 53, 69)"],
          span[style*="background-color: rgb(220, 53, 69)"],
          span[style*="background-color:#dc3545"],
          div[style*="background-color: #dc3545"],
          div[style*="background-color:rgb(220, 53, 69)"],
          div[style*="background-color: rgb(220, 53, 69)"],
          div[style*="background-color:#dc3545"],
          .szekcio-piros,
          [class*="szekcio"][class*="piros"] {
            display: inline-block !important;
            background-color: #dc3545 !important;
            color: white !important;
            padding: 4px 10px !important;
            border-radius: 4px !important;
            font-weight: bold !important;
            margin-right: 8px !important;
            font-size: 14px !important;
            min-width: 32px !important;
            text-align: center !important;
          }
          /* Szekció számok színes dobozokban - kék */
          span[style*="background-color: #1976d2"],
          span[style*="background-color:rgb(25, 118, 210)"],
          span[style*="background-color: rgb(25, 118, 210)"],
          span[style*="background-color:#1976d2"],
          div[style*="background-color: #1976d2"],
          div[style*="background-color:rgb(25, 118, 210)"],
          div[style*="background-color: rgb(25, 118, 210)"],
          div[style*="background-color:#1976d2"],
          .szekcio-kek,
          [class*="szekcio"][class*="kek"] {
            display: inline-block !important;
            background-color: #1976d2 !important;
            color: white !important;
            padding: 4px 10px !important;
            border-radius: 4px !important;
            font-weight: bold !important;
            margin-right: 8px !important;
            font-size: 14px !important;
            min-width: 32px !important;
            text-align: center !important;
          }
          /* Kulcsszavak */
          .kulcsszo,
          [class*="kulcsszo"],
          div.kulcsszo,
          span.kulcsszo {
            display: inline-block !important;
            background-color: #e3f2fd !important;
            padding: 4px 8px !important;
            border-radius: 4px !important;
            font-weight: 500 !important;
            margin-bottom: 10px !important;
            color: #1976d2 !important;
          }
          /* Színezés */
          .szin-kek {
            color: #1976d2 !important;
            font-weight: 500 !important;
          }
          .szin-zold {
            color: #388e3c !important;
            font-weight: 500 !important;
          }
          .hatter-sarga {
            background-color: #fff9c4 !important;
            padding: 2px 4px !important;
            border-radius: 3px !important;
          }
          /* Idézet dobozok */
          .jogszabaly-doboz,
          [class*="jogszabaly-doboz"],
          [class*="jogszabaly"],
          div[style*="background-color: #f5f5f5"],
          div[style*="background-color:#f5f5f5"],
          div[style*="background-color: rgb(245, 245, 245)"],
          div[style*="background-color:rgb(245, 245, 245)"] {
            background-color: #f5f5f5 !important;
            border-left: 4px solid #1976d2 !important;
            padding: 12px !important;
            margin: 16px 0 !important;
            border-radius: 4px !important;
          }
          .jogszabaly-cimke,
          [class*="jogszabaly-cimke"] {
            font-weight: bold !important;
            color: #1976d2 !important;
            display: block !important;
            margin-bottom: 8px !important;
          }

          /* Másolás/kijelölés tiltása (nehezítés) */
          html, body, body * {
            -webkit-touch-callout: none !important;
            -webkit-user-select: none !important;
            -khtml-user-select: none !important;
            -moz-user-select: none !important;
            -ms-user-select: none !important;
            user-select: none !important;
          }
          input, textarea, [contenteditable="true"] {
            -webkit-user-select: text !important;
            -khtml-user-select: text !important;
            -moz-user-select: text !important;
            -ms-user-select: text !important;
            user-select: text !important;
            -webkit-touch-callout: default !important;
          }
        ''';

        const additionalJs = '''
<script>
  (function () {
    function isEditableTarget(target) {
      if (!target) return false;
      if (target.closest) {
        return !!target.closest('input, textarea, [contenteditable="true"]');
      }
      return false;
    }

    document.addEventListener('contextmenu', function (e) {
      if (isEditableTarget(e.target)) return;
      e.preventDefault();
    }, true);

    document.addEventListener('keydown', function (e) {
      if (isEditableTarget(e.target)) return;
      if (!(e.ctrlKey || e.metaKey)) return;
      var k = (e.key || '').toLowerCase();
      if (k === 'c' || k === 'a') {
        e.preventDefault();
      }
    }, true);

    document.addEventListener('copy', function (e) {
      if (isEditableTarget(e.target)) return;
      e.preventDefault();
    }, true);
  })();
</script>
''';

        // Hozzáadjuk a CSS-t a meglévő </style> tag elé
        if (htmlWithLang.toLowerCase().contains('</style>')) {
          styledHtmlContent = htmlWithLang.replaceAll(
            RegExp(r'</style>', caseSensitive: false),
            '$additionalCss</style>',
          );
        } else {
          // Ha nincs </style> tag, hozzáadjuk a head végéhez
          if (htmlWithLang.toLowerCase().contains('</head>')) {
            styledHtmlContent = htmlWithLang.replaceAll(
              RegExp(r'</head>', caseSensitive: false),
              '<style>$additionalCss</style></head>',
            );
          } else {
            // Ha nincs head tag sem, hozzáadjuk a html elejéhez
            styledHtmlContent = htmlWithLang.replaceAll(
              RegExp(r'<html[^>]*>', caseSensitive: false),
              '<html lang="hu"><head><style>$additionalCss</style></head>',
            );
          }
        }

        // Hozzáadjuk a JS tiltásokat is (iframe dokumentumon belül)
        if (styledHtmlContent.toLowerCase().contains('</head>')) {
          styledHtmlContent = styledHtmlContent.replaceAll(
            RegExp(r'</head>', caseSensitive: false),
            '$additionalJs</head>',
          );
        } else if (styledHtmlContent.toLowerCase().contains('<html')) {
          // Ha nincs head, próbáljuk beilleszteni a html tag után
          styledHtmlContent = styledHtmlContent.replaceAllMapped(
            RegExp(r'<html[^>]*>', caseSensitive: false),
            (m) => '${m.group(0)}<head>$additionalJs</head>',
          );
        } else {
          styledHtmlContent = '<head>$additionalJs</head>$styledHtmlContent';
        }
      }

      final blob = web.Blob([styledHtmlContent.toJS].toJS,
          web.BlobPropertyBag(type: 'text/html'));
      iframeElement.src = web.URL.createObjectURL(blob);

      // Eltávolítottuk a nehéz debugPrint hívásokat
      debugPrint('🟢 [_setupIframe] Iframe content set via Blob URL');
      debugPrint(
          'Contains "jogszabaly": ${htmlContent.toLowerCase().contains('jogszabaly')}');
      debugPrint(
          'Contains style with #1976d2: ${htmlContent.contains('#1976d2')}');
      debugPrint(
          'Contains style with #dc3545: ${htmlContent.contains('#dc3545')}');
      debugPrint(
          'Contains style with rgb(25, 118, 210): ${htmlContent.contains('rgb(25, 118, 210)')}');
      debugPrint(
          'Contains style with rgb(220, 53, 69): ${htmlContent.contains('rgb(220, 53, 69)')}');
      debugPrint('Final styled HTML length: ${styledHtmlContent.length}');
      debugPrint('========================');
      // #endregion
    }

    // Platform view regisztrálása
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => iframeElement,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_noteSnapshot == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final data = _noteSnapshot!.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? 'Cím nélkül';
    final category = data['category'] as String?;
    final tags = data['tags'] as List<dynamic>?;
    final tag = tags != null && tags.isNotEmpty ? tags.first.toString() : null;

    // Debug: ellenőrizzük, hogy milyen adatokat kaptunk
    debugPrint('🔵 NoteReadScreen: title=$title, category=$category, tag=$tag');

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final state = GoRouterState.of(context);
    final bundleId = state.uri.queryParameters['bundleId'];

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
            // Ha kötegből jöttünk, oda megyünk vissza
            if (bundleId != null && bundleId.isNotEmpty) {
              context.go('/my-bundles/view/$bundleId');
              return;
            }

            // Breadcrumb navigációval visszalépünk
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
            } else if (effectiveCategory != null &&
                effectiveCategory.isNotEmpty) {
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
          // Breadcrumb navigáció - elrejtve, ha kötegből jöttünk
          if (bundleId == null || bundleId.isEmpty)
            BreadcrumbNavigation(
              category: category,
              tag: tag,
              noteTitle: title,
              noteId: widget.noteId,
              fromBundleId: bundleId,
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
                      child: _hasContent && _viewId.isNotEmpty
                          ? HtmlElementView(
                              key: ValueKey('iframe_$_viewId'),
                              viewType: _viewId,
                            )
                          : const Center(
                              child: Text(
                                'Ez a jegyzet nem tartalmaz tartalmat.',
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                            ),
                    ),
                  ),
                  if (data['audioUrl'] != null &&
                      data['audioUrl'].toString().isNotEmpty)
                    Container(
                      margin: EdgeInsets.fromLTRB(
                        isMobile ? 0 : 16,
                        0,
                        isMobile ? 0 : 16,
                        isMobile ? 0 : 16,
                      ),
                      child: AudioPreviewPlayer(audioUrl: data['audioUrl']),
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
