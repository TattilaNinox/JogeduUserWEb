import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/firebase_config.dart';
import '../theme/app_theme.dart';
import '../utils/filter_storage.dart';
import 'video_preview_player.dart';
import 'mini_audio_player.dart';
import 'quiz_viewer.dart';
import 'quiz_viewer_dual.dart';
import '../models/quiz_models.dart';

enum SortColumn { title, category, tags, status, modified }

class NoteTable extends StatefulWidget {
  final String searchText;
  final String? selectedStatus;
  final String? selectedCategory;
  final String? selectedScience;
  final String? selectedTag;
  final String? selectedType;
  final VoidCallback? onEmptyResults;

  const NoteTable({
    super.key,
    required this.searchText,
    required this.selectedStatus,
    required this.selectedCategory,
    required this.selectedScience,
    required this.selectedTag,
    required this.selectedType,
    this.onEmptyResults,
  });

  @override
  State<NoteTable> createState() => _NoteTableState();
}

class _NoteTableState extends State<NoteTable> {
  SortColumn _sortColumn = SortColumn.modified;
  bool _ascending = false;

  void _toggleSort(SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _ascending = !_ascending;
      } else {
        _sortColumn = column;
        // Alapértelmezett irány: szövegesnél növekvő, dátumnál csökkenő
        _ascending = column == SortColumn.modified ? false : true;
      }
    });
  }

  int _compareDocs(DocumentSnapshot a, DocumentSnapshot b) {
    final ad = a.data() as Map<String, dynamic>;
    final bd = b.data() as Map<String, dynamic>;
    int cmp;
    switch (_sortColumn) {
      case SortColumn.title:
        cmp = _str(ad['title']).compareTo(_str(bd['title']));
        break;
      case SortColumn.category:
        cmp = _str(ad['category']).compareTo(_str(bd['category']));
        break;
      case SortColumn.tags:
        cmp = _str((ad['tags'] ?? []).join(','))
            .compareTo(_str((bd['tags'] ?? []).join(',')));
        break;
      case SortColumn.status:
        cmp = _str(ad['status']).compareTo(_str(bd['status']));
        break;
      case SortColumn.modified:
        cmp = _date(ad['modified']).compareTo(_date(bd['modified']));
        break;
    }
    return _ascending ? cmp : -cmp;
  }

  String _str(Object? v) => (v ?? '').toString().toLowerCase();

  DateTime _date(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query =
        FirebaseConfig.firestore.collection('notes');

    if (widget.selectedStatus != null && widget.selectedStatus!.isNotEmpty) {
      query = query.where('status', isEqualTo: widget.selectedStatus);
    }
    if (widget.selectedCategory != null &&
        widget.selectedCategory!.isNotEmpty) {
      query = query.where('category', isEqualTo: widget.selectedCategory);
    }
    if (widget.selectedScience != null && widget.selectedScience!.isNotEmpty) {
      query = query.where('science', isEqualTo: widget.selectedScience);
    }
    if (widget.selectedTag != null && widget.selectedTag!.isNotEmpty) {
      query = query.where('tags', arrayContains: widget.selectedTag);
    }
    if (widget.selectedType != null && widget.selectedType!.isNotEmpty) {
      query = query.where('type', isEqualTo: widget.selectedType);
    }

    return Expanded(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        key: ValueKey(
            '${widget.selectedStatus}|${widget.selectedCategory}|${widget.selectedScience}|${widget.selectedTag}|${widget.selectedType}|${widget.searchText}'),
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
                child: Text('Hiba történt az adatok betöltésekor.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Nincsenek jegyzetek.'));
          }
          final notes = snapshot.data!.docs
              .where((d) => !(d.data()['deletedAt'] != null))
              .toList();
          if (notes.isEmpty) {
            // Ha van onEmptyResults callback, hívjuk meg
            if (widget.onEmptyResults != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onEmptyResults!();
              });
            }
            return const Center(child: Text('Nincsenek találatok.'));
          }
          final filteredNotes = notes.where((doc) {
            final data = doc.data();
            final title = (data['title'] ?? '');
            return title
                .toLowerCase()
                .contains(widget.searchText.toLowerCase());
          }).toList();

          if (filteredNotes.isEmpty) {
            // Ha van onEmptyResults callback, hívjuk meg
            if (widget.onEmptyResults != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onEmptyResults!();
              });
            }
            return const Center(child: Text('Nincsenek találatok.'));
          }

          // Rendezés a kiválasztott oszlop szerint
          filteredNotes.sort(_compareDocs);

          return LayoutBuilder(
            builder: (context, constraints) {
              Widget buildTable({required bool shrink}) {
                return Column(
                  children: [
                    _buildHeader(),
                    shrink
                        ? ListView.builder(
                            itemCount: filteredNotes.length,
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final doc = filteredNotes[index];
                              final data = doc.data();
                              final noteType =
                                  data['type'] as String? ?? 'standard';
                              if (noteType == 'deck') {
                                return _buildDeckCard(context, doc);
                              } else {
                                return _buildNoteRow(context, doc);
                              }
                            },
                          )
                        : Expanded(
                            child: ListView.builder(
                              itemCount: filteredNotes.length,
                              itemBuilder: (context, index) {
                                final doc = filteredNotes[index];
                                final data = doc.data();
                                final noteType =
                                    data['type'] as String? ?? 'standard';
                                if (noteType == 'deck') {
                                  return _buildDeckCard(context, doc);
                                } else {
                                  return _buildNoteRow(context, doc);
                                }
                              },
                            ),
                          ),
                  ],
                );
              }

              final tableWide = buildTable(shrink: false);
              final tableNarrow = buildTable(shrink: true);

              // Ha keskeny a viewport, csomagoljuk vízszintes scrollba.
              const minW = 800.0;
              if (constraints.maxWidth < minW) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: minW, child: tableNarrow),
                );
              }

              return tableWide;
            },
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    const TextStyle headerStyle =
        TextStyle(fontSize: 14, fontWeight: FontWeight.bold);

    Widget buildCell(String label, SortColumn column, int flex) {
      final bool isActive = _sortColumn == column;
      final icon = isActive
          ? (_ascending ? Icons.arrow_upward : Icons.arrow_downward)
          : null;
      return Expanded(
        flex: flex,
        child: InkWell(
          onTap: () => _toggleSort(column),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: headerStyle),
              if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 14, color: Colors.black54),
              ]
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF960018))),
        color: Color.fromARGB(255, 244, 245, 247),
      ),
      child: Row(
        children: [
          buildCell('Cím', SortColumn.title, 3),
          buildCell('Kategória', SortColumn.category, 1),
          buildCell('Címkék', SortColumn.tags, 1),
          const Expanded(flex: 3, child: Text('Fájlok', style: headerStyle)),
          const Expanded(flex: 2, child: Text('Műveletek', style: headerStyle)),
        ],
      ),
    );
  }

  Widget _buildNoteRow(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final title = (data['title'] ?? '');
    final category = (data['category'] ?? '');
    // final status = (data['status'] ?? '');
    // final displayStatus = status == 'Public' ? 'Published' : status;
    // final modified = (data['modified'] is Timestamp)
    //     ? (data['modified'] as Timestamp).toDate()
    //     : DateTime.now();
    final hasDocx =
        data['docxUrl'] != null && data['docxUrl'].toString().isNotEmpty;
    final hasAudio =
        data['audioUrl'] != null && data['audioUrl'].toString().isNotEmpty;
    final hasVideo =
        data['videoUrl'] != null && data['videoUrl'].toString().isNotEmpty;
    final noteType = data['type'] as String? ?? 'standard';
    final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();
    const TextStyle cellStyle = TextStyle(fontSize: 12);

    IconData getIconForNoteType(String type) {
      switch (type) {
        case 'deck':
          return Icons.style;
        case 'interactive':
          return Icons.touch_app;
        case 'dynamic_quiz':
          return Icons.quiz;
        case 'dynamic_quiz_dual':
          return Icons.quiz_outlined;
        case 'source':
          return Icons.source;
        case 'memoriapalota_allomasok':
          return Icons.train;
        default:
          return Icons.menu_book;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(getIconForNoteType(noteType),
                    color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                // Lakat ikonok eltávolítva felhasználói nézetben.
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: cellStyle.copyWith(
                        color: noteType == 'source'
                            ? const Color(0xFF009B77)
                            : null),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              category,
              style: cellStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                for (int i = 0; i < tags.length; i++) ...[
                  Text(tags[i],
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E90FF))),
                  if (i != tags.length - 1) const SizedBox(width: 12),
                ]
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasDocx)
                  Tooltip(
                    message: 'Dokumentum',
                    child: IconButton(
                      icon: const Icon(Icons.description, color: Colors.blue),
                      onPressed: () {
                        final googleDocsUrl =
                            'https://docs.google.com/viewer?url=${Uri.encodeComponent(data['docxUrl'])}&embedded=true';
                        launchUrl(Uri.parse(googleDocsUrl));
                      },
                    ),
                  ),
                if (hasAudio)
                  Align(
                    alignment: Alignment.center,
                    child: MiniAudioPlayer(
                      audioUrl: data['audioUrl'],
                      compact: true,
                    ),
                  ),
                if (hasVideo)
                  Tooltip(
                    message: 'Videó',
                    child: IconButton(
                      icon: const Icon(Icons.movie, color: Colors.deepOrange),
                      onPressed: () =>
                          _showVideoDialog(context, data['videoUrl']),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Szerkesztés, státusz-módosítás és törlés ikonok eltávolítva felhasználói nézetben.
                  _buildIconButton(
                      context, Icons.visibility, AppTheme.primaryColor, () {
                    // Menteni a szűrők állapotát navigáció előtt
                    FilterStorage.saveFilters(
                      searchText: widget.searchText,
                      status: widget.selectedStatus,
                      category: widget.selectedCategory,
                      science: widget.selectedScience,
                      tag: widget.selectedTag,
                      type: widget.selectedType,
                    );

                    // Az aktuális URL-t query paraméterként adjuk át (visszalépéshez)
                    final currentUri = GoRouterState.of(context).uri;
                    final fromParam = Uri.encodeComponent(currentUri.toString());

                    if (noteType == 'dynamic_quiz' ||
                        noteType == 'dynamic_quiz_dual') {
                      final questionBankId = data['questionBankId'] as String?;
                      if (questionBankId == null || questionBankId.isEmpty) {
                        _showSnackBar(context,
                            'Hiba: Ehhez a kvízhez nincs társítva kérdésbank.');
                        return;
                      }
                      _showQuizPreviewDialog(context, questionBankId,
                          dualMode: noteType == 'dynamic_quiz_dual');
                    } else if (noteType == 'interactive') {
                      context.go('/interactive-note/${doc.id}?from=$fromParam');
                    } else if (noteType == 'memoriapalota_allomasok') {
                      context.go('/memoriapalota-allomas/${doc.id}?from=$fromParam');
                    } else {
                      context.go('/note/${doc.id}?from=$fromParam');
                    }
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeckCard(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final title = data['title'] as String? ?? 'Névtelen pakli';
    final flashcards = data['flashcards'] as List<dynamic>? ?? [];
    final category = (data['category'] ?? '');
    // final status = (data['status'] ?? '');
    // final displayStatus = status == 'Public' ? 'Published' : status;
    // final modified = (data['modified'] is Timestamp)
    //     ? (data['modified'] as Timestamp).toDate()
    //     : DateTime.now();
    final hasDocx =
        data['docxUrl'] != null && data['docxUrl'].toString().isNotEmpty;
    final hasAudio =
        data['audioUrl'] != null && data['audioUrl'].toString().isNotEmpty;
    final hasVideo =
        data['videoUrl'] != null && data['videoUrl'].toString().isNotEmpty;
    final tags = (data['tags'] as List<dynamic>? ?? []).cast<String>();
    const TextStyle cellStyle = TextStyle(fontSize: 12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Icon(Icons.style, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                // Lakat ikonok eltávolítva.
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false),
                    if (flashcards.isNotEmpty)
                      Text('${flashcards.length} kártya',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              category,
              style: cellStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                for (int i = 0; i < tags.length; i++) ...[
                  Text(tags[i],
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E90FF))),
                  if (i != tags.length - 1) const SizedBox(width: 12),
                ]
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasDocx)
                  Tooltip(
                    message: 'Dokumentum',
                    child: IconButton(
                      icon: const Icon(Icons.description, color: Colors.blue),
                      onPressed: () {
                        final googleDocsUrl =
                            'https://docs.google.com/viewer?url=${Uri.encodeComponent(data['docxUrl'])}&embedded=true';
                        launchUrl(Uri.parse(googleDocsUrl));
                      },
                    ),
                  ),
                if (hasAudio)
                  Align(
                    alignment: Alignment.center,
                    child: MiniAudioPlayer(
                      audioUrl: data['audioUrl'],
                      compact: true,
                    ),
                  ),
                if (hasVideo)
                  Tooltip(
                    message: 'Videó',
                    child: IconButton(
                      icon: const Icon(Icons.movie, color: Colors.deepOrange),
                      onPressed: () =>
                          _showVideoDialog(context, data['videoUrl']),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIconButton(
                      context, Icons.visibility, AppTheme.primaryColor, () {
                    // Menteni a szűrők állapotát navigáció előtt
                    FilterStorage.saveFilters(
                      searchText: widget.searchText,
                      status: widget.selectedStatus,
                      category: widget.selectedCategory,
                      science: widget.selectedScience,
                      tag: widget.selectedTag,
                      type: widget.selectedType,
                    );
                    context.go('/deck/${doc.id}/view');
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(BuildContext context, IconData icon, Color color,
      VoidCallback onPressed) {
    String tooltip = '';
    switch (icon) {
      case Icons.edit:
        tooltip = 'Szerkesztés';
        break;
      case Icons.delete:
        tooltip = 'Törlés';
        break;
      case Icons.publish:
        tooltip = 'Publikálás';
        break;
      case Icons.visibility:
        tooltip = 'Előnézet';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: IconButton(
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        icon: Icon(icon, color: color, size: 18),
        onPressed: onPressed,
      ),
    );
  }

  // A státusz menü ikon méretének csökkentése is, hogy illeszkedjen a kisebb ikonmérethez.
  // ignore: unused_element
  Widget _buildStatusMenu(
      BuildContext context, String noteId, String currentStatus) {
    const statuses = ['Published', 'Draft', 'Archived'];
    final effectiveStatus =
        currentStatus == 'Public' ? 'Published' : currentStatus;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.primaryColor, size: 18),
      tooltip: 'Státusz módosítása',
      onSelected: (String newStatus) {
        _updateNoteStatus(context, noteId, newStatus);
      },
      itemBuilder: (BuildContext context) {
        return statuses.map((String status) {
          return PopupMenuItem<String>(
            value: status,
            child: Text(status,
                style: TextStyle(
                  color: status == effectiveStatus ? Colors.blue : null,
                  fontWeight: status == effectiveStatus
                      ? FontWeight.bold
                      : FontWeight.normal,
                )),
          );
        }).toList();
      },
      // A menügomb minimális mérete
      constraints: const BoxConstraints(minWidth: 24),
    );
  }

  Future<void> _updateNoteStatus(
      BuildContext context, String noteId, String newStatus) async {
    try {
      await FirebaseConfig.firestore.collection('notes').doc(noteId).update({
        'status': newStatus,
        'modified': Timestamp.now(),
      });
      if (!context.mounted) return;
      _showSnackBar(context, 'Státusz sikeresen frissítve!');
    } catch (e) {
      _showSnackBar(context, 'Hiba a státusz frissítésekor: $e');
    }
  }

  // ignore: unused_element
  Future<void> _toggleFreeStatus(
      BuildContext context, String noteId, bool currentFree) async {
    try {
      await FirebaseConfig.firestore.collection('notes').doc(noteId).update({
        'isFree': !currentFree,
        'modified': Timestamp.now(),
      });
      if (!context.mounted) return;
      _showSnackBar(
          context,
          !currentFree
              ? 'A jegyzet mostantól ingyenes!'
              : 'Ingyenes státusz kikapcsolva');
    } catch (e) {
      _showSnackBar(context, 'Hiba a státusz frissítésekor: $e');
    }
  }

  // Nem használt a felhasználói buildben – megtartjuk a későbbi admin funkciókhoz.
  // ignore: unused_element
  void _showDeleteAllDialog(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Megerősítés',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
        content: const Text(
            'Biztosan törlöd ezt a jegyzetet és minden hozzá tartozó fájlt?',
            style: TextStyle(fontFamily: 'Inter')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Nem',
                style:
                    TextStyle(color: Color(0xFF6B7280), fontFamily: 'Inter')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A)),
            onPressed: () async {
              Navigator.of(context).pop();

              try {
                // Hard delete: teljes dokumentum törlése.
                await FirebaseConfig.firestore
                    .collection('notes')
                    .doc(docId)
                    .delete();

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Jegyzet véglegesen törölve')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Hiba a törlés során: $e')),
                );
              }
            },
            child: const Text('Igen, törlés',
                style: TextStyle(fontFamily: 'Inter')),
          ),
        ],
      ),
    );
  }

  void _showVideoDialog(BuildContext context, String videoUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.7,
          height: MediaQuery.of(context).size.height * 0.7,
          child: VideoPreviewPlayer(videoUrl: videoUrl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Bezárás'),
          ),
        ],
      ),
    );
  }

  void _showQuizPreviewDialog(BuildContext context, String bankId,
      {bool dualMode = false}) async {
    final bankDoc = await FirebaseConfig.firestore
        .collection('question_banks')
        .doc(bankId)
        .get();
    if (!bankDoc.exists) {
      if (context.mounted) {
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ez a kérdésbank nem tartalmaz kérdéseket.')));
      }
      return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          contentPadding: const EdgeInsets.all(8),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            child: dualMode
                ? QuizViewerDual(
                    questions: selectedQuestions,
                    onQuizComplete: (result) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Kvíz eredménye: ${result.score}/${result.totalQuestions}'),
                        ),
                      );
                    },
                  )
                : QuizViewer(
                    questions:
                        selectedQuestions.map((q) => q.toMap()).toList()),
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
