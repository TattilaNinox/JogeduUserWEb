import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class NoteContentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get note content preview for a given noteId
  static Future<String?> getNoteContentPreview(String noteId) async {
    try {
      final doc = await _firestore.collection('notes').doc(noteId).get();

      if (!doc.exists) {
        debugPrint('NoteContentService: Note not found: $noteId');
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;

      // Try to get content from 'content' field first
      final content = data['content'] as String?;
      if (content != null && content.isNotEmpty) {
        return _extractPreview(content);
      }

      // Fallback to 'pages' field
      final pages = data['pages'] as List<dynamic>?;
      if (pages != null && pages.isNotEmpty) {
        final firstPage = pages.first as String?;
        if (firstPage != null && firstPage.isNotEmpty) {
          return _extractPreview(firstPage);
        }
      }

      debugPrint('NoteContentService: No content found for note: $noteId');
      return null;
    } catch (e) {
      debugPrint('NoteContentService: Error getting note content: $e');
      return null;
    }
  }

  /// Extract a preview from HTML content
  static String _extractPreview(String content) {
    // Remove HTML tags and get plain text
    String plainText = content
        .replaceAll(RegExp(r'<[^>]*>'), ' ') // Remove HTML tags
        .replaceAll(
            RegExp(r'\s+'), ' ') // Replace multiple spaces with single space
        .trim();

    // Limit to 200 characters
    if (plainText.length > 200) {
      plainText = '${plainText.substring(0, 200)}...';
    }

    return plainText;
  }

  /// Check if content is encrypted (has iv:payload format)
  static bool isEncrypted(String content) {
    return content.contains('iv:') && content.contains('payload:');
  }

  /// Decrypt content if needed (placeholder - would need actual encryption service)
  static String decryptContent(String encryptedContent) {
    // This is a placeholder - in a real implementation, you would use
    // the actual encryption service to decrypt the content
    debugPrint(
        'NoteContentService: Content appears to be encrypted, decryption not implemented');
    return 'Titkosított tartalom - dekódolás szükséges';
  }
}
