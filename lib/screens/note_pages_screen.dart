import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../widgets/audio_preview_player.dart';

class NotePagesScreen extends StatefulWidget {
  final String noteId;
  final String? from;

  const NotePagesScreen({
    super.key,
    required this.noteId,
    this.from,
  });

  @override
  State<NotePagesScreen> createState() => _NotePagesScreenState();
}

class _NotePagesScreenState extends State<NotePagesScreen> {
  DocumentSnapshot? _noteSnapshot;
  int _currentPageIndex = 0;
  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadNote() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId)
          .get();

      if (mounted) {
        // Ha a dokumentum nem létezik vagy a Firestore szabály blokkolja
        if (!snapshot.exists) {
          _showAccessDeniedAndGoBack();
          return;
        }
        setState(() => _noteSnapshot = snapshot);
        _setupMedia(snapshot.data());
      }
    } catch (e) {
      // Firestore permission denied hiba (zárt jegyzet, nincs prémium hozzáférés)
      if (mounted) {
        _showAccessDeniedAndGoBack();
      }
    }
  }

  void _showAccessDeniedAndGoBack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            'Ez a tartalom csak előfizetőknek érhető el. Vásárolj előfizetést a teljes hozzáféréshez!'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Előfizetés',
          onPressed: () {
            context.go('/account');
          },
        ),
      ),
    );
    // Visszairányítás a jegyzetek listához
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        if (widget.from != null && widget.from!.isNotEmpty) {
          context.go(widget.from!);
        } else {
          context.go('/notes');
        }
      }
    });
  }

  void _setupMedia(Map<String, dynamic>? data) {
    if (data == null) return;

    final pages = data['pages'] as List<dynamic>? ?? [];
    if (pages.isNotEmpty) {
      final currentPage = pages[_currentPageIndex] as String;
      if (currentPage.contains('<script')) {
        _webViewController = WebViewController()..loadHtmlString(currentPage);
      }
    }
  }

  void _goToPreviousPage() {
    if (_currentPageIndex > 0) {
      setState(() {
        _currentPageIndex--;
        _updatePageContent();
      });
    }
  }

  void _goToNextPage(List<dynamic> pages) {
    if (_currentPageIndex < pages.length - 1) {
      setState(() {
        _currentPageIndex++;
        _updatePageContent();
      });
    }
  }

  void _updatePageContent() {
    final data = _noteSnapshot!.data() as Map<String, dynamic>;
    final pages = data['pages'] as List<dynamic>? ?? [];
    final currentPage =
        pages.isNotEmpty ? pages[_currentPageIndex] as String : '';

    if (currentPage.contains('<script')) {
      _webViewController = WebViewController()..loadHtmlString(currentPage);
    } else {
      _webViewController = null;
    }
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
    final pages = data['pages'] as List<dynamic>? ?? [];
    final currentPage = pages.isNotEmpty
        ? pages[_currentPageIndex] as String
        : 'Ez a jegyzet nem tartalmaz tartalmat.';

    final bool isWebView = _webViewController != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.from != null && widget.from!.isNotEmpty) {
              context.go(widget.from!);
            } else {
              context.go('/notes');
            }
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (pages.isNotEmpty)
              Text(
                'Oldal ${_currentPageIndex + 1} / ${pages.length}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: isWebView
                  ? WebViewWidget(controller: _webViewController!)
                  : SingleChildScrollView(
                      child: Html(
                        data: currentPage,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _currentPageIndex > 0 ? _goToPreviousPage : null,
                  child: const Text('Előző oldal'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _currentPageIndex < pages.length - 1
                      ? () => _goToNextPage(pages)
                      : null,
                  child: const Text('Következő oldal'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (data['audioUrl'] != null &&
                data['audioUrl'].toString().isNotEmpty)
              AudioPreviewPlayer(audioUrl: data['audioUrl'])
            else
              const Padding(
                padding: EdgeInsets.only(top: 20.0),
                child: Text('Nincs hanganyag elérhető.'),
              ),
          ],
        ),
      ),
    );
  }
}
