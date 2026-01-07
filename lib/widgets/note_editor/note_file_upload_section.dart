import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';

/// Fájl feltöltési szekció a jegyzet szerkesztő képernyőhöz
///
/// Kezeli:
/// - MP3 hangfájl feltöltést és törlést
/// - PDF dokumentum feltöltést és törlést
/// - Videó fájl megjelenítést
class NoteFileUploadSection extends StatelessWidget {
  /// Kiválasztott MP3 fájl adatai
  final Map<String, dynamic>? selectedMp3File;

  /// Létező audio URL (korábban feltöltött)
  final String? existingAudioUrl;

  /// MP3 törlésre van jelölve
  final bool deleteAudio;

  /// Kiválasztott PDF fájl adatai
  final Map<String, dynamic>? selectedPdfFile;

  /// Létező PDF URL
  final String? existingPdfUrl;

  /// PDF törlésre van jelölve
  final bool deletePdf;

  /// Kiválasztott videó fájl
  final Map<String, dynamic>? selectedVideoFile;

  /// Videó kontroller
  final VideoPlayerController? videoController;

  /// MP3 kiválasztás callback
  final VoidCallback onPickMp3;

  /// PDF kiválasztás callback
  final VoidCallback onPickPdf;

  /// MP3 törlés callback
  final VoidCallback onDeleteMp3;

  /// PDF törlés callback
  final VoidCallback onDeletePdf;

  /// URL megnyitás callback
  final void Function(String url) onOpenUrl;

  const NoteFileUploadSection({
    super.key,
    this.selectedMp3File,
    this.existingAudioUrl,
    required this.deleteAudio,
    this.selectedPdfFile,
    this.existingPdfUrl,
    required this.deletePdf,
    this.selectedVideoFile,
    this.videoController,
    required this.onPickMp3,
    required this.onPickPdf,
    required this.onDeleteMp3,
    required this.onDeletePdf,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Fájlok',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildMp3Section(context),
        const SizedBox(height: 24),
        _buildPdfSection(context),
        if (_shouldShowVideoPreview()) _buildVideoPreview(),
      ],
    );
  }

  Widget _buildMp3Section(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onPickMp3,
                icon: const Icon(Icons.audiotrack),
                label: const Text('MP3 Csere'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 8),
            if (existingAudioUrl != null || selectedMp3File != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDeleteMp3,
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text('MP3 Törlés',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
          ],
        ),
        if (selectedMp3File != null || existingAudioUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              deleteAudio
                  ? 'Hangfájl törlésre megjelölve'
                  : 'Kiválasztva: ${selectedMp3File != null ? selectedMp3File!['name'] : 'Meglévő hangfájl'}',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: deleteAudio ? Colors.red : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildPdfSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onPickPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF Csere'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            if ((existingPdfUrl != null && !deletePdf) ||
                selectedPdfFile != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDeletePdf,
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                tooltip: 'PDF törlése',
              ),
            ],
          ],
        ),
        if (existingPdfUrl != null && !deletePdf) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => onOpenUrl(existingPdfUrl!),
                icon: const Icon(Icons.open_in_new),
                label: const Text('PDF Megnyitása'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'URL másolása',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: existingPdfUrl!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('PDF URL vágólapra másolva')));
                  }
                },
                icon: const Icon(Icons.link),
              ),
            ],
          ),
        ],
      ],
    );
  }

  bool _shouldShowVideoPreview() {
    return selectedVideoFile != null &&
        selectedVideoFile!['path'] != null &&
        !kIsWeb &&
        videoController != null;
  }

  Widget _buildVideoPreview() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: AspectRatio(
        aspectRatio: videoController!.value.aspectRatio,
        child: VideoPlayer(videoController!),
      ),
    );
  }
}

/// Címke szekció widget
class NoteTagsSection extends StatelessWidget {
  final List<String> tags;
  final TextEditingController tagController;
  final void Function(String tag) onAddTag;
  final void Function(String tag) onRemoveTag;

  const NoteTagsSection({
    super.key,
    required this.tags,
    required this.tagController,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Címkék',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: tags
              .map((tag) => Chip(
                    label: Text(tag),
                    onDeleted: () => onRemoveTag(tag),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: tagController,
          decoration: InputDecoration(
            labelText: 'Új címke',
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                if (tagController.text.isNotEmpty &&
                    !tags.contains(tagController.text)) {
                  onAddTag(tagController.text);
                }
              },
            ),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty && !tags.contains(value)) {
              onAddTag(value);
            }
          },
        ),
      ],
    );
  }
}
