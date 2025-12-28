import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import '../widgets/mini_audio_player.dart';
import 'package:flutter_html/flutter_html.dart';

class FlashcardCardEditScreen extends StatefulWidget {
  final String cardId;
  const FlashcardCardEditScreen({super.key, required this.cardId});

  @override
  State<FlashcardCardEditScreen> createState() =>
      _FlashcardCardEditScreenState();
}

class _FlashcardCardEditScreenState extends State<FlashcardCardEditScreen> {
  final _titleCtrl = TextEditingController();
  final _htmlCtrl = TextEditingController();
  Map<String, dynamic>? _audio;
  String? _deckId;
  bool _isLoading = true;
  bool _isSaving = false;
  Timer? _debounce;

  DocumentReference get _cardRef =>
      FirebaseFirestore.instance.collection('notes').doc(widget.cardId);

  @override
  void initState() {
    super.initState();
    _loadCardData();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _htmlCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCardData() async {
    try {
      final doc = await _cardRef.get();
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        _titleCtrl.text = data['title'] ?? 'Névtelen kártya';
        _htmlCtrl.text = data['html'] ?? '';
        _deckId = data['deckId'];
        if (data['audioUrl'] != null) {
          _audio = {
            'url': data['audioUrl'],
            'name': _extractFileName(data['audioUrl'])
          };
        }
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hiba a kártya betöltésekor: $e')));
        context.pop();
      }
    }
  }

  String _extractFileName(String url) {
    try {
      return Uri.decodeComponent(url.split('%2F').last.split('?').first);
    } catch (e) {
      return 'Ismeretlen fájlnév';
    }
  }

  Future<void> _pickAudio() async {
    const typeGroup = XTypeGroup(label: 'MP3', extensions: ['mp3']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      // 10 MB limit
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Max 10 MB MP3!')));
      return;
    }

    setState(() {
      _audio = {'name': file.name, 'bytes': bytes};
    });
  }

  void _removeAudio() {
    setState(() {
      _audio = null;
    });
  }

  Future<void> _saveCard() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      String? audioUrl;
      if (_audio != null) {
        if (_audio!.containsKey('bytes')) {
          final ref = FirebaseStorage.instance
              .ref('notes/${widget.cardId}/${_audio!['name']}');
          await ref.putData(_audio!['bytes']);
          audioUrl = await ref.getDownloadURL();
        } else if (_audio!.containsKey('url')) {
          audioUrl = _audio!['url'];
        }
      }

      await _cardRef.update({
        'title': _titleCtrl.text.trim(),
        'html': _htmlCtrl.text.trim(),
        'audioUrl': audioUrl,
        'modified': Timestamp.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Kártya mentve!')));
        if (_deckId != null) context.go('/flashcard-decks/edit/$_deckId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hiba mentés közben: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showPreview() {
    final audioPlayer = AudioPlayer();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Előnézet'),
        content: SizedBox(
          width: 800,
          height: 600,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Html(data: _htmlCtrl.text),
                ),
              ),
              if (_audio != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: _audio!['url'] != null
                      ? MiniAudioPlayer(
                          audioUrl: _audio!['url'],
                          compact: false,
                          large: true,
                        )
                      : ElevatedButton.icon(
                          onPressed: () {
                            if (_audio!['bytes'] != null) {
                              audioPlayer.play(BytesSource(_audio!['bytes']));
                            }
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Helyi fájl lejátszása'),
                        ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              audioPlayer.dispose();
              Navigator.of(context).pop();
            },
            child: const Text('Bezárás'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Kártya Szerkesztése: ${_titleCtrl.text}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_deckId != null) context.go('/flashcard-decks/edit/$_deckId');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_red_eye),
            onPressed: _showPreview,
            tooltip: 'Előnézet',
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveCard,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Mentés'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Kártya címe (admin felületen látszik)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Hangfájl',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _audio == null
                          ? 'Nincs hangfájl csatolva.'
                          : _audio!['name'],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    children: [
                      if (_audio != null)
                        IconButton(
                          icon:
                              const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: _removeAudio,
                          tooltip: 'Hangfájl eltávolítása',
                        ),
                      ElevatedButton.icon(
                        onPressed: _pickAudio,
                        icon: const Icon(Icons.attach_file),
                        label: Text(_audio == null ? 'Kiválasztás' : 'Csere'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('HTML Kód',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _htmlCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Illessze be a kártya teljes HTML kódját...',
              ),
              maxLines: 25,
            ),
          ],
        ),
      ),
    );
  }
}
