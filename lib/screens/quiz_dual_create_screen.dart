import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/app_messenger.dart';
import '../widgets/sidebar.dart';
import '../widgets/quiz_viewer_dual.dart';
import '../models/quiz_models.dart';

class QuizDualCreateScreen extends StatefulWidget {
  const QuizDualCreateScreen({super.key});

  @override
  State<QuizDualCreateScreen> createState() => _QuizDualCreateScreenState();
}

class _QuizDualCreateScreenState extends State<QuizDualCreateScreen> {
  final _titleController = TextEditingController();
  String? _selectedCategory;
  String? _selectedQuestionBankId;
  bool _isSaving = false;
  List<String> _categories = [];
  List<String> _sciences = [];
  String? _selectedScience;
  List<DocumentSnapshot> _questionBanks = [];
  final List<String> _tags = [];
  final _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadSciences();
    await _loadCategories();
    await _loadQuestionBanks();
    if (mounted) setState(() {});
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

  Future<void> _loadQuestionBanks() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('question_banks')
        .where('mode', isEqualTo: 'dual')
        .get();
    final compatibleBanks = <DocumentSnapshot>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final questions =
          List<Map<String, dynamic>>.from(data['questions'] ?? []);
      if (questions.isEmpty) continue;
      final allValid = questions.every((q) {
        final options = (q['options'] as List).cast<Map<String, dynamic>>();
        final correctCnt = options.where((o) => o['isCorrect'] == true).length;
        return correctCnt == 2;
      });
      if (allValid) compatibleBanks.add(doc);
    }
    if (mounted) _questionBanks = compatibleBanks;
  }

  Future<void> _createQuiz() async {
    if (_titleController.text.isEmpty ||
        _selectedScience == null ||
        _selectedCategory == null ||
        _selectedQuestionBankId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Minden mező kitöltése kötelező!')));
      return;
    }

    final trimmedTitle = _titleController.text.trim();
    final dupSnap = await FirebaseFirestore.instance
        .collection('notes')
        .where('title', isEqualTo: trimmedTitle)
        .where('type', isEqualTo: 'dynamic_quiz_dual')
        .where('category', isEqualTo: _selectedCategory)
        .limit(1)
        .get();
    if (!mounted) return; // ensure widget still active
    if (dupSnap.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Már létezik ilyen című, típusú és kategóriájú jegyzet!')));
      return;
    }

    final bankDoc = await FirebaseFirestore.instance
        .collection('question_banks')
        .doc(_selectedQuestionBankId)
        .get();
    if (!mounted) return;
    if (!bankDoc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hiba: A kérdésbank nem található.')));
      return;
    }
    final bankData = bankDoc.data()!;
    final questions =
        List<Map<String, dynamic>>.from(bankData['questions'] ?? []);
    final invalidQuestions = questions.where((q) {
      final options = (q['options'] as List).cast<Map<String, dynamic>>();
      final correctCount = options.where((o) => o['isCorrect'] == true).length;
      return correctCount != 2;
    }).toList();

    if (!mounted) return;
    if (invalidQuestions.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'A kiválasztott kérdésbank minden kérdésének pontosan 2 helyes válasszal kell rendelkeznie.')));
      return;
    }

    setState(() => _isSaving = true);
    for (final tag in _tags) {
      FirebaseFirestore.instance.collection('tags').doc(tag).set({'name': tag});
    }
    try {
      await FirebaseFirestore.instance.collection('notes').add({
        'title': _titleController.text,
        'category': _selectedCategory,
        'science': _selectedScience,
        'questionBankId': _selectedQuestionBankId,
        'type': 'dynamic_quiz_dual',
        'status': 'Draft',
        'createdAt': Timestamp.now(),
        'modified': Timestamp.now(),
        'tags': _tags,
      });
      if (mounted) {
        AppMessenger.showSuccess('Jegyzet sikeresen létrehozva!');
        context.go('/notes');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hiba: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Címkék',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _tags
              .map((tag) => Chip(
                  label: Text(tag),
                  onDeleted: () => setState(() => _tags.remove(tag))))
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
          onSubmitted: (val) {
            if (val.isNotEmpty && !_tags.contains(val)) {
              setState(() {
                _tags.add(val);
                _tagController.clear();
              });
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredBanks = _selectedCategory == null
        ? _questionBanks
        : _questionBanks
            .where((bank) => bank['category'] == _selectedCategory)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Új 2-válaszos Dinamikus Kvíz'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/notes'),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => context.go('/notes'),
            child: const Text('Mégse'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _createQuiz,
            icon: _isSaving
                ? const CircularProgressIndicator()
                : const Icon(Icons.save),
            label: const Text('Mentés'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'dynamic_quiz_dual_create'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                      controller: _titleController,
                      decoration:
                          const InputDecoration(labelText: 'Kvíz címe')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedScience,
                    items: _sciences
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) => setState(() {
                      _selectedScience = val;
                      _selectedCategory = null;
                      _selectedQuestionBankId = null;
                      _loadCategories();
                    }),
                    decoration: const InputDecoration(labelText: 'Tudomány'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: _selectedScience == null
                        ? null
                        : (val) => setState(() {
                              _selectedCategory = val;
                              _selectedQuestionBankId = null;
                            }),
                    decoration: InputDecoration(
                      labelText: 'Kategória',
                      fillColor:
                          _selectedScience == null ? Colors.grey[100] : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTagsSection(),
                  const SizedBox(height: 16),
                  if (_selectedCategory != null)
                    DropdownButtonFormField<String>(
                      initialValue: _selectedQuestionBankId,
                      items: filteredBanks
                          .map((doc) => DropdownMenuItem(
                              value: doc.id, child: Text(doc['name'])))
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedQuestionBankId = val);
                      },
                      decoration: const InputDecoration(
                          labelText: 'Válassz Kérdésbankot'),
                    ),
                  const SizedBox(height: 24),
                  if (_selectedQuestionBankId != null)
                    ElevatedButton.icon(
                      onPressed: _showQuizPreview,
                      icon: const Icon(Icons.visibility),
                      label: const Text('Kvíz Előnézet'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuizPreview() async {
    if (_selectedQuestionBankId == null) return;

    final bankDoc = await FirebaseFirestore.instance
        .collection('question_banks')
        .doc(_selectedQuestionBankId)
        .get();
    if (!bankDoc.exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hiba: A kérdésbank nem található.')));
      }
      return;
    }
    final bank = bankDoc.data()!;
    final questions = List<Map<String, dynamic>>.from(bank['questions'] ?? []);
    questions.shuffle();
    final selectedQuestions =
        questions.take(10).map((q) => Question.fromMap(q)).toList();

    if (selectedQuestions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ez a kérdésbank nem tartalmaz kérdéseket.')));
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          contentPadding: const EdgeInsets.all(8),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            child: QuizViewerDual(
              questions: selectedQuestions,
              onQuizComplete: (result) {
                // Handle quiz completion in preview mode
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Előnézet eredménye: ${result.score}/${result.totalQuestions}'),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Bezárás'),
            )
          ],
        ),
      );
    }
  }
}
