import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Egységes irodalom / forrás lista képernyő.
///
/// A források mostantól a `notes` gyűjteményben találhatók
/// `type = "source"` mezővel, így mindenhol ugyanúgy kezelhetők,
/// mint a többi jegyzet.
class ReferencesScreen extends StatelessWidget {
  const ReferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Források / Irodalom')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('notes')
            .where('type', isEqualTo: 'source')
            .orderBy('order')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Nincs rögzített forrás.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, index) {
              final data = docs[index].data();
              final title = data['title'] ?? '';
              final url = data['url'] ?? '';
              final description = data['description'] ?? '';
              final category = data['category'] ?? '';
              final tagsList = (data['tags'] is List)
                  ? (data['tags'] as List).cast<String>()
                  : <String>[];
              final tagsText = tagsList.join(', ');

              List<InlineSpan> spans = [
                TextSpan(
                    text: '${index + 1}. ',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(
                  text: title,
                  style: TextStyle(
                    color: url.isNotEmpty ? Colors.blue : null,
                    decoration: url.isNotEmpty
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                  recognizer: url.isNotEmpty
                      ? (TapGestureRecognizer()
                        ..onTap = () async {
                          await launchUrl(Uri.parse(url),
                              mode: LaunchMode.externalApplication,
                              webOnlyWindowName: '_blank');
                        })
                      : null,
                ),
              ];

              if (description.isNotEmpty) {
                spans.add(TextSpan(text: ' – $description'));
              }
              if (category.isNotEmpty) {
                spans.add(TextSpan(text: '  [Kategória: $category]'));
              }
              if (tagsText.isNotEmpty) {
                spans.add(TextSpan(text: '  [Címkék: $tagsText]'));
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RichText(
                    text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: spans)),
              );
            },
          );
        },
      ),
    );
  }
}
