import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../core/app_messenger.dart';
import 'package:file_selector/file_selector.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:html/parser.dart' show parse;
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../widgets/sidebar.dart';
import '../widgets/quiz_viewer.dart';

class NoteEditScreen extends StatefulWidget {
  final String noteId;
  final String? from;

  const NoteEditScreen({super.key, required this.noteId, this.from});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  bool _isSaving = false;
  bool _isFree = false; // új mező

  final _titleController = TextEditingController();
  final _htmlContentController = TextEditingController();
  String? _selectedCategory;
  List<String> _tags = [];
  final _tagController = TextEditingController();
  String _selectedType = 'text';
  String? _bundleId;

  Map<String, dynamic>? _selectedMp3File;
  Map<String, dynamic>? _selectedVideoFile;
  VideoPlayerController? _videoController;
  String? _existingAudioUrl;
  bool _deleteAudio = false;

  // Új: PDF fájl kezelése
  Map<String, dynamic>? _selectedPdfFile;
  String? _existingPdfUrl;
  bool _deletePdf = false;

  String get _pdfFileDisplayName {
    if (_selectedPdfFile != null) return _selectedPdfFile!['name'] as String;
    if (_existingPdfUrl != null) {
      final path = Uri.parse(_existingPdfUrl!).pathSegments;
      return path.isNotEmpty ? path.last : 'PDF fájl';
    }
    return '';
  }

  List<String> _categories = [];
  List<String> _sciences = [];
  String? _selectedScience;
  late TabController _tabController;
  final ValueNotifier<double> _editorFontSize = ValueNotifier<double>(9.0);

  late final String _previewViewId;
  final web.HTMLIFrameElement _previewIframeElement = web.HTMLIFrameElement();
  bool _showPreview = false;

  // Segédfüggvény URL megnyitásához
  Future<void> _openUrl(String url) async {
    // Weben sok böngésző a PDF-et azonnal letölti. A Google Docs Viewerrel
    // biztosan egy új fülön, beágyazva nyílik meg.
    final targetUrl = kIsWeb
        ? 'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(url)}'
        : url;

    final uri = Uri.parse(targetUrl);
    if (!await launchUrl(uri,
        mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nem sikerült megnyitni a PDF-et.')));
      }
    }
  }

  // Előnézet nyomtatása (csak WEB)
  Future<void> _printPreview() async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nyomtatás csak a webes felületen érhető el.')));
      return;
    }

    if (_selectedType != 'text') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nyomtatás csak szöveges jegyzethez érhető el.')));
      return;
    }

    // HTML -> PDF nyomtatás közvetlenül, URL-lábléc nélkül
    final htmlContent = _htmlContentController.text;
    if (htmlContent.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nincs tartalom a nyomtatáshoz.')));
      return;
    }

    final title = _titleController.text;
    final htmlDoc = '<!doctype html>'
        '<html><head><meta charset="utf-8"><title>'
        '$title'
        '</title><style>'
        '@page { size: A4; margin: 15mm; }'
        'body{font-family:Inter,Arial,sans-serif;font-size:12pt;margin-bottom:18mm;}'
        'img{max-width:100%;}'
        'h1,h2,h3{page-break-after:avoid;}'
        'table{border-collapse:collapse;width:100%;}'
        'td,th{border:1px solid #ccc;padding:6px;}'
        '.print-footer{position:fixed;left:0;bottom:0;font-size:10pt;color:#fff;}'
        '</style></head><body>'
        '$htmlContent'
        '<div class="print-footer">Lomedu.hu</div>'
        '</body></html>';

    try {
      await Printing.layoutPdf(
        name: title.isEmpty ? 'jegyzet' : title,
        onLayout: (format) async {
          // ignore: deprecated_member_use
          return await Printing.convertHtml(format: format, html: htmlDoc);
        },
      );
    } catch (e) {
      // Weben előfordulhat UnimplementedError – essünk vissza új ablakos nyomtatásra
      final newWin = web.window.open('', '_blank');
      if (newWin == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'A böngésző blokkolta a felugró ablakot. Engedélyezd a pop-upokat.')));
        return;
      }
      final html =
          '<!doctype html><html><head><meta charset="utf-8"><title> </title>'
          '<style>@page { size: A4; margin: 15mm; } body{font-family:Inter,Arial,sans-serif;font-size:12pt;margin-bottom:18mm;} img{max-width:100%;} h1,h2,h3{page-break-after:avoid;} table{border-collapse:collapse;width:100%;} td,th{border:1px solid #ccc;padding:6px;} .print-footer{position:fixed;left:0;bottom:0;font-size:10pt;color:#fff;}</style>'
          '</head><body>'
          '$htmlContent'
          '<div class="print-footer">Lomedu.hu</div>'
          '<script>window.addEventListener("load",function(){setTimeout(function(){try{window.focus();window.print();}catch(e){console.error(e);} }, 50);}); window.onafterprint=function(){window.close();};</script>'
          '</body></html>';
      try {
        newWin.document.open();
        newWin.document.write(html);
        newWin.document.close();
      } catch (_) {}
    }
  }

  // (nincs használatban)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _previewViewId = 'note-edit-preview-iframe-$hashCode';

    _previewIframeElement
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none';

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
        _previewViewId, (int viewId) => _previewIframeElement);

    _loadInitialData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _htmlContentController.dispose();
    _tagController.dispose();
    _videoController?.dispose();
    _tabController.dispose();
    _editorFontSize.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      // Előbb a tudományok listája, majd a jegyzet adatai,
      // végül a kategóriák a kiválasztott tudomány alapján.
      await _loadSciences();
      await _loadNoteData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Hiba a kezdeti adatok betöltésekor: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCategories() async {
    if (_selectedScience == null) {
      if (mounted) {
        setState(() {
          _categories = [];
        });
      }
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('categories')
        .where('science', isEqualTo: _selectedScience)
        .get();
    if (mounted) {
      setState(() {
        _categories =
            snapshot.docs.map((doc) => doc['name'] as String).toList();
      });
    }
  }

  Future<void> _loadSciences() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('sciences').get();
    if (mounted) {
      _sciences = snapshot.docs.map((doc) => doc['name'] as String).toList();
    }
  }

  Future<void> _loadNoteData() async {
    final doc = await FirebaseFirestore.instance
        .collection('notes')
        .doc(widget.noteId)
        .get();

    if (doc.exists) {
      if (mounted) {
        final data = doc.data()!;
        _titleController.text = data['title'] ?? '';
        _selectedCategory = data['category'];
        _selectedScience = data['science'];
        _bundleId = data['bundleId'];
        _tags = List<String>.from(data['tags'] ?? []);
        _selectedType = data['type'] ?? 'text';
        _isFree = data['isFree'] == true;

        if (data.containsKey('audioUrl')) {
          _existingAudioUrl = data['audioUrl'] as String?;
          _selectedMp3File = {
            'name': 'Meglévő hangfájl',
            'url': _existingAudioUrl
          };
        }
        if (data.containsKey('videoUrl')) {
          _selectedVideoFile = {
            'name': 'Meglévő videófájl',
            'url': data['videoUrl']
          };
        }

        if (data.containsKey('pdfUrl')) {
          _existingPdfUrl = data['pdfUrl'] as String?;
          final fileName = Uri.parse(_existingPdfUrl!).pathSegments.isNotEmpty
              ? Uri.parse(_existingPdfUrl!).pathSegments.last
              : 'pdf_dokumentum.pdf';
          _selectedPdfFile = {'name': fileName, 'url': _existingPdfUrl};
        }

        final pages = data['pages'] as List<dynamic>? ?? [];
        final content = pages.isNotEmpty ? pages.first as String : '';

        _htmlContentController.text = content;

        // A kategóriák frissítése a jegyzet tudománya alapján
        if (_selectedScience != null) {
          await _loadCategories();
          // Ha a jegyzet kategóriája nincs a listában (adatkonzisztencia hiba vagy hiányzó kategória),
          // ne nullázzuk ki, inkább hagyjuk meg a meglévő értéket, és a dropdown-ban legyen disabled.
          if (!_categories.contains(_selectedCategory)) {
            // Itt nem állítunk null-t, csak a dropdown értéke lesz null, a mentésnél viszont a meglévő
            // _selectedCategory fog szerepelni, amíg a felhasználó nem választ új értéket.
          }
        }
      }
    } else {
      throw Exception('A jegyzet nem található.');
    }
  }

  Future<void> _updateNote() async {
    if (_titleController.text.isEmpty ||
        _selectedCategory == null ||
        _selectedScience == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A cím és a kategória megadása kötelező!')),
      );
      return;
    }

    if (_htmlContentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A tartalom nem lehet üres!')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      for (final tag in _tags) {
        FirebaseFirestore.instance
            .collection('tags')
            .doc(tag)
            .set({'name': tag});
      }

      final Map<String, dynamic> noteData = {
        'title': _titleController.text,
        'category': _selectedCategory,
        'science': _selectedScience,
        'tags': _tags,
        'pages': [_htmlContentController.text],
        'isFree': _isFree,
        'modified': Timestamp.now(),
      };

      // Audio törlés / csere kezelése
      if (_deleteAudio && _existingAudioUrl != null) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(_existingAudioUrl!);
          await ref.delete();
        } catch (_) {}
        // csak akkor töröljük a mezőt, ha nem töltünk fel újat
        noteData['audioUrl'] = FieldValue.delete();
        _existingAudioUrl = null;
      }

      if (isFileValid(_selectedMp3File) && _selectedMp3File!['bytes'] != null) {
        final mp3Ref = FirebaseStorage.instance
            .ref('notes/${widget.noteId}/${_selectedMp3File!['name']}');
        await mp3Ref.putData(
            Uint8List.fromList(_selectedMp3File!['bytes'] as List<int>));
        noteData['audioUrl'] = await mp3Ref.getDownloadURL();
        _deleteAudio = false;
      }

      if (isFileValid(_selectedVideoFile) &&
          _selectedVideoFile!['bytes'] != null) {
        final videoRef = FirebaseStorage.instance
            .ref('notes/${widget.noteId}/${_selectedVideoFile!['name']}');
        await videoRef.putData(
            Uint8List.fromList(_selectedVideoFile!['bytes'] as List<int>));
        noteData['videoUrl'] = await videoRef.getDownloadURL();
      }

      // PDF törlés  / csere kezelése
      if (_deletePdf && _existingPdfUrl != null) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(_existingPdfUrl!);
          await ref.delete();
        } catch (_) {}
        noteData['pdfUrl'] = FieldValue.delete();
        _existingPdfUrl = null;
      }

      if (isFileValid(_selectedPdfFile) && _selectedPdfFile!['bytes'] != null) {
        final pdfRef = FirebaseStorage.instance
            .ref('notes/${widget.noteId}/${_selectedPdfFile!['name']}');
        await pdfRef.putData(
            Uint8List.fromList(_selectedPdfFile!['bytes'] as List<int>));
        noteData['pdfUrl'] = await pdfRef.getDownloadURL();
        _deletePdf = false;
      }

      await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId)
          .update(noteData);

      if (mounted) {
        AppMessenger.showSuccess('Jegyzet sikeresen frissítve!');
        // Frissítsük a lokális állapotot, hogy a feltöltött/törölt fájlok
        // azonnal tükröződjenek.
        await _loadNoteData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a mentés során: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
          body: Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red))));
    }

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 249, 250, 251),
      appBar: AppBar(
        title: Text('"${_titleController.text}" szerkesztése'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.from != null && widget.from!.isNotEmpty) {
              context.go(Uri.decodeComponent(widget.from!));
            } else {
              context.go('/notes');
            }
          },
        ),
        actions: [
          if (_bundleId != null)
            IconButton(
              icon: const Icon(Icons.all_inbox),
              tooltip: 'Ugrás a köteghez',
              onPressed: () {
                context.go('/bundles/edit/$_bundleId');
              },
            ),
          TextButton(
            onPressed: () {
              if (widget.from != null && widget.from!.isNotEmpty) {
                context.go(Uri.decodeComponent(widget.from!));
              } else {
                context.go('/notes');
              }
            },
            child: const Text('Mégse'),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: ElevatedButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: const Text('Mentés'),
              onPressed: _isSaving ? null : _updateNote,
            ),
          )
        ],
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'notes'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bal oldali, fő tartalom
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildTextField(
                                  _titleController, 'Jegyzet címe'),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 1,
                              child: _buildTypeDropdown(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildEditorAndPreview(),
                        if (_selectedPdfFile != null ||
                            (_existingPdfUrl != null && !_deletePdf)) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'PDF: $_pdfFileDisplayName',
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_existingPdfUrl != null && !_deletePdf) ...[
                                IconButton(
                                  tooltip: 'URL másolása',
                                  onPressed: () async {
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    await Clipboard.setData(
                                        ClipboardData(text: _existingPdfUrl!));
                                    if (mounted) {
                                      messenger.showSnackBar(const SnackBar(
                                          content: Text(
                                              'PDF URL vágólapra másolva')));
                                    }
                                  },
                                  icon: const Icon(Icons.link),
                                ),
                              ]
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Jobb oldali sáv
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildScienceDropdown(),
                            const SizedBox(height: 16),
                            _buildCategoryDropdown(),
                            const SizedBox(height: 16),
                            _buildFreeAccessToggle(),
                            const SizedBox(height: 16),
                            _buildTagsSection(),
                            const SizedBox(height: 24),
                            _buildFileUploadSection(),
                          ],
                        ),
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

  Widget _buildTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedType,
      items: const [
        DropdownMenuItem(value: 'text', child: Text('Szöveges')),
        DropdownMenuItem(value: 'interactive', child: Text('Interaktív')),
        DropdownMenuItem(value: 'dynamic_quiz', child: Text('Dinamikus Kvíz')),
        DropdownMenuItem(
            value: 'dynamic_quiz_dual',
            child: Text('2-válaszos Dinamikus Kvíz')),
        DropdownMenuItem(value: 'deck', child: Text('Pakli')),
        DropdownMenuItem(value: 'source', child: Text('Forrás')),
      ],
      onChanged: (newValue) => setState(() => _selectedType = newValue!),
      decoration: const InputDecoration(
        labelText: 'Típus',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue:
          _categories.contains(_selectedCategory) ? _selectedCategory : null,
      items: _categories.map((String category) {
        return DropdownMenuItem<String>(
          value: category,
          child: Text(category),
        );
      }).toList(),
      onChanged: _selectedScience == null
          ? null
          : (newValue) {
              setState(() {
                _selectedCategory = newValue;
              });
            },
      decoration: InputDecoration(
        labelText: 'Kategória',
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: _selectedScience == null ? Colors.grey[100] : Colors.white,
      ),
    );
  }

  Widget _buildScienceDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedScience,
      items: _sciences.map((String sc) {
        return DropdownMenuItem<String>(
          value: sc,
          child: Text(sc),
        );
      }).toList(),
      onChanged: (newValue) {
        setState(() {
          _selectedScience = newValue;
          _selectedCategory = null;
        });
        _loadCategories();
      },
      decoration: const InputDecoration(
        labelText: 'Tudomány',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildEditorAndPreview() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  labelColor: Theme.of(context).primaryColor,
                  unselectedLabelColor: Colors.grey,
                  tabs: const [
                    Tab(text: 'Szerkesztő'),
                    Tab(text: 'Előnézet'),
                  ],
                  onTap: (index) {
                    if (index == 1) {
                      // Preview tab
                      final htmlContent = _htmlContentController.text;
                      if (htmlContent.isNotEmpty) {
                        if (parse(htmlContent).documentElement == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Figyelem: A HTML kód érvénytelennek tűnik.'),
                                backgroundColor: Colors.orange),
                          );
                          _tabController.index = 0; // Visszaváltás
                          return;
                        }
                        setState(() {
                          _previewIframeElement.src =
                              'data:text/html;charset=utf-8,${Uri.encodeComponent(htmlContent)}';
                          _showPreview = true;
                        });
                      } else {
                        setState(() {
                          _showPreview = false;
                        });
                      }
                    } else {
                      setState(() {
                        _showPreview = false;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              if (kIsWeb && _selectedType == 'text')
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: OutlinedButton.icon(
                    onPressed:
                        _showPreview && _htmlContentController.text.isNotEmpty
                            ? _printPreview
                            : null,
                    icon: const Icon(Icons.print),
                    label: const Text('Nyomtatás'),
                  ),
                ),
              ValueListenableBuilder<double>(
                valueListenable: _editorFontSize,
                builder: (context, fontSize, child) {
                  return Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          if (fontSize > 8.0) {
                            _editorFontSize.value--;
                          }
                        },
                        tooltip: 'Betűméret csökkentése',
                      ),
                      Text('${fontSize.toInt()}pt'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          if (fontSize < 24.0) {
                            _editorFontSize.value++;
                          }
                        },
                        tooltip: 'Betűméret növelése',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Editor
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: SizedBox(
                    height: 300,
                    child: ValueListenableBuilder<double>(
                        valueListenable: _editorFontSize,
                        builder: (context, fontSize, child) {
                          return TextField(
                            controller: _htmlContentController,
                            onChanged: (value) {
                              if (_tabController.index == 1) {
                                setState(() {
                                  _previewIframeElement.src =
                                      'data:text/html;charset=utf-8,${Uri.encodeComponent(value)}';
                                });
                              }
                            },
                            style: TextStyle(
                                fontSize: fontSize, fontFamily: 'monospace'),
                            maxLines: 15,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              hintText: 'Írd ide a HTML tartalmat...',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          );
                        }),
                  ),
                ),
                // Preview
                if (_selectedType == 'dynamic_quiz')
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _getQuizQuestions(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError ||
                          !snapshot.hasData ||
                          snapshot.data!.isEmpty) {
                        return const Center(
                            child: Text(
                                'Hiba a kvíz kérdések betöltésekor, vagy nincs kérdés a bankban.'));
                      }
                      return QuizViewer(questions: snapshot.data!);
                    },
                  )
                else
                  _showPreview
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: HtmlElementView(viewType: _previewViewId),
                        )
                      : const Center(
                          child: Text('Az előnézethez válts fület.')),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFreeAccessToggle() {
    return CheckboxListTile(
      value: _isFree,
      onChanged: (val) => setState(() => _isFree = val ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text('Ingyenes hozzáférés'),
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Címkék',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: _tags
              .map((tag) => Chip(
                    label: Text(tag),
                    onDeleted: () {
                      setState(() => _tags.remove(tag));
                    },
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tagController,
          decoration: InputDecoration(
            labelText: 'Új címke',
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                if (_tagController.text.isNotEmpty &&
                    !_tags.contains(_tagController.text)) {
                  setState(() {
                    _tags.add(_tagController.text);
                    _tagController.clear();
                  });
                }
              },
            ),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty && !_tags.contains(value)) {
              setState(() {
                _tags.add(value);
                _tagController.clear();
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildFileUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Fájlok',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickMp3File,
                    icon: const Icon(Icons.audiotrack),
                    label: const Text('MP3 Csere'),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                if (_existingAudioUrl != null || _selectedMp3File != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _deleteAudio = true;
                          _selectedMp3File = null;
                        });
                      },
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text('MP3 Törlés',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
              ],
            ),
            if (_selectedMp3File != null || _existingAudioUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _deleteAudio
                      ? 'Hangfájl törlésre megjelölve'
                      : 'Kiválasztva: ${_selectedMp3File != null ? _selectedMp3File!['name'] : 'Meglévő hangfájl'}',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: _deleteAudio ? Colors.red : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        // PDF CSERE + TÖRLÉS EGY SORBAN
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickPdfFile,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF Csere'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            if ((_existingPdfUrl != null && !_deletePdf) ||
                _selectedPdfFile != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  setState(() {
                    _deletePdf = true;
                    _selectedPdfFile = null;
                  });
                },
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                tooltip: 'PDF törlése',
              ),
            ],
          ],
        ),
        if (_existingPdfUrl != null && !_deletePdf) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _openUrl(_existingPdfUrl!),
                icon: const Icon(Icons.open_in_new),
                label: const Text('PDF Megnyitása'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'URL másolása',
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: _existingPdfUrl!));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('PDF URL vágólapra másolva')));
                  }
                },
                icon: const Icon(Icons.link),
              ),
            ],
          ),
        ],
        if (_selectedVideoFile != null &&
            _selectedVideoFile!['path'] != null &&
            !kIsWeb)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          )
      ],
    );
  }

  bool isFileValid(Map<String, dynamic>? file) {
    return file != null && file['name'] != null;
  }

  Future<void> _pickMp3File() async {
    const typeGroup = XTypeGroup(label: 'MP3', extensions: ['mp3']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('A hangfájl mérete nem haladhatja meg az 5 MB-ot!')),
        );
        return;
      }
      setState(() => _selectedMp3File = {
            'name': file.name,
            'size': bytes.length,
            'bytes': bytes
          });
      // új fájl választásakor ne legyen törlés jelölve
      setState(() => _deleteAudio = false);
    }
  }

  // PDF kiválasztása
  Future<void> _pickPdfFile() async {
    const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('A PDF mérete nem haladhatja meg a 10 MB-ot!')));
        return;
      }
      setState(() {
        _selectedPdfFile = {
          'name': file.name,
          'size': bytes.length,
          'bytes': bytes,
        };
      });
    }
  }

  Future<List<Map<String, dynamic>>> _getQuizQuestions() async {
    if (_selectedCategory != null) {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('question_banks')
          .where('category', isEqualTo: _selectedCategory)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final bank = querySnapshot.docs.first.data();
        final questions =
            List<Map<String, dynamic>>.from(bank['questions'] ?? []);
        questions.shuffle();
        return questions.take(10).toList();
      }
    }
    return [];
  }
}
