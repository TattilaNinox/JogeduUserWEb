import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:orlomed_admin_web/core/app_messenger.dart';
import 'package:orlomed_admin_web/core/firebase_config.dart';
import 'package:orlomed_admin_web/widgets/sidebar.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

class PublicDocumentEditScreen extends StatefulWidget {
  final String? documentId;

  const PublicDocumentEditScreen({super.key, this.documentId});

  @override
  State<PublicDocumentEditScreen> createState() =>
      _PublicDocumentEditScreenState();
}

class _PublicDocumentEditScreenState extends State<PublicDocumentEditScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  final _titleController = TextEditingController();
  final _versionController = TextEditingController();
  final _htmlContentController = TextEditingController();
  String? _selectedCategory;
  String _selectedLanguage = 'hu';

  late final TabController _tabController;
  late final String _previewViewId;
  final web.HTMLIFrameElement _previewIframeElement = web.HTMLIFrameElement();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _previewViewId = 'public-doc-preview-${widget.documentId ?? 'new'}';

    _previewIframeElement
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none';

    ui_web.platformViewRegistry.registerViewFactory(
        _previewViewId, (int viewId) => _previewIframeElement);

    if (widget.documentId != null) {
      _loadDocumentData();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _versionController.dispose();
    _htmlContentController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocumentData() async {
    try {
      final doc = await FirebaseConfig.publicFirestore
          .collection('public_documents')
          .doc(widget.documentId)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _titleController.text = data['title'] ?? '';
          _versionController.text = data['version'] ?? '';
          _htmlContentController.text = data['content'] ?? '';
          _selectedCategory = data['category'];
          _selectedLanguage = data['language'] ?? 'hu';
          _isLoading = false;
        });
      } else {
        throw Exception('Dokumentum nem található.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Hiba a dokumentum betöltésekor: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveDocument() async {
    if (_titleController.text.isEmpty || _selectedCategory == null) {
      AppMessenger.showError('A cím és a kategória megadása kötelező!');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final data = {
        'title': _titleController.text,
        'category': _selectedCategory,
        'language': _selectedLanguage,
        'version': _versionController.text,
        'content': _htmlContentController.text,
        'publishedAt': FieldValue.serverTimestamp(),
      };

      if (widget.documentId == null) {
        // Create new document
        await FirebaseConfig.publicFirestore
            .collection('public_documents')
            .add(data);
        AppMessenger.showSuccess('Dokumentum sikeresen létrehozva!');
      } else {
        // Update existing document
        await FirebaseConfig.publicFirestore
            .collection('public_documents')
            .doc(widget.documentId)
            .update(data);
        AppMessenger.showSuccess('Dokumentum sikeresen frissítve!');
      }
      if (mounted) context.go('/public-documents');
    } catch (e) {
      AppMessenger.showError('Hiba a mentés során: $e');
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
        title: Text(widget.documentId == null
            ? 'Új Nyilvános Dokumentum'
            : 'Dokumentum Szerkesztése'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/public-documents')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: ElevatedButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: const Text('Mentés'),
              onPressed: _isSaving ? null : _saveDocument,
            ),
          )
        ],
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'public_documents'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          flex: 3,
                          child: _buildTextField(
                              _titleController, 'Dokumentum címe')),
                      const SizedBox(width: 16),
                      Expanded(flex: 1, child: _buildCategoryDropdown()),
                      const SizedBox(width: 16),
                      Expanded(flex: 1, child: _buildLanguageDropdown()),
                      const SizedBox(width: 16),
                      Expanded(
                          flex: 1,
                          child: _buildTextField(
                              _versionController, 'Verzió (pl. 1.0)')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildEditorTabs(),
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
      initialValue: _selectedCategory,
      items: const [
        DropdownMenuItem(value: 'aszf', child: Text('ÁSZF')),
        DropdownMenuItem(value: 'adatvedelmi', child: Text('Adatvédelem')),
        DropdownMenuItem(value: 'fioktorles', child: Text('Fióktörlés')),
      ],
      onChanged: (newValue) => setState(() => _selectedCategory = newValue),
      decoration: const InputDecoration(
        labelText: 'Kategória',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildLanguageDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedLanguage,
      items: const [
        DropdownMenuItem(value: 'hu', child: Text('Magyar')),
        DropdownMenuItem(value: 'en', child: Text('English')),
      ],
      onChanged: (newValue) => setState(() => _selectedLanguage = newValue!),
      decoration: const InputDecoration(
        labelText: 'Nyelv',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildEditorTabs() {
    return Expanded(
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Szerkesztő'), Tab(text: 'Előnézet')],
            onTap: (index) {
              if (index == 1) {
                // Preview tab
                setState(() {
                  _previewIframeElement.src =
                      'data:text/html;charset=utf-8,${Uri.encodeComponent(_htmlContentController.text)}';
                });
              }
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Editor
                TextField(
                  controller: _htmlContentController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Írd ide a HTML tartalmat...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                  onChanged: (value) {
                    if (_tabController.index == 1) {
                      _previewIframeElement.src =
                          'data:text/html;charset=utf-8,${Uri.encodeComponent(value)}';
                    }
                  },
                ),
                // Preview
                HtmlElementView(viewType: _previewViewId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
