import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NoteDetailPage extends StatefulWidget {
  final String noteId;

  const NoteDetailPage({super.key, required this.noteId});

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  DocumentSnapshot? _note;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  void _loadNote() async {
    final doc = await FirebaseFirestore.instance
        .collection('notes')
        .doc(widget.noteId)
        .get();

    if (doc.exists) {
      setState(() {
        _note = doc;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_note == null) {
      return const Scaffold(
          body: Center(child: Text('A jegyzet nem található.')));
    }

    final data = _note!.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? 'Cím nélkül';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: const Center(
        child: Text('Jegyzet tartalom'),
      ),
    );
  }
}
