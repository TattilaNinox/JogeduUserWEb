import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import '../widgets/audio_preview_player.dart';
import '../utils/filter_storage.dart';

/// Felhasználói (csak olvasás) nézet szöveges jegyzetekhez.
///
/// - Csak megjelenítés és hanganyag lejátszás
/// - Nincsenek admin műveletek
class NoteReadScreen extends StatefulWidget {
  final String noteId;

  const NoteReadScreen({super.key, required this.noteId});

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
    final snapshot = await FirebaseFirestore.instance
        .collection('notes')
        .doc(widget.noteId)
        .get();

    if (!mounted) return;

    final data = snapshot.data();
    String? htmlContent;
    if (data != null) {
    final pages = data['pages'] as List<dynamic>? ?? [];
    if (pages.isNotEmpty) {
        htmlContent = pages[_currentPageIndex] as String? ?? '';
      }
    }
    
    if (htmlContent != null && htmlContent.isNotEmpty) {
      _setupIframe(htmlContent);
    }
    
    setState(() {
      _noteSnapshot = snapshot;
      _hasContent = htmlContent != null && htmlContent.isNotEmpty;
    });
  }

  void _setupIframe(String htmlContent) {
    // Minden alkalommal új view ID-t generálunk, amikor a tartalom változik
    _viewId = 'note-read-iframe-${widget.noteId}-${DateTime.now().millisecondsSinceEpoch}';
    
    // Iframe elem létrehozása
    final iframeElement = web.HTMLIFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none';
    
    iframeElement.sandbox.add('allow-scripts');
    iframeElement.sandbox.add('allow-same-origin');
    iframeElement.sandbox.add('allow-forms');
    iframeElement.sandbox.add('allow-popups');
    
    // Iframe src beállítása data URI-val
    if (htmlContent.isNotEmpty) {
      iframeElement.src = 'data:text/html;charset=utf-8,${Uri.encodeComponent(htmlContent)}';
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
            // URL paraméterekkel vissza navigálás a szűrők megőrzéséhez
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
        actions: const [],
      ),
      body: Container(
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
                          style: TextStyle(color: Colors.grey, fontSize: 16),
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
    );
  }
}
