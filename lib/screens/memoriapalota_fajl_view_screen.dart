import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/audio_preview_player.dart';
import '../utils/filter_storage.dart';

/// Felhasználói (csak olvasás) nézet memoriapalota_fajlok típusú jegyzetekhez.
///
/// - Csak cím megjelenítés és hanganyag lejátszás
/// - Nincsenek admin műveletek
class MemoriapalotaFajlViewScreen extends StatefulWidget {
  final String noteId;

  const MemoriapalotaFajlViewScreen({super.key, required this.noteId});

  @override
  State<MemoriapalotaFajlViewScreen> createState() =>
      _MemoriapalotaFajlViewScreenState();
}

class _MemoriapalotaFajlViewScreenState
    extends State<MemoriapalotaFajlViewScreen> {
  DocumentSnapshot? _noteSnapshot;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
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
    );
  }
}
