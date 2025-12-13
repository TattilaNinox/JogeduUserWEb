import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import '../core/app_messenger.dart';
import 'package:video_player/video_player.dart';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:html/parser.dart' show parse;
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

import '../widgets/sidebar.dart';

class InteractiveNoteCreateScreen extends StatefulWidget {
  const InteractiveNoteCreateScreen({super.key});

  @override
  State<InteractiveNoteCreateScreen> createState() =>
      _InteractiveNoteCreateScreenState();
}

class _InteractiveNoteCreateScreenState
    extends State<InteractiveNoteCreateScreen>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _htmlContentController = TextEditingController();
  String? _selectedCategory;
  Map<String, dynamic>? _selectedMp3File;
  Map<String, dynamic>? _selectedVideoFile;
  bool _isUploading = false;
  List<String> _categories = [];
  List<String> _sciences = [];
  String? _selectedScience;
  VideoPlayerController? _videoController;
  final List<String> _tags = [];
  final _tagController = TextEditingController();
  late TabController _tabController;
  final ValueNotifier<double> _editorFontSize = ValueNotifier<double>(9.0);
  late final String _previewViewId;
  final web.HTMLIFrameElement _previewIframeElement = web.HTMLIFrameElement();
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _previewViewId = 'interactive-note-create-preview-iframe-$hashCode';

    _previewIframeElement
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none';

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
        _previewViewId, (int viewId) => _previewIframeElement);

    _loadCategories();
    _loadSciences();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _htmlContentController.dispose();
    _videoController?.dispose();
    _tagController.dispose();
    _tabController.dispose();
    _editorFontSize.dispose();
    super.dispose();
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
      setState(() {
        _sciences = snapshot.docs.map((doc) => doc['name'] as String).toList();
      });
    }
  }

  bool isFileValid(Map<String, dynamic>? file) {
    return file != null &&
        file['bytes'] != null &&
        (file['bytes'] as List<int>).isNotEmpty;
  }

  Future<void> _pickMp3File() async {
    const typeGroup = XTypeGroup(
      label: 'MP3',
      extensions: ['mp3'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        setState(() => _selectedMp3File = {
              'name': file.name,
              'size': bytes.length,
              'bytes': bytes,
            });
      } else {
        debugPrint(
            'Az MP3 fájl nem tartalmaz adatot vagy nem sikerült betölteni.');
      }
    }
  }

  Future<void> _pickVideoFile() async {
    const typeGroup = XTypeGroup(
      label: 'Video',
      extensions: ['mp4', 'mov', 'avi'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        if (bytes.length > 5 * 1024 * 1024) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('A videófájl mérete nem haladhatja meg az 5 MB-ot!')),
          );
          return;
        }
        setState(() => _selectedVideoFile = {
              'name': file.name,
              'size': bytes.length,
              'bytes': bytes,
              'path': file.path,
            });
        _videoController?.dispose();
        if (!kIsWeb) {
          _videoController = VideoPlayerController.file(File(file.path));
          await _videoController!.initialize();
          if (!mounted) return;
          setState(() {});
        }
      } else {
        debugPrint(
            'A videófájl nem tartalmaz adatot vagy nem sikerült betölteni.');
      }
    }
  }

  Future<void> _uploadNote() async {
    final htmlContent = _htmlContentController.text;

    if (_titleController.text.isEmpty ||
        _selectedCategory == null ||
        htmlContent.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('A cím, kategória és a tartalom kötelező!')),
        );
      }
      return;
    }

    final trimmedTitle = _titleController.text.trim();
    final dupSnap = await FirebaseFirestore.instance
        .collection('notes')
        .where('title', isEqualTo: trimmedTitle)
        .where('type', isEqualTo: 'interactive')
        .where('category', isEqualTo: _selectedCategory)
        .limit(1)
        .get();
    if (dupSnap.docs.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Már létezik ilyen című, típusú és kategóriájú jegyzet!'),
        ));
      }
      return;
    }

    setState(() => _isUploading = true);

    try {
      final noteRef = FirebaseFirestore.instance.collection('notes').doc();
      final noteId = noteRef.id;

      // Címkék mentése a 'tags' kollekcióba
      for (final tag in _tags) {
        FirebaseFirestore.instance
            .collection('tags')
            .doc(tag)
            .set({'name': tag});
      }

      String? mp3Url;
      if (isFileValid(_selectedMp3File)) {
        final mp3Ref = FirebaseStorage.instance
            .ref('notes/$noteId/${_selectedMp3File!['name']}');
        await mp3Ref.putData(
            Uint8List.fromList(_selectedMp3File!['bytes'] as List<int>));
        mp3Url = await mp3Ref.getDownloadURL();
      }

      String? videoUrl;
      if (isFileValid(_selectedVideoFile)) {
        final videoRef = FirebaseStorage.instance
            .ref('notes/$noteId/${_selectedVideoFile!['name']}');
        await videoRef.putData(
            Uint8List.fromList(_selectedVideoFile!['bytes'] as List<int>));
        videoUrl = await videoRef.getDownloadURL();
      }

      // Firestore mentés
      final noteData = {
        'title': _titleController.text,
        'category': _selectedCategory,
        'science': _selectedScience,
        'status': 'Draft',
        'modified': Timestamp.now(),
        'pages': [htmlContent],
        'type': 'interactive',
        'tags': _tags,
      };
      if (mp3Url != null) noteData['audioUrl'] = mp3Url;
      if (videoUrl != null) noteData['videoUrl'] = videoUrl;

      await noteRef.set(noteData);

      if (mounted) {
        AppMessenger.showSuccess('Interaktív jegyzet sikeresen létrehozva!');

        setState(() {
          _titleController.clear();
          _htmlContentController.clear();
          _selectedCategory = null;
          _selectedScience = null;
          _selectedMp3File = null;
          _selectedVideoFile = null;
          _videoController?.dispose();
          _videoController = null;
          _tags.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba történt: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 249, 250, 251),
      appBar: AppBar(
        title: const Text('Új interaktív jegyzet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/notes'),
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/notes'),
            child: const Text('Mégse'),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: ElevatedButton.icon(
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: const Text('Mentés'),
              onPressed: _isUploading ? null : _uploadNote,
            ),
          )
        ],
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'interactive_note_create'),
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
                              child: _buildScienceDropdown(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildCategoryDropdown(),
                        const SizedBox(height: 24),
                        _buildEditorAndPreview(),
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

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
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
      value: _selectedScience,
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
                            if (fontSize < 12.0) {
                              _editorFontSize.value++;
                            }
                          },
                          tooltip: 'Betűméret növelése',
                        ),
                      ],
                    );
                  }),
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
                _showPreview
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: HtmlElementView(viewType: _previewViewId),
                      )
                    : const Center(
                        child: Text(
                            'Az előnézethez válts a szerkesztőre és írj be HTML tartalmat.')),
              ],
            ),
          )
        ],
      ),
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
        _buildFileUploadButton(
          label: 'MP3 Feltöltés',
          icon: Icons.audiotrack,
          file: _selectedMp3File,
          onPressed: _pickMp3File,
        ),
        const SizedBox(height: 12),
        _buildFileUploadButton(
          label: 'Videó Feltöltés',
          icon: Icons.videocam,
          file: _selectedVideoFile,
          onPressed: _pickVideoFile,
        ),
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

  Widget _buildFileUploadButton({
    required String label,
    required IconData icon,
    required Map<String, dynamic>? file,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        if (file != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Kiválasztva: ${file['name']}',
              style: const TextStyle(fontStyle: FontStyle.italic),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
