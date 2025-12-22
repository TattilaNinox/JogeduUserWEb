import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Egy teljes értékű, vezérlőkkel ellátott videólejátszó widget.
///
/// Ez a `StatefulWidget` a `video_player` csomagot használja egy videó
/// lejátszására a megadott URL-ről. A widget egy komplett felhasználói felületet
/// biztosít a videó vezérléséhez, beleértve a lejátszás/szünet gombot,
/// egy interaktív csúszkát a tekeréshez, és egy időkijelzőt.
/// Úgy van kialakítva, hogy egy `Stack`-en belül a vezérlők a videó felett
/// jelenjenek meg.
class VideoPreviewPlayer extends StatefulWidget {
  /// A lejátszandó videófájl URL-je.
  final String videoUrl;

  const VideoPreviewPlayer({super.key, required this.videoUrl});

  @override
  State<VideoPreviewPlayer> createState() => _VideoPreviewPlayerState();
}

class _VideoPreviewPlayerState extends State<VideoPreviewPlayer> {
  // A `video_player` csomag központi vezérlője.
  late VideoPlayerController _controller;
  // Állapotváltozó, ami jelzi, hogy a videó inicializálása befejeződött-e.
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // A `VideoPlayerController` inicializálása a hálózati URL-ről.
    // A láncolt `..` (cascade) operátorral az inicializálás után azonnal
    // elindítjuk a folyamatokat.
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        // Az inicializálás befejeződése után...
        if (!mounted) return;
        setState(
            () => _isInitialized = true); // ...jelezzük, hogy a UI felépülhet.
        _controller.play(); // ...automatikusan elindítjuk a lejátszást.
        _controller
            .addListener(_videoListener); // ...és hozzáadunk egy listenert.
      });
  }

  /// Egy listener, ami a videó állapotának minden változásakor lefut.
  /// A célja, hogy a `setState`-hívással frissítse a UI-t (pl. a csúszka
  /// pozícióját vagy a lejátszás/szünet gomb állapotát).
  void _videoListener() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // A widget eltávolításakor fontos eltávolítani a listenert,
    // majd felszabadítani a kontroller erőforrásait a memóriaszivárgás elkerülése végett.
    _controller.removeListener(_videoListener);
    _controller.dispose();
    super.dispose();
  }

  /// Egy `Duration` objektumot formáz olvasható időkijelzésre ("óó:pp:mm" vagy "pp:mm").
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    // Amíg a videó nem inicializált, egy töltésjelzőt mutatunk.
    return _isInitialized
        ? Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // A `VideoPlayer` widget, ami megjeleníti a videó képkockáit.
              VideoPlayer(_controller),
              // Egy áttetsző réteg a vezérlők alatt, hogy jobban olvashatóak legyenek.
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(128),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(8.0),
                // A vezérlőelemeket tartalmazó rész.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Lejátszás/szünet gomb.
                        IconButton(
                          icon: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white.withAlpha(200),
                            size: 64,
                          ),
                          onPressed: () {
                            setState(() {
                              _controller.value.isPlaying
                                  ? _controller.pause()
                                  : _controller.play();
                            });
                          },
                        ),
                        // Interaktív csúszka.
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.0,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6.0),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12.0),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white.withAlpha(77),
                              thumbColor: Colors.white,
                              overlayColor: Colors.white.withAlpha(51),
                            ),
                            child: Slider(
                              value: _controller.value.position.inSeconds
                                  .toDouble(),
                              max: _controller.value.duration.inSeconds
                                  .toDouble(),
                              onChanged: (value) {
                                _controller
                                    .seekTo(Duration(seconds: value.toInt()));
                              },
                            ),
                          ),
                        ),
                        // Időkijelző (aktuális pozíció / teljes hossz).
                        Text(
                          '${_formatDuration(_controller.value.position)} / ${_formatDuration(_controller.value.duration)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          )
        : const Center(child: CircularProgressIndicator());
  }
}
