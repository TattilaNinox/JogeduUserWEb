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
  final String? customFromUrl; // Egyedi from URL (pl. TagDrillDownScreen-hez)

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
    this.customFromUrl, // Opcionális egyedi from URL
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
      case 'jogeset':
        return Icons.gavel; // Kalapács ikon jogesetekhez
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

    // Az aktuális URL-t query paraméterként adjuk át (visszalépéshez)
    // FONTOS: GoRouterState.of(context) csak akkor érhető el, ha GoRouter kontextusban vagyunk
    // Ha Navigator.push()-sal navigáltunk (pl. TagDrillDownScreen), akkor nincs GoRouterState
    String fromParam = '';

    // Ha van customFromUrl, azt használjuk
    if (customFromUrl != null && customFromUrl!.isNotEmpty) {
      fromParam = Uri.encodeComponent(customFromUrl!);
    } else {
      // Különben próbáljuk meg a GoRouterState-ből kiolvasni
      try {
        final currentUri = GoRouterState.of(context).uri;
        fromParam = Uri.encodeComponent(currentUri.toString());
      } catch (e) {
        // Ha nincs GoRouterState, akkor üres marad a fromParam
        debugPrint('GoRouterState not available, skipping from parameter');
      }
    }

    final fromQuery = fromParam.isNotEmpty ? '?from=$fromParam' : '';

    // Navigációs metódus kiválasztása
    // Ha van customFromUrl (pl. TagDrillDownScreen), akkor push-t használunk, hogy megőrizzük a history-t
    // Különben go-t használunk, ami a standard működés
    final usePush = customFromUrl != null && customFromUrl!.isNotEmpty;

    if (type == 'interactive') {
      if (usePush) {
        context.push('/interactive-note/$id$fromQuery');
      } else {
        context.go('/interactive-note/$id$fromQuery');
      }
    } else if (type == 'dynamic_quiz' || type == 'dynamic_quiz_dual') {
      if (isMobile) {
        if (usePush) {
          context.push('/quiz/$id$fromQuery');
        } else {
          context.go('/quiz/$id$fromQuery');
        }
      } else {
        _openQuiz(context, dualMode: type == 'dynamic_quiz_dual');
      }
    } else if (type == 'deck') {
      if (usePush) {
        context.push('/deck/$id/view$fromQuery');
      } else {
        context.go('/deck/$id/view$fromQuery');
      }
    } else if (type == 'memoriapalota_allomasok') {
      if (usePush) {
        context.push('/memoriapalota-allomas/$id$fromQuery');
      } else {
        context.go('/memoriapalota-allomas/$id$fromQuery');
      }
    } else if (type == 'memoriapalota_fajlok') {
      if (usePush) {
        context.push('/memoriapalota-fajl/$id$fromQuery');
      } else {
        context.go('/memoriapalota-fajl/$id$fromQuery');
      }
    } else if (type == 'jogeset') {
      if (usePush) {
        context.push('/jogeset/$id$fromQuery');
      } else {
        context.go('/jogeset/$id$fromQuery');
      }
    } else {
      if (usePush) {
        context.push('/note/$id$fromQuery');
      } else {
        context.go('/note/$id$fromQuery');
      }
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
    return Opacity(
      opacity: isLocked ? 0.6 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isLocked ? Colors.grey.shade300 : Colors.grey.shade200,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                              fontSize: 15,
                              color: Color(0xFF202122),
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
                            color: const Color(0xFF1976D2),
                            size: 24,
                          ),
                          const SizedBox(width: 16),
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
                      color: const Color(0xFF1976D2),
                      size: 24,
                    ),
                    const SizedBox(width: 16),
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
    );
  }
}
