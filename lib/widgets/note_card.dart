import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/filter_storage.dart';

class NoteCard extends StatelessWidget {
  final String id;
  final String title;
  final String? category;
  final bool hasDoc;
  final bool hasAudio;
  final bool hasVideo;
  final String type; // standard, interactive, deck, dynamic_quiz
  final int? deckCount;

  const NoteCard({
    super.key,
    required this.id,
    required this.title,
    this.category,
    required this.hasDoc,
    required this.hasAudio,
    required this.hasVideo,
    required this.type,
    this.deckCount,
  });

  IconData _typeIcon() {
    switch (type) {
      case 'deck':
        return Icons.style;
      case 'interactive':
        return Icons.touch_app;
      case 'dynamic_quiz':
        return Icons.quiz;
      case 'dynamic_quiz_dual':
        return Icons.quiz_outlined;
      case 'memoriapalota_allomasok':
        return Icons.train;
      default:
        return Icons.menu_book;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: () {
          // Menteni a szűrők állapotát navigáció előtt
          FilterStorage.saveFilters(
            searchText: FilterStorage.searchText ?? '',
            status: FilterStorage.status,
            category: FilterStorage.category,
            science: FilterStorage.science,
            tag: FilterStorage.tag,
            type: FilterStorage.type,
          );

          if (type == 'interactive' ||
              type == 'dynamic_quiz' ||
              type == 'dynamic_quiz_dual') {
            context.go('/interactive-note/$id');
          } else if (type == 'deck') {
            context.go('/deck/$id/view');
          } else if (type == 'memoriapalota_allomasok') {
            context.go('/memoriapalota-allomas/$id');
          } else {
            context.go('/note/$id');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_typeIcon(), color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (category != null && category!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(category!, style: const TextStyle(fontSize: 12)),
              ],
              const Spacer(),
              Row(
                children: [
                  if (hasDoc)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child:
                          Icon(Icons.description, size: 16, color: Colors.blue),
                    ),
                  if (hasAudio)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child:
                          Icon(Icons.audiotrack, size: 16, color: Colors.green),
                    ),
                  if (hasVideo)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child:
                          Icon(Icons.movie, size: 16, color: Colors.deepOrange),
                    ),
                  if (type == 'deck' && deckCount != null) ...[
                    const Spacer(),
                    Text('${deckCount!} kártya',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ]
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
