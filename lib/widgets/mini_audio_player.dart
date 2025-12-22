import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/version_check_service.dart';

/// Egy kompakt, beágyazható audiolejátszó widget.
///
/// Ez a `StatefulWidget` az `audioplayers` csomagot használja egyetlen
/// audiofájl lejátszására a megadott URL-ről. A widget saját maga kezeli
/// az összes állapotot, ami a lejátszáshoz szükséges. A projektben ez az
/// egységesített audiolejátszó csomag.
class MiniAudioPlayer extends StatefulWidget {
  /// A lejátszandó audiofájl URL-je.
  final String audioUrl;

  /// Ha igaz, a lejátszó csak interakcióra inicializál (lista teljesítményhez).
  final bool deferInit;

  /// Kompakt megjelenítés: kisebb ikonok, hátralévő idő elrejtése.
  final bool compact;

  /// Nagy méretű megjelenítés: nagyobb ikonok, hangsúlyosabb vezérlők.
  final bool large;

  /// Automatikus lejátszás: ha igaz, automatikusan elindítja a lejátszást inicializálás után
  final bool autoPlay;

  /// Opcionális vezérlő a külső vezérléshez (pl. mobil web autoplay-hoz user gesture-ből).
  final MiniAudioPlayerController? controller;

  /// Ha igaz, megjelenik egy "AUTO" badge, jelezve hogy automatikus lejátszás aktív.
  final bool showAutoBadge;

  const MiniAudioPlayer(
      {super.key,
      required this.audioUrl,
      this.deferInit = true,
      this.compact = false,
      this.large = false,
      this.autoPlay = false,
      this.controller,
      this.showAutoBadge = false});

  @override
  State<MiniAudioPlayer> createState() => _MiniAudioPlayerState();
}

/// A `MiniAudioPlayer` állapotát kezelő osztály.
class _MiniAudioPlayerState extends State<MiniAudioPlayer> {
  // Az `audioplayers` csomag lejátszó példánya.
  late AudioPlayer _audioPlayer;

  // Állapotváltozók a lejátszó állapotának követésére.
  PlayerState? _playerState;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _initializing = false;
  bool _expanded = false; // Ha igaz, a teljes kezelőfelület látszik
  bool _isLooping =
      false; // Folyamatos lejátszás kapcsoló (nem mentjük tartósan)
  Timer? _activityTimer; // Timer az aktivitás szimulálásához

  bool get _isPlaying => _playerState == PlayerState.playing;

  String? _guessMimeType(String url) {
    final lower = url.toLowerCase();
    // Firebase Storage alt=media URL-eknél is általában benne van a kiterjesztés a path-ban.
    if (lower.contains('.mp3')) return 'audio/mpeg';
    if (lower.contains('.m4a') || lower.contains('.mp4')) return 'audio/mp4';
    if (lower.contains('.aac')) return 'audio/aac';
    if (lower.contains('.wav')) return 'audio/wav';
    if (lower.contains('.ogg') || lower.contains('.oga')) return 'audio/ogg';
    return null; // hagyjuk a böngészőt sniff-elni
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    widget.controller?._attach(this);
    if (!widget.deferInit) {
      _initAudioPlayer();
    }
  }

  @override
  void didUpdateWidget(covariant MiniAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }

    if (oldWidget.audioUrl != widget.audioUrl) {
      // Ha van külső controller (pl. MP autoplay user gesture-ből), akkor NEM nyúlunk
      // automatikusan a source-hoz itt, mert az a lejátszást azonnal megszakíthatja
      // egy későbbi setState miatt (start -> stop tünet).
      //
      // Controller nélküli esetben viszont frissítjük a source-ot, hogy a UI/play
      // biztosan az új URL-re álljon.
      if (widget.controller == null) {
        _setSource(widget.audioUrl);
      }
    }
  }

  /// A lejátszó inicializálását és a listenerekre való feliratkozást végző metódus.
  Future<void> _initAudioPlayer() async {
    try {
      // Beállítja a forrás URL-t. Ez a lejátszás előfeltétele.
      await _setSource(widget.audioUrl);
      // Ismétlés beállítása a kapcsoló állapotának megfelelően
      await _audioPlayer.setReleaseMode(
        _isLooping ? ReleaseMode.loop : ReleaseMode.stop,
      );

      // Feliratkozás a lejátszó eseményeire (listenerek), hogy az UI
      // valós időben frissüljön az állapotváltozásoknak megfelelően.
      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _playerState = state);
        // Timer kezelése: indítás playing állapotban, leállítás egyébként
        _manageActivityTimer(state);
      });

      _audioPlayer.onDurationChanged.listen((duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
      });

      _audioPlayer.onPositionChanged.listen((position) {
        if (!mounted) return;
        setState(() => _position = position);
      });

      _audioPlayer.onPlayerComplete.listen((event) {
        if (!mounted) return;
        setState(() {
          _playerState = PlayerState.completed;
          _position = _duration; // Vagy Duration.zero, ízlés szerint
        });
      });

      if (!mounted) return;
      setState(() => _isInitialized = true);

      // Automatikus lejátszás, ha be van kapcsolva
      // Ha külső controller vezérli (pl. MP mobil autoplay), ne próbáljunk itt automatikusan
      // elindítani, mert mobil böngészőkben user gesture kell és ez hibára futhat.
      if (widget.autoPlay && widget.controller == null) {
        await _audioPlayer.play(UrlSource(
          widget.audioUrl,
          mimeType: _guessMimeType(widget.audioUrl),
        ));
        setState(() => _expanded = true);
      }
    } catch (e) {
      debugPrint('Hiba az audio inicializálásakor (audioplayers): $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = true; // Jelezzük, hogy a hibaüzenet megjelenhessen.
        });
      }
    }
  }

  Future<void> _ensureInitAndPlay() async {
    if (_isInitialized) {
      setState(() => _expanded = true);
      await _audioPlayer.play(UrlSource(
        widget.audioUrl,
        mimeType: _guessMimeType(widget.audioUrl),
      ));
      return;
    }
    setState(() => _initializing = true);
    await _initAudioPlayer();
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _expanded = true;
    });
    await _audioPlayer.play(UrlSource(
      widget.audioUrl,
      mimeType: _guessMimeType(widget.audioUrl),
    ));
  }

  /// Timer kezelése az aktivitás szimulálásához
  void _manageActivityTimer(PlayerState state) {
    _activityTimer?.cancel();
    _activityTimer = null;

    if (state == PlayerState.playing) {
      // Timer indítása: 30 másodpercenként aktivitást rögzít
      _activityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        VersionCheckService().recordActivity();
      });
    }
  }

  Future<void> _setSource(String url) async {
    try {
      // Ha épp játszik, állítsuk le forrásváltás előtt
      if (_isPlaying) {
        await _audioPlayer.stop();
      }
      await _audioPlayer.setSource(
        UrlSource(
          url,
          mimeType: _guessMimeType(url),
        ),
      );
      if (mounted) {
        setState(() {
          _hasError = false;
          _duration = Duration.zero;
          _position = Duration.zero;
        });
      }
    } catch (e) {
      debugPrint('Hiba a forrás beállításakor: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _externalSetSourceAndPlay(String url) async {
    // iOS/WebKit: a lejátszás akkor a legstabilabb user gesture-ből, ha a
    // source+play egy lépésben történik (külön await-ek nélkül).
    //
    // Az audioplayers web implementációja a play(url) hívásnál maga kezeli a source beállítást.
    if (_hasError) return;
    if (_isPlaying) {
      await _audioPlayer.stop();
    }
    if (mounted) {
      setState(() => _expanded = true);
    }
    await _audioPlayer.play(
      UrlSource(url, mimeType: _guessMimeType(url)),
    );
  }

  Future<void> _externalSetSource(String url) async {
    if (!_isInitialized) {
      await _initAudioPlayer();
    }
    if (_hasError) return;
    await _setSource(url);
    // Maradjon nyitva a felület, ha már használjuk
    if (mounted) {
      setState(() => _expanded = true);
    }
  }

  Future<void> _externalPlay() async {
    if (_hasError) return;
    if (!_isInitialized) {
      await _initAudioPlayer();
    }
    await _ensureInitAndPlay();
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    // Timer törlése
    _activityTimer?.cancel();
    _activityTimer = null;
    // A dispose() metódus automatikusan meghívja a stop() metódust is.
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Relatív tekerés a hangfájlban.
  void _seekRelative(int seconds) {
    final newPos = _position + Duration(seconds: seconds);
    _audioPlayer.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  /// Egy `Duration` objektumot formáz "pp:mm" formátumú String-gé.
  String _formatDuration(Duration d) {
    if (d == Duration.zero) return "00:00";
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final double iconSize = widget.large ? 32 : (widget.compact ? 18 : 22);
    final BoxConstraints btnSize = BoxConstraints(
      minWidth: widget.large ? 48 : (widget.compact ? 30 : 36),
      minHeight: widget.large ? 48 : (widget.compact ? 30 : 36),
    );
    final double height = widget.large ? 56 : (widget.compact ? 28 : 36);

    if (_hasError) {
      return const Tooltip(
        message: 'A hangfájl nem tölthető be vagy hibás.',
        child: Icon(Icons.error, color: Colors.red),
      );
    }

    // Lista-optimalizált kezdeti állapot: csak egy kis Play ikon jelenik meg.
    if (widget.deferInit && !_expanded) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(
          height: height,
          child: _initializing
              ? SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Center(
                  child: widget.large
                      ? IconButton(
                          icon: const Icon(Icons.play_circle_fill,
                              size: 48, color: Color(0xFF1E3A8A)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 56,
                            minHeight: 56,
                          ),
                          tooltip: 'Dialógus betöltése',
                          onPressed: _ensureInitAndPlay,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill,
                                  size: 22, color: Color(0xFF1E3A8A)),
                              padding: EdgeInsets.zero,
                              constraints: btnSize,
                              tooltip: 'Hang lejátszása',
                              onPressed: _ensureInitAndPlay,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                _isLooping ? Icons.repeat_on : Icons.repeat,
                                size: 20,
                                color: _isLooping
                                    ? Colors.orange
                                    : const Color(0xFF1E3A8A),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: btnSize,
                              tooltip: _isLooping
                                  ? 'Ismétlés: bekapcsolva'
                                  : 'Ismétlés: kikapcsolva',
                              onPressed: () async {
                                setState(() => _isLooping = !_isLooping);
                                if (_isInitialized) {
                                  await _audioPlayer.setReleaseMode(
                                    _isLooping
                                        ? ReleaseMode.loop
                                        : ReleaseMode.stop,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                ),
        ),
      );
    }

    if (!_isInitialized) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(
          height: height,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.replay_10, size: iconSize),
                  onPressed: () => _seekRelative(-10),
                  color: Colors.green,
                  padding: EdgeInsets.zero,
                  constraints: btnSize,
                  tooltip: 'Vissza 10 mp',
                ),
                SizedBox(width: widget.large ? 8 : 0),
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow,
                      size: widget.large ? 40 : iconSize),
                  onPressed: () async {
                    if (_isPlaying) {
                      await _audioPlayer.pause();
                    } else if (_playerState == PlayerState.paused) {
                      await _audioPlayer.resume();
                    } else {
                      // If controller is present (MP station view), use the same method as autoplay
                      // to ensure iOS/WebKit compatibility (single-step source+play)
                      // Don't await to preserve user gesture context on iOS/WebKit
                      if (widget.controller != null) {
                        // ignore: discarded_futures
                        widget.controller!.setSourceAndPlay(widget.audioUrl);
                      } else {
                        // No controller (dialog files): use _ensureInitAndPlay()
                        await _ensureInitAndPlay();
                      }
                    }
                  },
                  color: Colors.green,
                  padding: EdgeInsets.zero,
                  constraints: btnSize,
                  tooltip: _isPlaying ? 'Szünet' : 'Lejátszás',
                ),
                SizedBox(width: widget.large ? 8 : 0),
                IconButton(
                  icon: Icon(Icons.forward_10, size: iconSize),
                  onPressed: () => _seekRelative(10),
                  color: Colors.green,
                  padding: EdgeInsets.zero,
                  constraints: btnSize,
                  tooltip: 'Előre 10 mp',
                ),
                SizedBox(width: widget.large ? 8 : 0),
                IconButton(
                  icon: Icon(Icons.stop, size: iconSize),
                  onPressed: () async {
                    await _audioPlayer.stop();
                    setState(() => _position = Duration.zero);
                  },
                  color: Colors.green,
                  padding: EdgeInsets.zero,
                  constraints: btnSize,
                  tooltip: 'Stop',
                ),
                SizedBox(width: widget.large ? 8 : 0),
                IconButton(
                  icon: Icon(
                    _isLooping ? Icons.repeat_on : Icons.repeat,
                    size: iconSize,
                  ),
                  onPressed: () async {
                    setState(() => _isLooping = !_isLooping);
                    await _audioPlayer.setReleaseMode(
                      _isLooping ? ReleaseMode.loop : ReleaseMode.stop,
                    );
                  },
                  color: _isLooping ? Colors.orange : Colors.green,
                  padding: EdgeInsets.zero,
                  constraints: btnSize,
                  tooltip: _isLooping
                      ? 'Ismétlés: bekapcsolva'
                      : 'Ismétlés: kikapcsolva',
                ),
                Padding(
                  padding: EdgeInsets.only(left: widget.large ? 12 : 6),
                  child: Text(
                    _formatDuration((_duration - _position).isNegative
                        ? Duration.zero
                        : _duration - _position),
                    style: TextStyle(
                      fontSize: widget.large ? 14 : (widget.compact ? 11 : 12),
                      fontWeight:
                          widget.large ? FontWeight.bold : FontWeight.normal,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}

/// Külső vezérlő a `MiniAudioPlayer`-hez (pl. mobil weben user gesture-ből indított autoplay).
class MiniAudioPlayerController {
  _MiniAudioPlayerState? _state;
  String? _pendingUrlToPlay;
  String? _pendingUrlToSet;
  bool _pendingPlay = false;

  void _attach(_MiniAudioPlayerState state) {
    _state = state;
    // Függőben lévő parancsok lejátszása attach után
    if (_pendingUrlToPlay != null) {
      final url = _pendingUrlToPlay!;
      _pendingUrlToPlay = null;
      _pendingPlay = false;
      // ignore: discarded_futures
      state._externalSetSourceAndPlay(url);
      return;
    }
    if (_pendingUrlToSet != null) {
      final url = _pendingUrlToSet!;
      _pendingUrlToSet = null;
      // ignore: discarded_futures
      state._externalSetSource(url);
      // ne return-öljünk, mert lehet még pendingPlay is
    }
    if (_pendingPlay) {
      _pendingPlay = false;
      // ignore: discarded_futures
      state._externalPlay();
    }
  }

  void _detach(_MiniAudioPlayerState state) {
    if (_state == state) {
      _state = null;
    }
  }

  Future<void> setSourceAndPlay(String url) async {
    final s = _state;
    if (s == null) {
      _pendingUrlToPlay = url;
      _pendingPlay = true;
      return;
    }
    await s._externalSetSourceAndPlay(url);
  }

  Future<void> setSource(String url) async {
    final s = _state;
    if (s == null) {
      _pendingUrlToSet = url;
      return;
    }
    await s._externalSetSource(url);
  }

  Future<void> play() async {
    final s = _state;
    if (s == null) {
      _pendingPlay = true;
      return;
    }
    await s._externalPlay();
  }
}
