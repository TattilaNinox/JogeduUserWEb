import 'package:flutter/material.dart';
import '../mini_audio_player.dart';

/// Mobilnézet alsó sáv: audio player vagy "Nincs hanganyag" üzenet
class MemoriapalotaMobileBottomBar extends StatelessWidget {
  final String? audioUrl;

  const MemoriapalotaMobileBottomBar({
    super.key,
    required this.audioUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasAudio = audioUrl != null && audioUrl!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasAudio) ...[
          MiniAudioPlayer(
            key: ValueKey(audioUrl),
            audioUrl: audioUrl!,
            compact: false,
            large: true,
          ),
        ] else ...[
          const Text(
            'Nincs hanganyag',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

/// Mobilnézet felső navigációs sáv: előző/következő gombok és állomás számláló
class MemoriapalotaMobilePagerTopBar extends StatelessWidget {
  final int currentIndex;
  final int totalCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const MemoriapalotaMobilePagerTopBar({
    super.key,
    required this.currentIndex,
    required this.totalCount,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: currentIndex > 0 ? onPrevious : null,
            icon: const Icon(Icons.chevron_left),
            iconSize: 30,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            tooltip: 'Előző állomás',
          ),
          Text(
            '${currentIndex + 1} / $totalCount',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            onPressed: currentIndex < totalCount - 1 ? onNext : null,
            icon: const Icon(Icons.chevron_right),
            iconSize: 30,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            tooltip: 'Következő állomás',
          ),
        ],
      ),
    );
  }
}

/// Desktopnézet alsó sáv: előző-következő gombok
class MemoriapalotaDesktopBottomBar extends StatelessWidget {
  final int currentIndex;
  final int totalCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const MemoriapalotaDesktopBottomBar({
    super.key,
    required this.currentIndex,
    required this.totalCount,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ElevatedButton.icon(
          onPressed: currentIndex > 0 ? onPrevious : null,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Előző'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
          ),
        ),
        Text(
          '${currentIndex + 1} / $totalCount',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ElevatedButton.icon(
          onPressed: currentIndex < totalCount - 1 ? onNext : null,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Következő'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}
