/// Very lightweight Hungarian-oriented hyphenation helper for HTML strings.
///
/// Goal: Insert soft hyphens (&shy;) into long words in TEXT segments
/// (outside of tags, and skipping <code> / <pre> blocks) so that
/// mobile justified text does not create big gaps.
///
/// This is NOT a perfect linguistic hyphenator, just a pragmatic
/// fallback that avoids bad rivers. It inserts soft hyphens in words
/// longer than [minWordLength] at roughly every [chunk] characters,
/// preferring breaks after a vowel when possible.
String hyphenateHtmlHu(String html, {int minWordLength = 10, int chunk = 6}) {
  final buffer = StringBuffer();

  bool inTag = false;
  bool inCode = false;
  bool inPre = false;
  final lower = html.toLowerCase();

  // Simple scanner – we detect tag boundaries and naive <code>/<pre> blocks.
  for (int i = 0; i < html.length; i++) {
    final ch = html[i];

    if (ch == '<') {
      inTag = true;
      // Detect entering code/pre
      final rest = lower.substring(i);
      if (rest.startsWith('<code')) inCode = true;
      if (rest.startsWith('<pre')) inPre = true;
      buffer.write(ch);
      continue;
    }
    if (ch == '>') {
      inTag = false;
      final upto = lower.substring(0, i + 1);
      // Detect leaving code/pre – look back a bit
      if (upto.endsWith('</code>')) inCode = false;
      if (upto.endsWith('</pre>')) inPre = false;
      buffer.write(ch);
      continue;
    }

    if (inTag || inCode || inPre) {
      buffer.write(ch);
      continue;
    }

    // We are in text. Collect a run until next tag start or whitespace break
    if (_isLetter(ch)) {
      final start = i;
      while (i + 1 < html.length && _isLetter(html[i + 1])) {
        i++;
      }
      final word = html.substring(start, i + 1);
      buffer.write(
          _hyphenateWordHu(word, minWordLength: minWordLength, chunk: chunk));
    } else {
      buffer.write(ch);
    }
  }

  return buffer.toString();
}

bool _isLetter(String ch) {
  // Basic Latin + Hungarian accented letters
  final code = ch.codeUnitAt(0);
  final isLatin = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  const accents = 'áéíóöőúüűÁÉÍÓÖŐÚÜŰ';
  return isLatin || accents.contains(ch);
}

String _hyphenateWordHu(String word,
    {required int minWordLength, required int chunk}) {
  if (word.length < minWordLength) return word;

  const soft = '&shy;';
  const vowels = 'aáeéiíoóöőuúüűAÁEÉIÍOÓÖŐUÚÜŰ';

  // Try to place breaks at approx every [chunk] chars, but if the next
  // character after the break is a consonant followed by a vowel, move break
  // to the vowel boundary – very rough Hungarian-friendly heuristic.
  final breaks = <int>[];
  int pos = chunk;
  while (pos < word.length - 3) {
    int best = pos;
    // Look ahead up to 2 chars to find a vowel boundary (CV pattern)
    for (int shift = 0; shift <= 2 && pos + shift + 1 < word.length; shift++) {
      final c1 = word[pos + shift];
      final c2 = word[pos + shift + 1];
      if (!vowels.contains(c1) && vowels.contains(c2)) {
        best = pos + shift + 1; // break before vowel
        break;
      }
    }
    breaks.add(best);
    pos = best + chunk;
  }

  if (breaks.isEmpty) return word;

  final sb = StringBuffer();
  int last = 0;
  for (final b in breaks) {
    sb
      ..write(word.substring(last, b))
      ..write(soft);
    last = b;
  }
  sb.write(word.substring(last));
  return sb.toString();
}
