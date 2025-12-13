/// Egyszerű state management a kategória kibontási állapot kezelésére.
///
/// Ez az osztály lehetővé teszi a kategóriák állapotának megtartását,
/// amikor a felhasználó elnavigál a jegyzetlistáról, majd visszatér.
class CategoryState {
  // Statikus változók a kategória állapot tárolására
  static String? _selectedCategory;
  static String? _selectedScience;
  static String? _selectedTag;
  static String? _selectedType;
  static String? _searchText;

  /// Visszaadja a kiválasztott kategóriát
  static String? get selectedCategory => _selectedCategory;

  /// Visszaadja a kiválasztott tudományt
  static String? get selectedScience => _selectedScience;

  /// Visszaadja a kiválasztott címkét
  static String? get selectedTag => _selectedTag;

  /// Visszaadja a kiválasztott típust
  static String? get selectedType => _selectedType;

  /// Visszaadja a keresési szöveget
  static String? get searchText => _searchText;

  /// Beállítja a kategória állapotot
  static void setCategoryState({
    String? category,
    String? science,
    String? tag,
    String? type,
    String? searchText,
  }) {
    _selectedCategory = category;
    _selectedScience = science;
    _selectedTag = tag;
    _selectedType = type;
    _searchText = searchText;
  }

  /// Törli az összes kategória állapotot
  static void clearState() {
    _selectedCategory = null;
    _selectedScience = null;
    _selectedTag = null;
    _selectedType = null;
    _searchText = null;
  }

  /// Ellenőrzi, hogy vannak-e mentett állapotok
  static bool get hasState =>
      _selectedCategory != null ||
      _selectedScience != null ||
      _selectedTag != null ||
      _selectedType != null ||
      (_searchText != null && _searchText!.isNotEmpty);
}
