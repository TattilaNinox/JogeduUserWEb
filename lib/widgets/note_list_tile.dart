import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/firebase_config.dart';
import '../utils/filter_storage.dart';
import 'quiz_viewer.dart';
import 'quiz_viewer_dual.dart';
import '../models/quiz_models.dart';
import 'mini_audio_player.dart';

class NoteListTile extends StatelessWidget {
  final String id;
  final String title;
  final String type; // standard, interactive, deck, dynamic_quiz...
  final bool hasDoc;
  final bool hasAudio;
  final bool hasVideo;
  final int? deckCount;
  final String? questionBankId;
  final String? audioUrl;
  final bool isLocked; // Új paraméter a zárt állapot jelzésére
  final bool isLast; // Jelzi, hogy ez az utolsó elem a listában

  const NoteListTile({
    super.key,
    required this.id,
    required this.title,
    required this.type,
    required this.hasDoc,
    required this.hasAudio,
    required this.hasVideo,
    this.deckCount,
    this.questionBankId,
    this.audioUrl,
    this.isLocked = false, // Alapértelmezetten nem zárt
    this.isLast = false, // Alapértelmezetten nem utolsó
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
      case 'source':
        return Icons.source;
      case 'memoriapalota_allomasok':
        return Icons.train;
      case 'memoriapalota_fajlok':
        return Icons.audiotrack;
      default:
        return Icons.menu_book;
    }
  }

  void _open(BuildContext context) {
    // Ha a jegyzet zárt, nem nyitjuk meg, hanem üzenetet jelenítünk meg
    if (isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Ez a tartalom csak előfizetőknek érhető el. Vásárolj előfizetést a teljes hozzáféréshez!'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Előfizetés',
            onPressed: () {
              context.go('/account');
            },
          ),
        ),
      );
      return;
    }

    // Menteni a szűrők állapotát navigáció előtt
    FilterStorage.saveFilters(
      searchText: FilterStorage.searchText ?? '',
      status: FilterStorage.status,
      category: FilterStorage.category,
      science: FilterStorage.science,
      tag: FilterStorage.tag,
      type: FilterStorage.type,
    );

    final isMobile = MediaQuery.of(context).size.width < 600;

    if (type == 'interactive') {
      context.go('/interactive-note/$id');
    } else if (type == 'dynamic_quiz' || type == 'dynamic_quiz_dual') {
      if (isMobile) {
        context.go('/quiz/$id');
      } else {
        _openQuiz(context, dualMode: type == 'dynamic_quiz_dual');
      }
    } else if (type == 'deck') {
      context.go('/deck/$id/view');
    } else if (type == 'memoriapalota_allomasok') {
      context.go('/memoriapalota-allomas/$id');
    } else if (type == 'memoriapalota_fajlok') {
      context.go('/memoriapalota-fajl/$id');
    } else {
      context.go('/note/$id');
    }
  }

  Future<void> _openQuiz(BuildContext context, {required bool dualMode}) async {
    try {
      String? bankId = questionBankId;
      if (bankId == null || bankId.isEmpty) {
        final noteDoc =
            await FirebaseConfig.firestore.collection('notes').doc(id).get();
        bankId = (noteDoc.data() ?? const {})['questionBankId'] as String?;
      }
      if (bankId == null || bankId.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Hiba: a kvízhez nincs kérdésbank társítva.')),
          );
        }
        return;
      }

      final bankDoc = await FirebaseConfig.firestore
          .collection('question_banks')
          .doc(bankId)
          .get();
      if (!bankDoc.exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hiba: a kérdésbank nem található.')),
          );
        }
        return;
      }
      final bank = bankDoc.data()!;
      final questions =
          List<Map<String, dynamic>>.from(bank['questions'] ?? []);
      if (questions.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Ez a kérdésbank nem tartalmaz kérdéseket.')),
          );
        }
        return;
      }

      questions.shuffle();
      final selected =
          questions.take(10).map((q) => Question.fromMap(q)).toList();

      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          contentPadding: const EdgeInsets.all(8),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            child: dualMode
                ? QuizViewerDual(
                    questions: selected,
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
                    questions: selected.map((q) => q.toMap()).toList()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Bezárás'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Firestore permission denied vagy egyéb hiba
      if (context.mounted) {
        final isPermissionError = e.toString().contains('permission-denied') ||
            e.toString().contains('PERMISSION_DENIED');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPermissionError
                ? 'Ez a tartalom csak előfizetőknek érhető el. Vásárolj előfizetést a teljes hozzáféréshez!'
                : 'Kvíz megnyitási hiba: $e'),
            duration: Duration(seconds: isPermissionError ? 4 : 3),
            action: isPermissionError
                ? SnackBarAction(
                    label: 'Előfizetés',
                    onPressed: () => context.go('/account'),
                  )
                : null,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wikipedia-stílusú színvilág
    const Color cardColor = Colors.white;
    const Color borderColor = Color(0xFFB0D4F1); // Halvány édenkék

    // Ha a jegyzet zárt, halványabb színeket használunk
    final effectiveCardColor =
        isLocked ? cardColor.withValues(alpha: 0.7) : cardColor;
    final effectiveBorderColor =
        isLocked ? borderColor.withValues(alpha: 0.5) : borderColor;

    return Opacity(
      opacity: isLocked ? 0.6 : 1.0, // Elhalványítás zárt jegyzetek esetén
      child: Container(
        decoration: BoxDecoration(
          color: effectiveCardColor,
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: effectiveBorderColor,
                    width: 1,
                  ),
                ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(context),
            hoverColor: const Color(0xFFF8F9FA),
            splashColor: const Color(0xFF3366CC).withValues(alpha: 0.1),
            highlightColor: const Color(0xFF3366CC).withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool isNarrow = constraints.maxWidth < 520;

                  Widget audioWidget = const SizedBox.shrink();
                  if (hasAudio && (audioUrl?.isNotEmpty ?? false)) {
                    audioWidget = Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: isNarrow ? double.infinity : 150,
                        child:
                            MiniAudioPlayer(audioUrl: audioUrl!, compact: true),
                      ),
                    );
                  } else if (hasAudio) {
                    audioWidget = const Tooltip(
                      message: 'Hangjegyzet elérhető',
                      child:
                          Icon(Icons.audiotrack, size: 16, color: Colors.green),
                    );
                  }

                  final Widget titleAndMeta = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title.isEmpty ? '(Cím nélkül)' : title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                                color: Color(0xFF202122),
                                height: 1.5,
                                letterSpacing: 0,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Lakatos ikon zárt jegyzetek esetén
                          if (isLocked) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: Color(0xFF54595D),
                            ),
                          ],
                        ],
                      ),
                    ],
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              _typeIcon(),
                              color: const Color(0xFF54595D),
                              size: 16,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: titleAndMeta,
                            ),
                          ],
                        ),
                        if (hasAudio) ...[
                          const SizedBox(height: 12),
                          audioWidget,
                        ],
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        _typeIcon(),
                        color: const Color(0xFF54595D),
                        size: 16,
                      ),
                      const SizedBox(width: 12),
                      // Bal oldali cím/meta - mindig látható
                      Expanded(
                        child: titleAndMeta,
                      ),
                      // Jobb oldali lejátszó - fix szélesség
                      if (hasAudio) ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 150,
                          child: MiniAudioPlayer(
                            audioUrl: audioUrl!,
                            compact: true,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
