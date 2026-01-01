import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/metadata_service.dart';

import '../utils/filter_storage.dart';
import '../utils/category_state.dart';
import '../widgets/sidebar.dart';
import '../widgets/header.dart';
import '../widgets/filters.dart';
import '../widgets/note_card_grid.dart';
import 'category_tags_screen.dart';
import 'tag_drill_down_screen.dart';
import '../core/firebase_config.dart'; // Ha a FirebaseConfig.firestore-t használjuk

/// A jegyzetek listáját megjelenítő főképernyő.
///
/// Ez egy `StatefulWidget`, mivel a felhasználó által beállított szűrési és
/// keresési feltételeket az állapotában (`State`) kell tárolnia és kezelnie.
/// A képernyő felépítése több al-widgetre van bontva a jobb átláthatóság érdekében
/// (`Sidebar`, `Header`, `Filters`, `NoteTable`).
class NoteListScreen extends StatefulWidget {
  final String? initialSearch;
  final String? initialStatus;
  final String? initialCategory;
  final String? initialScience;
  final String? initialTag;
  final String? initialType;

  const NoteListScreen({
    super.key,
    this.initialSearch,
    this.initialStatus,
    this.initialCategory,
    this.initialScience,
    this.initialTag,
    this.initialType,
  });

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

/// A `NoteListScreen` állapotát kezelő osztály.
class _NoteListScreenState extends State<NoteListScreen> {
  // Állapotváltozók a szűrési és keresési feltételek tárolására.
  String _searchText = '';
  String? _selectedStatus;
  String? _selectedCategory;
  String? _selectedScience;
  String? _selectedTag;
  String? _selectedType;

  // TextEditingController a keresőmező vezérléséhez
  final _searchController = TextEditingController();

  // Cache-elt NoteCardGrid: így a kategória/címke betöltés miatti setState nem fogja
  // újraépíteni a fő listát, csak amikor a szűrők ténylegesen változnak.
  Widget? _cachedGrid;
  String? _cachedGridKey;

  // Listák a Firestore-ból betöltött kategóriák, tudományok és címkék tárolására.
  List<String> _categories = [];
  List<String> _sciences = [];
  List<String> _tags = [];
  Map<String, Set<String>> _catToTags = {};
  Map<String, Set<String>> _tagToCats = {};

  /// A widget életciklusának `initState` metódusa.
  ///
  /// Akkor hívódik meg, amikor a widget először bekerül a widget-fába.
  /// Itt indítjuk el a kategóriák és címkék betöltését a Firestore-ból.
  /// Betölti a mentett szűrőket vagy az URL-ből származó kezdeti szűrőket.
  @override
  void initState() {
    super.initState();
    // AZONNAL beállítjuk a fix tudományágat
    _selectedScience = 'Jogász';
    _sciences = const ['Jogász'];
    // Ezután betöltjük a felhasználó adatait és a szűrőket
    _loadSciences();
    _loadSavedFilters();
    _loadCategories();
    _loadTags();
    _loadDependencies();

    // inicializáljuk a grid-et a kezdeti szűrőkkel
    _rebuildGridIfNeeded(force: true);

    // Figyelünk a metadata frissítésére
    MetadataService.refreshNotifier.addListener(_onMetadataRefreshed);
  }

  void _onMetadataRefreshed() {
    // Újratöltjük a metaadatokat
    _loadCategories();
    _loadTags();
    _loadDependencies();
  }

  void _rebuildGridIfNeeded({bool force = false}) {
    final key =
        '$_searchText|${_selectedStatus ?? ''}|${_selectedCategory ?? ''}|${_selectedScience ?? ''}|${_selectedTag ?? ''}|${_selectedType ?? ''}';
    if (!force && key == _cachedGridKey && _cachedGrid != null) return;
    _cachedGridKey = key;
    _cachedGrid = NoteCardGrid(
      key: ValueKey('noteGrid_$key'),
      searchText: _searchText,
      selectedStatus: _selectedStatus,
      selectedCategory: _selectedCategory,
      selectedScience: _selectedScience,
      selectedTag: _selectedTag,
      selectedType: _selectedType,
    );
  }

  /// Betölti a mentett szűrőket vagy az URL paraméterekből származó kezdeti szűrőket.
  /// A tudomány szűrő NEM törlődik, mert az automatikusan a felhasználó tudományára van állítva.
  void _loadSavedFilters() {
    // Egyszerű megoldás: mindig használjuk az URL paramétereket, ha vannak
    if (widget.initialSearch != null ||
        widget.initialStatus != null ||
        widget.initialCategory != null ||
        widget.initialScience != null ||
        widget.initialTag != null ||
        widget.initialType != null) {
      // Normalizáljuk az "MP" értéket "memoriapalota_allomasok"-ra
      final normalizedType = widget.initialType == 'MP'
          ? 'memoriapalota_allomasok'
          : widget.initialType;

      // FONTOS: Ha van címke az URL-ben, de nincs a listában, hozzáadjuk!
      if (widget.initialTag != null &&
          widget.initialTag!.isNotEmpty &&
          !_tags.contains(widget.initialTag)) {
        setState(() {
          _tags = [..._tags, widget.initialTag!]..sort();
        });
        debugPrint('🔵 Címke hozzáadva a listához: ${widget.initialTag}');
      }

      setState(() {
        _searchText = widget.initialSearch ?? '';
        _searchController.text = _searchText;
        _selectedStatus = widget.initialStatus;
        _selectedCategory = widget.initialCategory;
        // _selectedScience NEM törlődik az URL-ből, mert fix a felhasználó tudományára
        // csak akkor állítjuk be, ha az URL-ben van és megegyezik a felhasználó tudományával
        if (widget.initialScience != null) {
          _selectedScience = widget.initialScience;
        }
        _selectedTag = widget.initialTag;
        _selectedType = normalizedType;
      });

      // szűrők változtak → grid újraépítése
      _rebuildGridIfNeeded(force: true);

      // FONTOS: Beállítjuk a FilterStorage értékeit is, hogy a breadcrumb és visszalépés működjön!
      FilterStorage.searchText = widget.initialSearch;
      FilterStorage.status = widget.initialStatus;
      FilterStorage.category = widget.initialCategory;
      FilterStorage.science = widget.initialScience;
      FilterStorage.tag = widget.initialTag;
      FilterStorage.type = normalizedType;
    }
  }

  @override
  void dispose() {
    MetadataService.refreshNotifier.removeListener(_onMetadataRefreshed);
    _searchController.dispose();
    super.dispose();
  }

  /// Betölti a kategóriákat a notes kollekcióból.
  /// Csak azokat a kategóriákat tölti be, amelyek science mezője megegyezik
  /// a felhasználó tudományágával és Published státuszúak (admin esetén Draft is).
  Future<void> _loadCategories() async {
    try {
      const userScience = 'Jogász';

      // Használjuk a MetadataService-t a felesleges olvasások elkerülése végett
      final metadata = await MetadataService.getMetadata(userScience);
      final categories = metadata['categories'] ?? [];

      if (mounted) {
        final List<String> finalCategories = List<String>.from(categories);
        // Biztosítjuk, hogy a virtual "Dialogus tags" kategória látható legyen
        if (!finalCategories.contains('Dialogus tags')) {
          finalCategories.add('Dialogus tags');
        }

        setState(() {
          _categories = finalCategories..sort();
        });
        debugPrint('🟢 Kategóriák betöltve: ${_categories.length} db');
      } else {
        debugPrint('🔴 Mounted check failed in _loadCategories');
      }
    } catch (e) {
      debugPrint('🔴 Hiba a kategóriák betöltésekor: $e');
      if (mounted) {
        setState(() => _categories = []);
      }
    }
  }

  /// Betölti a tudományágakat és automatikusan beállítja a felhasználó tudományágát.
  /// A rendszer jelenleg fix tudományágra van korlátozva: 'Jogász'.
  Future<void> _loadSciences() async {
    // FIX: Webalkalmazásban MINDIG csak "Jogász" tudományág
    setState(() {
      _sciences = const ['Jogász'];
      _selectedScience = 'Jogász';
    });
    // Beállítjuk a FilterStorage-ban is, hogy más képernyőkön is elérhető legyen
    FilterStorage.science = 'Jogász';
  }

  Future<void> _loadTags() async {
    try {
      const userScience = 'Jogász';

      // Használjuk a MetadataService-t a felesleges olvasások elkerülése végett
      final metadata = await MetadataService.getMetadata(userScience);
      final tags = metadata['tags'] ?? [];

      if (mounted) {
        setState(() {
          _tags = tags..sort();
        });
        debugPrint('🟢 Címkék betöltve: ${_tags.length} db');
      } else {
        debugPrint('🔴 Mounted check failed in _loadTags');
      }

      // Biztonsági háló: ha az URL/aktuális kiválasztott címke nem volt a metaadatokban, adjuk hozzá.
      final forcedTag = (_selectedTag != null && _selectedTag!.isNotEmpty)
          ? _selectedTag
          : (widget.initialTag != null && widget.initialTag!.isNotEmpty)
              ? widget.initialTag
              : null;
      if (forcedTag != null && !_tags.contains(forcedTag)) {
        setState(() {
          _tags = [..._tags, forcedTag]..sort();
        });
      }
    } catch (e) {
      debugPrint('🔴 Hiba a címkék betöltésekor: $e');
      if (mounted) {
        setState(() => _tags = []);
      }
    }
  }

  /// Segédfüggvény a függőségek betöltésére
  Future<void> _loadDependencies() async {
    const userScience = 'Jogász';
    final mapping = await MetadataService.getCategoryTagMapping(userScience);
    if (mounted) {
      setState(() {
        _catToTags = mapping['catToTags']!;
        _tagToCats = mapping['tagToCats']!;
      });
    }
  }

  // Az alábbi metódusok ún. "callback" függvények, amelyeket a gyermek
  // widget-ek (`Header`, `Filters`) hívnak meg, amikor a felhasználó
  // módosítja a keresési vagy szűrési feltételeket.

  /// Frissíti a keresőszöveget a `Header` widgetből kapott értékkel.
  void _onSearchChanged(String value) {
    setState(() {
      _searchText = value;
    });
    _rebuildGridIfNeeded();
    // Ha a controller értéke eltér, frissítjük
    if (_searchController.text != value) {
      _searchController.text = value;
    }
    // Menti a keresési feltételt a FilterStorage-ba
    FilterStorage.searchText = value.isNotEmpty ? value : null;
    // Menti a CategoryState-be is
    CategoryState.setCategoryState(
      searchText: value.isNotEmpty ? value : null,
      category: _selectedCategory,
      science: _selectedScience,
      tag: _selectedTag,
      type: _selectedType,
    );
    _pushFiltersToUrl();
  }

  /// Frissíti a kiválasztott státuszt a `Filters` widgetből.
  void _onStatusChanged(String? value) {
    setState(() {
      _selectedStatus = value;
    });
  }

  /// Frissíti a kiválasztott kategóriát a `Filters` widgetből.
  void _onCategoryChanged(String? value) {
    setState(() {
      _selectedCategory = value;
    });
  }

  /// Frissíti a kiválasztott tudományt.
  void _onScienceChanged(String? value) {
    setState(() {
      _selectedScience = value;
    });
  }

  /// Frissíti a kiválasztott címkét a `Filters` widgetből.
  void _onTagChanged(String? value) async {
    setState(() => _selectedTag = value);
  }

  /// Megkeresi, hogy az adott címke melyik kategóriához tartozik.
  /// Ha a címke több kategóriában is szerepel, vagy nem található, null-t ad vissza.
  Future<String?> _findCategoryForTag(String tagName) async {
    try {
      // 1. Lekérdezünk néhány dokumentumot, ami tartalmazza ezt a címkét
      // A 'notes' kollekció általában a legnagyobb, ott keresünk először
      final notesSnap = await FirebaseConfig.firestore
          .collection('notes')
          .where('tags', arrayContains: tagName)
          .limit(5)
          .get();

      final categories = <String>{};

      for (var doc in notesSnap.docs) {
        final cat = doc.data()['category'] as String?;
        if (cat != null) categories.add(cat);
      }

      // Ha még nincs eredmény, megnézhetjük a jogeseteket is (opcionális, de biztonságosabb)
      if (categories.isEmpty) {
        final jogesetSnap = await FirebaseConfig.firestore
            .collection('jogesetek')
            .where('tags', arrayContains: tagName)
            .limit(5)
            .get();
        for (var doc in jogesetSnap.docs) {
          final cat = doc.data()['category'] as String?;
          if (cat != null) categories.add(cat);
        }
      }

      // 2. Kiértékelés
      if (categories.length == 1) {
        // PONTOSAN EGY kategóriában szerepel -> ez a nyerő
        return categories.first;
      } else {
        // Vagy 0 (nincs ilyen címke), vagy >1 (több kategóriában is van) -> nem egyértelmű
        return null;
      }
    } catch (e) {
      debugPrint('Hiba a kategória keresésekor: $e');
      return null;
    }
  }

  /// Frissíti a kiválasztott típust.
  void _onTypeChanged(String? value) {
    // Normalizáljuk az "MP" értéket "memoriapalota_allomasok"-ra
    final normalizedValue = value == 'MP' ? 'memoriapalota_allomasok' : value;
    setState(() => _selectedType = normalizedValue);
  }

  /// Kézi keresés indítása a szűrők alapján
  void _onApplyFilters() async {
    // 1. Ha van kategória és címke is kiválasztva -> TagDrillDownScreen (konkrét címkére a kategóriában)
    if (_selectedCategory != null &&
        _selectedCategory!.isNotEmpty &&
        _selectedTag != null &&
        _selectedTag!.isNotEmpty) {
      debugPrint(
          'SmartNav: Cateogry+Tag -> TagDrillDownScreen ($_selectedCategory, $_selectedTag)');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TagDrillDownScreen(
            category: _selectedCategory!,
            tagPath: [_selectedTag!],
          ),
        ),
      );
      return;
    }

    // 2. Ha csak címke van -> Megpróbáljuk kitalálni a kategóriát
    if ((_selectedCategory == null || _selectedCategory!.isEmpty) &&
        _selectedTag != null &&
        _selectedTag!.isNotEmpty) {
      final category = await _findCategoryForTag(_selectedTag!);
      if (category != null && mounted) {
        debugPrint(
            'SmartNav: TagOnly -> Auto-detected category ($category) -> TagDrillDownScreen');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TagDrillDownScreen(
              category: category,
              tagPath: [_selectedTag!],
            ),
          ),
        );
        return;
      }
    }

    // 3. Ha csak kategória van -> CategoryTagsScreen
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      debugPrint(
          'SmartNav: CategoryOnly -> CategoryTagsScreen ($_selectedCategory)');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CategoryTagsScreen(category: _selectedCategory!),
        ),
      );
      return;
    }

    // 4. Egyéb esetekben (pl. csak típus, státusz) -> Alkalmazzuk a szűrőket helyben
    _rebuildGridIfNeeded(force: true);
    _pushFiltersToUrl();

    // Mentsük el a beállításokat a FilterStorage-ba és CategoryState-be most, hogy alkalmaztuk
    if (_selectedStatus != null) FilterStorage.status = _selectedStatus;
    if (_selectedCategory != null) FilterStorage.category = _selectedCategory;
    if (_selectedScience != null) FilterStorage.science = _selectedScience;
    if (_selectedTag != null) FilterStorage.tag = _selectedTag;
    if (_selectedType != null) FilterStorage.type = _selectedType;

    CategoryState.setCategoryState(
      searchText: _searchText.isNotEmpty ? _searchText : null,
      category: _selectedCategory,
      science: _selectedScience,
      tag: _selectedTag,
      type: _selectedType,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Szűrési feltételek alkalmazva.')),
    );
  }

  /// Törli az összes aktív szűrőt, kivéve a tudomány szűrőt.
  /// A tudomány szűrő automatikusan a felhasználó tudományágára van beállítva,
  /// és nem törölhető.
  void _onClearFilters() {
    setState(() {
      _searchText = '';
      _searchController.clear();
      _selectedStatus = null;
      _selectedCategory = null;
      // _selectedScience = null; <- NEM törlődik, fix marad a felhasználó tudományán
      _selectedTag = null;
      _selectedType = null;
    });
    _rebuildGridIfNeeded(force: true);
    // Törli a szűrőket a FilterStorage-ból is
    FilterStorage.clearFilters();
    // Törli a CategoryState-et is, de a science megmarad
    CategoryState.clearState();
    _pushFiltersToUrl();
  }

  void _pushFiltersToUrl() {
    final params = <String, String>{};
    void put(String key, String? val) {
      if (val != null && val.isNotEmpty) params[key] = val;
    }

    put('q', _searchText);
    put('status', _selectedStatus);
    put('category', _selectedCategory);
    put('science', _selectedScience);
    put('tag', _selectedTag);
    put('type', _selectedType);
    final uri =
        Uri(path: '/notes', queryParameters: params.isEmpty ? null : params);
    // go_router: go() replaces current route without adding history entry
    GoRouter.of(context).go(uri.toString());
  }

  bool get _hasActiveFilters {
    return _searchText.isNotEmpty ||
        _selectedStatus != null ||
        _selectedCategory != null ||
        _selectedTag != null ||
        _selectedType != null;
    // _selectedScience-t nem vesszük figyelembe, mert az fix
  }

  List<String> get _visibleCategories {
    if (_selectedTag != null && _tagToCats.containsKey(_selectedTag)) {
      final allowedCats = _tagToCats[_selectedTag]!;
      // Csak azokat a kategóriákat tartsuk meg, amelyek amúgy is léteznek
      // (Bár a map az létező jegyzetekből épült, de a _categories lehet, hogy szűkebb/bővebb a metadata alapján)
      return _categories.where((c) => allowedCats.contains(c)).toList();
    }
    return _categories;
  }

  List<String> get _visibleTags {
    // Ha még nem töltődött be a map, mutassunk mindent
    if (_catToTags.isEmpty) return _tags;

    if (_selectedCategory != null) {
      if (_catToTags.containsKey(_selectedCategory)) {
        final allowedTags = _catToTags[_selectedCategory]!;
        return _tags.where((t) => allowedTags.contains(t)).toList();
      } else {
        // Ha van kiválasztott kategória, de nincs hozzá címke a mapben:
        // Ez lehet hiba (nincs frissítve), vagy tényleg nincs címkéje.
        // Biztonságosabb üres listát visszaadni, mint mindent.
        return [];
      }
    }
    return _tags;
  }

  Widget buildContent({
    required bool showSideFilters,
    required bool includeHeader,
    required bool showHeaderActions,
  }) {
    return Row(
      children: [
        if (showSideFilters)
          SizedBox(
            width: 320,
            child: Card(
              margin: const EdgeInsets.fromLTRB(12, 10, 8, 12),
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Szűrők',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      Filters(
                        categories: _visibleCategories,
                        sciences: _sciences,
                        tags: _visibleTags,
                        selectedStatus: _selectedStatus,
                        selectedCategory: _selectedCategory,
                        selectedScience: _selectedScience,
                        selectedTag: _selectedTag,
                        selectedType: _selectedType,
                        onStatusChanged: _onStatusChanged,
                        onCategoryChanged: _onCategoryChanged,
                        onScienceChanged: _onScienceChanged,
                        onTagChanged: _onTagChanged,
                        onTypeChanged: _onTypeChanged,
                        onClearFilters: _onClearFilters,
                        onApplyFilters: _onApplyFilters,
                        vertical: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (includeHeader)
                Header(
                  onSearchChanged: _onSearchChanged,
                  showActions: showHeaderActions,
                ),
              if (!showSideFilters && _hasActiveFilters)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _onClearFilters,
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('Szűrők törlése',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      if (_selectedStatus != null)
                        Chip(
                          label: Text('Státusz: $_selectedStatus',
                              style: const TextStyle(fontSize: 12)),
                          onDeleted: () => _onStatusChanged(null),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey.shade300),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.all(0),
                          labelPadding:
                              const EdgeInsets.only(left: 8, right: 4),
                        ),
                      if (_selectedType != null)
                        Chip(
                          label: Text(
                              'Típus: ${_selectedType == "memoriapalota_allomasok" ? "Memóriapalota" : _selectedType}',
                              style: const TextStyle(fontSize: 12)),
                          onDeleted: () => _onTypeChanged(null),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey.shade300),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.all(0),
                          labelPadding:
                              const EdgeInsets.only(left: 8, right: 4),
                        ),
                      if (_selectedCategory != null)
                        Chip(
                          label: Text(_selectedCategory!,
                              style: const TextStyle(fontSize: 12)),
                          onDeleted: () => _onCategoryChanged(null),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey.shade300),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.all(0),
                          labelPadding:
                              const EdgeInsets.only(left: 8, right: 4),
                        ),
                      if (_selectedTag != null)
                        Chip(
                          label: Text('Címke: $_selectedTag',
                              style: const TextStyle(fontSize: 12)),
                          onDeleted: () => _onTagChanged(null),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey.shade300),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.all(0),
                          labelPadding:
                              const EdgeInsets.only(left: 8, right: 4),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: _hasActiveFilters
                    ? (_cachedGrid ??
                        NoteCardGrid(
                          searchText: _searchText,
                          selectedStatus: _selectedStatus,
                          selectedCategory: _selectedCategory,
                          selectedScience: _selectedScience,
                          selectedTag: _selectedTag,
                          selectedType: _selectedType,
                        ))
                    : _buildMapMode(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= 1200) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            body: Row(
              children: [
                Sidebar(
                  selectedMenu: 'notes',
                  extraPanel: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Filters(
                      categories: _visibleCategories,
                      sciences: _sciences,
                      tags: _visibleTags,
                      selectedStatus: _selectedStatus,
                      selectedCategory: _selectedCategory,
                      selectedScience: _selectedScience,
                      selectedTag: _selectedTag,
                      selectedType: _selectedType,
                      onStatusChanged: _onStatusChanged,
                      onCategoryChanged: _onCategoryChanged,
                      onScienceChanged: _onScienceChanged,
                      onTagChanged: _onTagChanged,
                      onTypeChanged: _onTypeChanged,
                      onClearFilters: _onClearFilters,
                      onApplyFilters: _onApplyFilters, // Kézi indító gomb
                      vertical: true,
                      showStatus: false,
                      showType: false,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: buildContent(
                    showSideFilters: false,
                    includeHeader: true,
                    showHeaderActions: true,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          appBar: AppBar(
            title: const Text('Tags'),
          ),
          drawer: Drawer(
            child: SafeArea(
              child: Sidebar(
                selectedMenu: 'notes',
                isDrawer: true,
                extraPanel: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Filters(
                        categories: _visibleCategories,
                        sciences: _sciences,
                        tags: _visibleTags,
                        selectedStatus: _selectedStatus,
                        selectedCategory: _selectedCategory,
                        selectedScience: _selectedScience,
                        selectedTag: _selectedTag,
                        selectedType: _selectedType,
                        onStatusChanged: _onStatusChanged,
                        onCategoryChanged: _onCategoryChanged,
                        onScienceChanged: _onScienceChanged,
                        onTagChanged: _onTagChanged,
                        onTypeChanged: _onTypeChanged,
                        onClearFilters: _onClearFilters,
                        onApplyFilters: _onApplyFilters,
                        vertical: true,
                        showStatus: false,
                        showType: false,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: LayoutBuilder(builder: (context, c) {
                        final isNarrow = c.maxWidth < 360;
                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton(
                                onPressed: () => context.go('/account'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF97316),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Fiók adatok'),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () async {
                                  await FirebaseAuth.instance.signOut();
                                  if (context.mounted) context.go('/login');
                                },
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Kijelentkezés'),
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => context.go('/account'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF97316),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 40),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Fiók adatok'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  await FirebaseAuth.instance.signOut();
                                  if (context.mounted) context.go('/login');
                                },
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Kijelentkezés'),
                              ),
                            ),
                          ],
                        );
                      }),
                    )
                  ],
                ),
              ),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: buildContent(
              showSideFilters: false,
              includeHeader: true,
              showHeaderActions: false,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapMode() {
    if (_categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // A "Dialogus tags" kategóriát mindig a végére tesszük, ha létezik
    final sortedCategories = List<String>.from(_categories);
    if (sortedCategories.contains('Dialogus tags')) {
      sortedCategories.remove('Dialogus tags');
      sortedCategories.add('Dialogus tags');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        return _buildMapFolder(sortedCategories[index]);
      },
    );
  }

  Widget _buildMapFolder(String category) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CategoryTagsScreen(category: category),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined,
                  color: Color(0xFF1976D2), size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF202122)),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
