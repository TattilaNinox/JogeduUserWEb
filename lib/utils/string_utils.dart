/// Szövegek természetes (numerikus) sorrendbe rendezéséhez használható segédfüggvények.
class StringUtils {
  /// Két szöveget hasonlít össze természetes sorrendben.
  /// Példa: "2." előbb lesz, mint a "10." (szemben a lexikografikus "10.", "2." sorrenddel).
  static int naturalCompare(String a, String b) {
    final RegExp re = RegExp(r'(\d+)|(\D+)');
    final String lowerA = a.toLowerCase();
    final String lowerB = b.toLowerCase();

    final Iterable<Match> matchesA = re.allMatches(lowerA);
    final Iterable<Match> matchesB = re.allMatches(lowerB);

    final Iterator<Match> itA = matchesA.iterator;
    final Iterator<Match> itB = matchesB.iterator;

    while (itA.moveNext() && itB.moveNext()) {
      final Match mA = itA.current;
      final Match mB = itB.current;

      final String partA = mA.group(0)!;
      final String partB = mB.group(0)!;

      // Ha mindkét rész szám, akkor számként hasonlítjuk össze őket
      if (mA.group(1) != null && mB.group(1) != null) {
        final int numA = int.parse(partA);
        final int numB = int.parse(partB);
        if (numA != numB) {
          return numA.compareTo(numB);
        }
      } else if (mA.group(1) != null || mB.group(1) != null) {
        // Ha az egyik szám, a másik szöveg, a szöveg kerül előre
        return mA.group(1) != null ? 1 : -1;
      } else {
        // Egyébként szövegként
        final int result = partA.compareTo(partB);
        if (result != 0) {
          return result;
        }
      }
    }

    // Ha az egyik szöveg rövidebb, az kerül előre
    return lowerA.length.compareTo(lowerB.length);
  }
}
