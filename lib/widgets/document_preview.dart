import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
// Felesleges importok eltávolítva:
// import 'package:just_audio/just_audio.dart';
// import 'package:video_player/video_player.dart';

// A központi lejátszó widgetek importálása:
import 'audio_preview_player.dart';
import 'video_preview_player.dart';

/// Egy multifunkciós előnézeti widget, amely egy DOCX dokumentumhoz
/// kapcsolódó gombokat, valamint egy beágyazott audio- és videólejátszót jelenít meg.
///
/// Ez a `StatelessWidget` egy központi helyen gyűjti össze a különböző
/// fájltípusokhoz (dokumentum, hang, videó) tartozó műveleteket.
/// A DOCX fájlokat a Google Docs Viewer segítségével nyitja meg, vagy letöltési
/// lehetőséget biztosít. A médiafájlok előnézetét a projekt központi,
/// újrafelhasználható `AudioPreviewPlayer` és `VideoPreviewPlayer` widgetjei biztosítják.
class DocumentPreview extends StatelessWidget {
  /// A kötelező DOCX fájl URL-je.
  final String docxUrl;

  /// Az opcionális hangfájl URL-je.
  final String? audioUrl;

  /// Az opcionális videófájl URL-je.
  final String? videoUrl;

  const DocumentPreview(
      {super.key, required this.docxUrl, this.audioUrl, this.videoUrl});

  @override
  Widget build(BuildContext context) {
    // A Google Docs Viewer URL-jének összeállítása a DOCX fájlhoz.
    // Az `embedded=true` paraméter biztosítja, hogy a nézegető beágyazott
    // módban, felesleges UI elemek nélkül jelenjen meg.
    final googleDocsUrl =
        'https://docs.google.com/viewer?url=${Uri.encodeComponent(docxUrl)}&embedded=true';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.description, size: 48, color: Colors.grey),
        const SizedBox(height: 16),
        // Gomb a dokumentum megnyitásához a Google Docs Viewerben.
        ElevatedButton.icon(
          onPressed: () => launchUrl(Uri.parse(googleDocsUrl)),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Előnézet megnyitása'),
        ),
        const SizedBox(height: 8),
        // Gomb a dokumentum közvetlen letöltéséhez.
        ElevatedButton.icon(
          onPressed: () => launchUrl(Uri.parse(docxUrl)),
          icon: const Icon(Icons.download),
          label: const Text('Letöltés'),
        ),
        // Ha van audio URL, megjeleníti a központi audiolejátszót.
        if (audioUrl != null && audioUrl!.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Hangfájl előnézet:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // A központi `AudioPreviewPlayer` widget használata.
          AudioPreviewPlayer(audioUrl: audioUrl!),
        ],
        // Ha van videó URL, megjelenít egy gombot, ami egy dialógusablakban
        // nyitja meg a központi videólejátszót.
        if (videoUrl != null && videoUrl!.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Videó előnézet:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _showVideoDialog(context, videoUrl!),
            icon: const Icon(Icons.play_circle_fill),
            label: const Text('Videó megnyitása'),
          ),
        ],
      ],
    );
  }

  /// Megjelenít egy egyedi, `showGeneralDialog`-gal készített párbeszédablakot
  /// a videó lejátszásához, a központi `VideoPreviewPlayer` widgetet használva.
  void _showVideoDialog(BuildContext context, String videoUrl) {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width * 0.8;
    final height = mediaQuery.size.height * 0.6;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Videó előnézet',
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: Colors.black, // A videólejátszóhoz jobban illő háttér
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  // A központi `VideoPreviewPlayer` widget beágyazása.
                  Center(
                    child: VideoPreviewPlayer(videoUrl: videoUrl),
                  ),
                  // Bezárás gomb a jobb felső sarokban.
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- Eltávolított beágyazott widgetek ---
// A `AudioPreviewPlayer` és `VideoDialogContent` osztályok törölve lettek
// a kódduplikáció és az inkonzisztenciák megszüntetése érdekében.
