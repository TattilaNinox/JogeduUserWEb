import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/languageconfig.dart'; // Correct import for Language enum
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:flutter/foundation.dart';

/// Global hyphenator instance for Hungarian.
Hyphenator? _hyphenatorHu;

/// Initializes the Hungarian hyphenator.
Future<void> initHyphenatorHu() async {
  if (_hyphenatorHu != null) return;

  try {
    // Load using the correct enum and loadAsync method
    _hyphenatorHu = await Hyphenator.loadAsync(Language.language_hu);
    debugPrint('🟢 [initHyphenatorHu] Hyphenator initialized successfully');
  } catch (e) {
    debugPrint('🔴 [initHyphenatorHu] Failed to initialize hyphenator: $e');
  }
}

/// Robust Hungarian hyphenation for HTML strings using hyphenatorx.
Future<String> hyphenateHtmlHu(String htmlString) async {
  if (htmlString.isEmpty) return htmlString;

  if (_hyphenatorHu == null) {
    await initHyphenatorHu();
  }

  if (_hyphenatorHu == null) {
    debugPrint('⚠️ [hyphenateHtmlHu] Hyphenator not available');
    return htmlString;
  }

  try {
    final document = html_parser.parseFragment(htmlString);
    _processNode(_hyphenatorHu!, document);
    return document.outerHtml;
  } catch (e) {
    debugPrint('🔴 [hyphenateHtmlHu] Error: $e');
    return htmlString;
  }
}

void _processNode(Hyphenator hyphenator, dom.Node node) {
  if (node is dom.Element) {
    final tag = node.localName?.toLowerCase();
    if (tag == 'code' || tag == 'pre' || tag == 'script' || tag == 'style') {
      return;
    }
  }

  final children = List<dom.Node>.from(node.nodes);
  for (final child in children) {
    if (child.nodeType == dom.Node.TEXT_NODE) {
      final text = child.text;
      if (text != null && text.trim().isNotEmpty) {
        try {
          // Use hyphenateText for potentially multiple words in a text node
          final hyphenatedText = hyphenator.hyphenateText(text);
          child.text = hyphenatedText;
        } catch (e) {
          debugPrint('⚠️ [hyphenateHtmlHu] Hyphenation failed for segment');
        }
      }
    } else {
      _processNode(hyphenator, child);
    }
  }
}
