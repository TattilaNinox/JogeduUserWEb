import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/firebase_config.dart';

import '../utils/filter_storage.dart';
import '../utils/category_state.dart';
import '../widgets/sidebar.dart';
import '../widgets/header.dart';
import '../widgets/filters.dart';
import '../widgets/note_card_grid.dart';

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

  // Listák a Firestore-ból betöltött kategóriák, tudományok és címkék tárolására.
  List<String> _categories = [];
  List<String> _sciences = [];
  List<String> _tags = [];

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Minden alkalommal, amikor a widget újraépül, ellenőrizzük a mentett szűrőket
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedFilters();
    });
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
        _selectedType = widget.initialType;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Betölti a kategóriákat a notes kollekcióból.
  /// Csak azokat a kategóriákat tölti be, amelyek science mezője megegyezik
  /// a felhasználó tudományágával és Published státuszúak (admin esetén Draft is).
  Future<void> _loadCategories() async {
    try {
      // Lekérjük a bejelentkezett felhasználó tudományágát
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _categories = []);
        return;
      }

      // Admin ellenőrzés
      bool isAdmin = false;
      try {
        final userDoc = await FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .get();
        final userData = userDoc.data() ?? {};
        final userType = (userData['userType'] as String? ?? '').toLowerCase();
        final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
        final isAdminBool = userData['isAdmin'] == true;
        isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;
      } catch (e) {
        // Ha hiba van az admin ellenőrzésben, nem adminként kezeljük
        isAdmin = false;
      }

      // FIX: Webalkalmazásban MINDIG csak "Jogász" tudományág
      const userScience = 'Jogász';

      // Lekérjük a notes-okat, szűrve a felhasználó tudományágára és státuszra
      // Admin esetén Draft státuszú jegyzeteket is betöltjük
      Query<Map<String, dynamic>> query = FirebaseConfig.firestore
          .collection('notes')
          .where('science', isEqualTo: userScience);
      
      if (isAdmin) {
        query = query.where('status', whereIn: ['Published', 'Draft']);
      } else {
        query = query.where('status', isEqualTo: 'Published');
      }
      
      final snapshot = await query.get();

      // Kinyerjük az egyedi kategóriákat
      final categoriesSet = <String>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['deletedAt'] == null) {
          final category = data['category'] as String?;
          if (category != null && category.isNotEmpty) {
            categoriesSet.add(category);
          }
        }
      }

      setState(() {
        _categories = categoriesSet.toList()..sort();
      });
    } catch (e) {
      // Hiba esetén üres lista
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
      // Lekérjük a bejelentkezett felhasználót
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _tags = []);
        return;
      }

      // Admin ellenőrzés
      bool isAdmin = false;
      try {
        final userDoc = await FirebaseConfig.firestore
            .collection('users')
            .doc(user.uid)
            .get();
        final userData = userDoc.data() ?? {};
        final userType = (userData['userType'] as String? ?? '').toLowerCase();
        final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
        final isAdminBool = userData['isAdmin'] == true;
        isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;
      } catch (e) {
        // Ha hiba van az admin ellenőrzésben, nem adminként kezeljük
        isAdmin = false;
      }

      // FIX: Webalkalmazásban MINDIG csak "Jogász" tudományág
      const userScience = 'Jogász';

      // Admin esetén Draft státuszú jegyzeteket is betöltjük
      Query<Map<String, dynamic>> query = FirebaseConfig.firestore
          .collection('notes')
          .where('science', isEqualTo: userScience);
      
      if (isAdmin) {
        query = query.where('status', whereIn: ['Published', 'Public', 'Draft']);
      } else {
        query = query.where('status', whereIn: ['Published', 'Public']);
      }
      
      final notesSnapshot = await query.get();
      final allTags = <String>{};

      for (final doc in notesSnapshot.docs) {
        final data = doc.data();
        if (data.containsKey('tags') && data['tags'] is List) {
          final tags = List<String>.from(data['tags']);
          allTags.addAll(tags);
        }
      }

      if (mounted) {
        setState(() {
          _tags = allTags.toList()..sort();
        });
      }
    } catch (e) {
      // Ha jogosultság/lekérdezési hiba, ne akassza meg az oldalt
      if (mounted) {
        setState(() {
          _tags = const [];
        });
      }
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
    // Menti a státusz szűrőt a FilterStorage-ba
    FilterStorage.status = value;
    _pushFiltersToUrl();
  }

  /// Frissíti a kiválasztott kategóriát a `Filters` widgetből.
  void _onCategoryChanged(String? value) {
    setState(() {
      _selectedCategory = value;
    });
    // Menti a kategória szűrőt a FilterStorage-ba
    FilterStorage.category = value;
    // Menti a CategoryState-be is
    CategoryState.setCategoryState(
      searchText: _searchText.isNotEmpty ? _searchText : null,
      category: value,
      science: _selectedScience,
      tag: _selectedTag,
      type: _selectedType,
    );
    _pushFiltersToUrl();
  }

  /// Frissíti a kiválasztott tudományt.
  void _onScienceChanged(String? value) {
    setState(() {
      _selectedScience = value;
    });
    // Menti a tudomány szűrőt a FilterStorage-ba
    FilterStorage.science = value;
    // Menti a CategoryState-be is
    CategoryState.setCategoryState(
      searchText: _searchText.isNotEmpty ? _searchText : null,
      category: _selectedCategory,
      science: value,
      tag: _selectedTag,
      type: _selectedType,
    );
    _pushFiltersToUrl();
  }

  /// Frissíti a kiválasztott címkét a `Filters` widgetből.
  void _onTagChanged(String? value) {
    setState(() => _selectedTag = value);
    // Menti a címke szűrőt a FilterStorage-ba
    FilterStorage.tag = value;
    // Menti a CategoryState-be is
    CategoryState.setCategoryState(
      searchText: _searchText.isNotEmpty ? _searchText : null,
      category: _selectedCategory,
      science: _selectedScience,
      tag: value,
      type: _selectedType,
    );
    _pushFiltersToUrl();
  }

  /// Frissíti a kiválasztott típust.
  void _onTypeChanged(String? value) {
    setState(() => _selectedType = value);
    // Menti a típus szűrőt a FilterStorage-ba
    FilterStorage.type = value;
    // Menti a CategoryState-be is
    CategoryState.setCategoryState(
      searchText: _searchText.isNotEmpty ? _searchText : null,
      category: _selectedCategory,
      science: _selectedScience,
      tag: _selectedTag,
      type: value,
    );
    _pushFiltersToUrl();
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
                        categories: _categories,
                        sciences: _sciences,
                        tags: _tags,
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
              Expanded(
                child: NoteCardGrid(
                  searchText: _searchText,
                  selectedStatus: _selectedStatus,
                  selectedCategory: _selectedCategory,
                  selectedScience: _selectedScience,
                  selectedTag: _selectedTag,
                  selectedType: _selectedType,
                ),
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
            backgroundColor: const Color.fromARGB(255, 249, 250, 251),
            body: Row(
              children: [
                Sidebar(
                  selectedMenu: 'notes',
                  extraPanel: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Filters(
                      categories: _categories,
                      sciences: _sciences,
                      tags: _tags,
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
                      vertical: true,
                      showStatus: false,
                      showType: false,
                    ),
                  ),
                ),
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
          appBar: AppBar(
            title: const Text('Jegyzetek'),
          ),
          drawer: Drawer(
            child: SafeArea(
              child: Sidebar(
                selectedMenu: 'notes',
                extraPanel: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Filters(
                        categories: _categories,
                        sciences: _sciences,
                        tags: _tags,
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
          backgroundColor: const Color.fromARGB(255, 249, 250, 251),
        );
      },
    );
  }
}
