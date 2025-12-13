/// Egy egyszerű statikus osztály a szűrő beállítások tárolására a memóriában.
///
/// Ez az osztály lehetővé teszi a szűrők állapotának megtartását,
/// amikor a felhasználó elnavigál a jegyzetlistáról, majd visszatér.
class FilterStorage {
  // Szűrési feltételek
  static String? searchText;
  static String? status;
  static String? category;
  static String? science;
  static String? tag;
  static String? type;

  /// Törli az összes szűrési feltételt.
  static void clearFilters() {
    searchText = null;
    status = null;
    category = null;
    science = null;
    tag = null;
    type = null;
  }

  /// Menteni a szűrők állapotát navigáció előtt
  static void saveFilters({
    required String searchText,
    required String? status,
    required String? category,
    required String? science,
    required String? tag,
    required String? type,
  }) {
    FilterStorage.searchText = searchText;
    FilterStorage.status = status;
    FilterStorage.category = category;
    FilterStorage.science = science;
    FilterStorage.tag = tag;
    FilterStorage.type = type;
  }
}
