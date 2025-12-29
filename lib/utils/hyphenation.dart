import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/languageconfig.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:flutter/foundation.dart';

/// Global hyphenator instance for Hungarian (Main Isolate).
Hyphenator? _hyphenatorHu;

/// Initializes the Hungarian hyphenator.
Future<void> initHyphenatorHu() async {
  if (_hyphenatorHu != null) return;
  try {
    _hyphenatorHu = await Hyphenator.loadAsync(Language.language_hu);
    if (kDebugMode) {
      debugPrint('🟢 [initHyphenatorHu] Hyphenator initialized successfully');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('🔴 [initHyphenatorHu] Failed to initialize hyphenator: $e');
    }
  }
}

/// Helper class for background processing
class HyphenationJob {
  final String html;
  final Language language;

  HyphenationJob(this.html, this.language);
}

/// Statics for the worker isolate (separate memory space)
Hyphenator? _workerHyphenator;

/// Worker function that runs in a separate isolate (compute).
/// It must be a top-level function or a static method.
Future<String> _hyphenationWorker(HyphenationJob job) async {
  try {
    // Cache the hyphenator within the isolate to avoid repeated JSON loading
    _workerHyphenator ??= await Hyphenator.loadAsync(job.language);

    final document = html_parser.parseFragment(job.html);
    _processNodeRecursive(_workerHyphenator!, document);
    return document.outerHtml;
  } catch (e) {
    return job.html;
  }
}

/// Robust Hungarian hyphenation for HTML strings.
/// Moves work to background isolate for long strings to keep UI responsive.
Future<String> hyphenateHtmlHu(String htmlString) async {
  if (htmlString.isEmpty) return htmlString;

  // RAPID EXIT: If the content is already hyphenated (contains soft hyphens), skip processing.
  // 0xAD is the soft hyphen character. &shy; is the HTML entity.
  if (htmlString.contains('\u00AD') || htmlString.contains('&shy;')) {
    // Already hyphenated, return as is.
    return htmlString;
  }

  if (_hyphenatorHu == null) {
    // Ensure initialization is started
    initHyphenatorHu();
  }

  // Optimization: For very short strings, don't context switch to isolate
  if (htmlString.length < 500) {
    if (_hyphenatorHu != null) {
      final document = html_parser.parseFragment(htmlString);
      _processNodeRecursive(_hyphenatorHu!, document);
      return document.outerHtml;
    }
    return htmlString;
  }

  // Heavy lifting in background
  try {
    return await compute(
        _hyphenationWorker, HyphenationJob(htmlString, Language.language_hu));
  } catch (e) {
    if (kDebugMode) {
      debugPrint('🔴 [hyphenateHtmlHu] Background hyphenation failed: $e');
    }
    return htmlString;
  }
}

void _processNodeRecursive(Hyphenator hyphenator, dom.Node node) {
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
          final hyphenatedText = hyphenator.hyphenateText(text);
          child.text = hyphenatedText;
        } catch (e) {
          // Silent fail for specific segments
        }
      }
    } else {
      _processNodeRecursive(hyphenator, child);
    }
  }
}
