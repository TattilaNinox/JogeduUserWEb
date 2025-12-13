import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/sidebar.dart';
import 'package:excel/excel.dart';
import 'package:web/web.dart' as web;
import 'package:file_selector/file_selector.dart';
import 'dart:convert';

class QuestionBankEditScreen extends StatefulWidget {
  final String bankId;
  const QuestionBankEditScreen({super.key, required this.bankId});

  @override
  State<QuestionBankEditScreen> createState() => _QuestionBankEditScreenState();
}

class _QuestionBankEditScreenState extends State<QuestionBankEditScreen> {
  // Segédfüggvény az Excel cellákban található "igaz" értékek felismeréséhez.
  bool _isTrueValue(dynamic cellValue) {
    if (cellValue == null) return false;
    final normalized = cellValue.toString().trim().toUpperCase();
    // Elfogadott jelölések a helyes válaszra
    const truthy = {
      'IGAZ', // teljes szó
      'I', // rövidítés
      'TRUE',
      'T',
      'YES',
      'Y',
      '1',
      'X',
      '✔',
      'HELYES'
    };
    return truthy.contains(normalized);
  }

  final _nameController = TextEditingController();
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;
  String? _selectedCategory;
  List<String> _categories = [];
  List<String> _sciences = [];
  String? _selectedScience;
  final List<String> _modes = ['single', 'dual'];
  String _selectedMode = 'single';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadSciences();
    await _loadCategories();
    await _loadBank();
    if (mounted) {
      setState(() => _isLoading = false);
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

  Future<void> _loadBank() async {
    final doc = await FirebaseFirestore.instance
        .collection('question_banks')
        .doc(widget.bankId)
        .get();
    if (doc.exists) {
      final data = doc.data()!;
      _nameController.text = data['name'] ?? '';
      _selectedScience = data['science'];
      _selectedCategory = data['category'];
      _selectedMode = data['mode'] ?? 'single';
      _questions = List<Map<String, dynamic>>.from(data['questions'] ?? []);
    }
  }

  Future<void> _saveBank() async {
    if (_nameController.text.trim().isEmpty ||
        _selectedScience == null ||
        _selectedCategory == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('A név, tudomány és kategória kitöltése kötelező!')),
        );
      }
      return;
    }

    // validate questions correct count
    for (final q in _questions) {
      final opts = (q['options'] as List<dynamic>).cast<Map<String, dynamic>>();
      final correctCnt = opts.where((o) => o['isCorrect'] == true).length;
      if ((_selectedMode == 'single' && correctCnt != 1) ||
          (_selectedMode == 'dual' && correctCnt != 2)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Minden kérdésnél a kiválasztott típusnak megfelelő számú helyes választ kell bejelölni.')));
        }
        return;
      }
    }

    await FirebaseFirestore.instance
        .collection('question_banks')
        .doc(widget.bankId)
        .update({
      'name': _nameController.text.trim(),
      'science': _selectedScience,
      'category': _selectedCategory,
      'mode': _selectedMode,
      'questions': _questions,
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Kérdésbank mentve!')));
    }
  }

  void _addQuestion() {
    setState(() {
      _questions.add({
        'question': 'Új kérdés',
        'options': [
          {'text': 'Válasz 1', 'isCorrect': true, 'rationale': ''},
          {'text': 'Válasz 2', 'isCorrect': false, 'rationale': ''},
          {'text': 'Válasz 3', 'isCorrect': false, 'rationale': ''},
          {'text': 'Válasz 4', 'isCorrect': false, 'rationale': ''},
        ]
      });
    });
  }

  Future<void> _exportToExcel() async {
    final excel = Excel.createExcel();
    final Sheet sheetObject = excel['Kérdések'];
    final header = [
      'Kérdés',
      'Válasz 1',
      'V1 Helyes',
      'V1 Indoklás',
      'Válasz 2',
      'V2 Helyes',
      'V2 Indoklás',
      'Válasz 3',
      'V3 Helyes',
      'V3 Indoklás',
      'Válasz 4',
      'V4 Helyes',
      'V4 Indoklás',
    ];
    sheetObject.appendRow(header);

    for (final question in _questions) {
      final List<dynamic> row = [];
      row.add(question['question'] as String? ?? '');
      final options =
          (question['options'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final option in options) {
        row.add(option['text'] as String? ?? '');
        row.add((option['isCorrect'] as bool? ?? false) ? 'IGAZ' : 'HAMIS');
        row.add(option['rationale'] as String? ?? '');
      }
      sheetObject.appendRow(row);
    }
    final bytes = excel.save();
    if (bytes != null) {
      // Egyszerűbb megközelítés a fájl letöltéshez
      final dataUrl =
          'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,${base64Encode(bytes)}';
      web.HTMLAnchorElement()
        ..href = dataUrl
        ..setAttribute('download', '${_nameController.text.trim()}.xlsx')
        ..click();
    }
  }

  Future<void> _importFromExcel() async {
    const typeGroup = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hiba: Nem található munkalap.')));
      return;
    }
    final newQuestions = <Map<String, dynamic>>[];
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every(
          (cell) => cell == null || cell.value.toString().trim().isEmpty)) {
        continue;
      }
      try {
        final questionText = row[0]?.value.toString().trim() ?? '';
        if (questionText.isEmpty) continue;
        final options = <Map<String, dynamic>>[];
        for (var j = 0; j < 4; j++) {
          final optionText = row[1 + j * 3]?.value.toString().trim() ?? '';
          final rawCorrectCell = row[2 + j * 3]?.value;
          final rationale = row[3 + j * 3]?.value.toString().trim() ?? '';
          options.add({
            'text': optionText,
            'isCorrect': _isTrueValue(rawCorrectCell),
            'rationale': rationale
          });
        }
        final correctCnt =
            options.where((opt) => opt['isCorrect'] == true).length;
        if ((_selectedMode == 'single' && correctCnt != 1) ||
            (_selectedMode == 'dual' && correctCnt != 2)) {
          throw Exception(
              'A(z) ${i + 1}. sorban a kiválasztott kérdés-típusnak megfelelően ${_selectedMode == 'single' ? '1' : '2'} helyes választ kell megjelölni, jelenleg $correctCnt van.');
        }
        newQuestions.add({'question': questionText, 'options': options});
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Hiba a(z) ${i + 1}. sor feldolgozásakor: $e')));
        return;
      }
    }
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importálás megerősítése'),
        content: Text(
            'A fájlban ${newQuestions.length} kérdés található. A jelenlegi kérdésbankban ${_questions.length} kérdés van. Mit szeretnél tenni?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Mégse')),
          TextButton(
              onPressed: () => Navigator.of(context).pop('append'),
              child: const Text('Hozzáfűzés')),
          TextButton(
              onPressed: () => Navigator.of(context).pop('replace'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Felülírás')),
        ],
      ),
    );
    if (action == 'append') {
      final existing = _questions
          .map((q) => (q['question'] as String).trim().toLowerCase())
          .toSet();
      final uniqueToAdd = newQuestions
          .where((q) => !existing
              .contains((q['question'] as String).trim().toLowerCase()))
          .toList();
      final skipped = newQuestions.length - uniqueToAdd.length;
      setState(() => _questions.addAll(uniqueToAdd));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Import sikeres: ${uniqueToAdd.length} új kérdés hozzáadva${skipped > 0 ? ', $skipped duplikált kihagyva' : ''}. Ne felejts el menteni.')));
      }
    } else if (action == 'replace') {
      setState(() => _questions = newQuestions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Sikeres importálás: kérdések felülírva. Ne felejts el menteni.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Betöltés...')),
          body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kérdésbank Szerkesztése'),
        actions: [
          IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _exportToExcel,
              tooltip: 'Exportálás Excelbe'),
          IconButton(
              icon: const Icon(Icons.file_upload),
              onPressed: _importFromExcel,
              tooltip: 'Importálás Excelből'),
          const SizedBox(width: 12),
          IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveBank,
              tooltip: 'Mentés'),
        ],
      ),
      body: Row(
        children: [
          const Sidebar(selectedMenu: 'question_banks'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Mód kiválasztása (1 vagy 2 helyes válasz)
                  DropdownButtonFormField<String>(
                    value: _selectedMode,
                    items: _modes
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m == 'single'
                                  ? '1 helyes válasz/kérdés'
                                  : '2 helyes válasz/kérdés'),
                            ))
                        .toList(),
                    onChanged: _questions.isEmpty
                        ? (val) =>
                            setState(() => _selectedMode = val ?? 'single')
                        : null,
                    decoration:
                        const InputDecoration(labelText: 'Kérdések típusa'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                  labelText: 'Kérdésbank neve'))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedScience,
                          items: _sciences
                              .map((String science) => DropdownMenuItem<String>(
                                  value: science, child: Text(science)))
                              .toList(),
                          onChanged: (newValue) {
                            setState(() {
                              _selectedScience = newValue;
                              _selectedCategory = null;
                            });
                            _loadCategories();
                          },
                          decoration:
                              const InputDecoration(labelText: 'Tudomány'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          items: _categories
                              .map((String category) =>
                                  DropdownMenuItem<String>(
                                      value: category, child: Text(category)))
                              .toList(),
                          onChanged: _selectedScience == null
                              ? null
                              : (newValue) =>
                                  setState(() => _selectedCategory = newValue),
                          decoration: InputDecoration(
                            labelText: 'Kategória',
                            fillColor: _selectedScience == null
                                ? Colors.grey[100]
                                : Colors.white,
                            filled: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _questions.length,
                      itemBuilder: (context, index) =>
                          _buildQuestionEditor(_questions[index], index),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: _addQuestion, child: const Icon(Icons.add)),
    );
  }

  Widget _buildQuestionEditor(Map<String, dynamic> question, int index) {
    final questionController =
        TextEditingController(text: question['question'] as String? ?? '');
    questionController.addListener(
        () => _questions[index]['question'] = questionController.text);
    final options =
        (question['options'] as List<dynamic>).cast<Map<String, dynamic>>();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: questionController,
                        decoration:
                            InputDecoration(labelText: 'Kérdés ${index + 1}'))),
                IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => setState(() => _questions.removeAt(index)))
              ],
            ),
            const SizedBox(height: 16),
            ...List.generate(4, (optionIndex) {
              final option = options[optionIndex];
              final optionController =
                  TextEditingController(text: option['text'] as String? ?? '');
              optionController.addListener(
                  () => options[optionIndex]['text'] = optionController.text);
              final rationaleController = TextEditingController(
                  text: option['rationale'] as String? ?? '');
              rationaleController.addListener(() =>
                  options[optionIndex]['rationale'] = rationaleController.text);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    _selectedMode == 'single'
                        // ignore: deprecated_member_use
                        ? Radio<bool>(
                            // ignore: deprecated_member_use
                            value: true,
                            // ignore: deprecated_member_use
                            groupValue: option['isCorrect'] as bool? ?? false,
                            // ignore: deprecated_member_use
                            onChanged: (value) => setState(() {
                              for (var opt in options) {
                                opt['isCorrect'] = false;
                              }
                              option['isCorrect'] = true;
                            }),
                          )
                        : Checkbox(
                            value: option['isCorrect'] as bool? ?? false,
                            onChanged: (val) => setState(() {
                              if (val == true) {
                                // ha már 2 helyes van, ne engedjük
                                final currentCorrect = options
                                    .where((o) => o['isCorrect'] == true)
                                    .length;
                                if (currentCorrect >= 2) return;
                              }
                              option['isCorrect'] = val;
                            }),
                          ),
                    Expanded(
                        child: TextField(
                            controller: optionController,
                            decoration: InputDecoration(
                                labelText: 'Válasz ${optionIndex + 1}'))),
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: TextField(
                                controller: rationaleController,
                                decoration: InputDecoration(
                                    labelText:
                                        'Indoklás ${optionIndex + 1}')))),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
