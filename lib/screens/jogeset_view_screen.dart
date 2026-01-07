import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/firebase_config.dart';
import '../models/jogeset_models.dart';
import '../services/jogeset_service.dart';
import '../widgets/breadcrumb_navigation.dart';
import '../utils/filter_storage.dart';
import '../widgets/jogeset/jogeset_section_widgets.dart';

/// Jogeset megjelenítő képernyő léptetéses navigációval.
///
/// Hasonló a memóriapalota állomások megjelenítéséhez, de jogeseteket jelenít meg.
/// Egy dokumentumban (paragrafusban) több jogeset van, ezeket lehet léptetni.
class JogesetViewScreen extends StatefulWidget {
  final String documentId;
  final int?
      jogesetId; // Opcionális: ha meg van adva, ezt a jogesetet nyitja meg
  final String? from;

  const JogesetViewScreen({
    super.key,
    required this.documentId,
    this.jogesetId,
    this.from,
  });

  @override
  State<JogesetViewScreen> createState() => _JogesetViewScreenState();
}

class _JogesetViewScreenState extends State<JogesetViewScreen> {
  JogesetDocument? _document;
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isMegoldasVisible = false;
  bool _isAdmin = false;

  // PageController a mobilnézetben való lapozáshoz
  PageController? _pageController;

  // Jegyzet adatok breadcrumb-hoz
  String? _noteTitle;
  String? _noteCategory;
  String? _noteTag;

  // Header összecsukott állapota mobilnézetben (ValueNotifier a teljes rebuild elkerülésére)
  final ValueNotifier<bool> _isHeaderCollapsedNotifier =
      ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _loadFiltersFromUrl();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkAdminStatus();
    _loadDocument();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _isHeaderCollapsedNotifier.dispose();
    super.dispose();
  }

  /// Betölti a FilterStorage értékeit az előző oldal URL-jéből (from paraméter)
  void _loadFiltersFromUrl() {
    if (widget.from != null && widget.from!.isNotEmpty) {
      try {
        final fromUri = Uri.parse(Uri.decodeComponent(widget.from!));
        final queryParams = fromUri.queryParameters;

        FilterStorage.searchText = queryParams['q'];
        FilterStorage.status = queryParams['status'];
        FilterStorage.category = queryParams['category'];
        FilterStorage.science = queryParams['science'];
        FilterStorage.tag = queryParams['tag'];
        FilterStorage.type = queryParams['type'];

        debugPrint('🔵 JogesetViewScreen _loadFiltersFromUrl:');
        debugPrint('   from=${widget.from}');
        debugPrint('   tag=${FilterStorage.tag}');
        debugPrint('   category=${FilterStorage.category}');
      } catch (e) {
        debugPrint('🔴 Hiba a FilterStorage betöltésekor az URL-ből: $e');
      }
    }
  }

  /// Admin státusz ellenőrzése
  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isAdmin = false);
      return;
    }

    try {
      final userDoc = await FirebaseConfig.firestore
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};
      final userType = (userData['userType'] as String? ?? '').toLowerCase();
      final isAdminEmail = user.email == 'tattila.ninox@gmail.com';
      final isAdminBool = userData['isAdmin'] == true;

      if (mounted) {
        setState(() {
          _isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;
        });
      }
    } catch (e) {
      debugPrint('🔴 Hiba az admin státusz ellenőrzésekor: $e');
      if (mounted) setState(() => _isAdmin = false);
    }
  }

  /// Dokumentum betöltése
  Future<void> _loadDocument() async {
    try {
      final document = await JogesetService.getJogesetDocument(
        widget.documentId,
        isAdmin: _isAdmin,
      );

      if (!mounted) return;

      // Ha meg van adva jogesetId, megkeressük a megfelelő indexet
      int initialIndex = 0;
      if (widget.jogesetId != null && document != null) {
        final index = document.jogesetek.indexWhere(
          (jogeset) => jogeset.id == widget.jogesetId,
        );
        if (index >= 0) {
          initialIndex = index;
        }
      }

      // PageController inicializálása mobilnézetben
      final screenWidth = MediaQuery.of(context).size.width;
      final isMobile = screenWidth < 600;
      if (isMobile && document != null && document.jogesetek.isNotEmpty) {
        _pageController ??= PageController(initialPage: 0);
      }

      setState(() {
        _document = document;
        _currentIndex = initialIndex;
        _isLoading = false;
        _isMegoldasVisible = false;
      });

      // Betöltjük a jegyzet adatait breadcrumb-hoz
      if (document != null && document.jogesetek.isNotEmpty) {
        final firstJogeset = document.jogesetek.first;
        setState(() {
          _noteTitle = firstJogeset.title;
          _noteCategory = firstJogeset.category;
          _noteTag =
              firstJogeset.tags.isNotEmpty ? firstJogeset.tags.first : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a jogeset betöltésekor: $e')),
        );
      }
    }
  }

  /// Következő jogeset megjelenítése
  void _nextJogeset() {
    if (_document == null || _currentIndex >= _document!.jogesetek.length - 1) {
      return;
    }

    setState(() {
      _currentIndex++;
      _isMegoldasVisible = false;
      _isHeaderCollapsedNotifier.value = false;
    });

    // PageController alaphelyzetbe állítása az új jogesetnél
    _pageController?.jumpToPage(0);
  }

  /// Előző jogeset megjelenítése
  void _previousJogeset() {
    if (_currentIndex <= 0) {
      return;
    }

    setState(() {
      _currentIndex--;
      _isMegoldasVisible = false;
      _isHeaderCollapsedNotifier.value = false;
    });

    // PageController alaphelyzetbe állítása az új jogesetnél
    _pageController?.jumpToPage(0);
  }

  /// Egy adott jogesethez ugrik
  void _jumpToJogeset(int index) {
    if (_document == null ||
        index < 0 ||
        index >= _document!.jogesetek.length) {
      return;
    }

    setState(() {
      _currentIndex = index;
      _isMegoldasVisible = false;
      _isHeaderCollapsedNotifier.value = false;
    });

    // PageController alaphelyzetbe állítása az új jogesetnél
    _pageController?.jumpToPage(0);
  }

  /// Megoldás láthatóságának váltása
  void _toggleMegoldas() {
    setState(() {
      _isMegoldasVisible = !_isMegoldasVisible;
    });
  }

  /// Vissza navigáció
  void _navigateBack() {
    final state = GoRouterState.of(context);
    final bundleId = state.uri.queryParameters['bundleId'];

    // Ha kötegből jöttünk, oda megyünk vissza
    if (bundleId != null && bundleId.isNotEmpty) {
      context.go('/my-bundles/view/$bundleId');
      return;
    }

    final effectiveTag = FilterStorage.tag;
    final effectiveCategory = FilterStorage.category;

    if (effectiveTag != null && effectiveTag.isNotEmpty) {
      final uri = Uri(
        path: '/notes',
        queryParameters: {
          if (FilterStorage.searchText != null &&
              FilterStorage.searchText!.isNotEmpty)
            'q': FilterStorage.searchText!,
          if (FilterStorage.status != null) 'status': FilterStorage.status!,
          if (effectiveCategory != null) 'category': effectiveCategory,
          if (FilterStorage.science != null) 'science': FilterStorage.science!,
          'tag': effectiveTag,
          if (FilterStorage.type != null) 'type': FilterStorage.type!,
        },
      );
      context.go(uri.toString());
    } else if (effectiveCategory != null && effectiveCategory.isNotEmpty) {
      final uri = Uri(
        path: '/notes',
        queryParameters: {
          if (FilterStorage.searchText != null &&
              FilterStorage.searchText!.isNotEmpty)
            'q': FilterStorage.searchText!,
          if (FilterStorage.status != null) 'status': FilterStorage.status!,
          'category': effectiveCategory,
          if (FilterStorage.science != null) 'science': FilterStorage.science!,
          if (FilterStorage.type != null) 'type': FilterStorage.type!,
        },
      );
      context.go(uri.toString());
    } else {
      final uri = Uri(
        path: '/notes',
        queryParameters: {
          if (FilterStorage.searchText != null &&
              FilterStorage.searchText!.isNotEmpty)
            'q': FilterStorage.searchText!,
          if (FilterStorage.status != null) 'status': FilterStorage.status!,
          if (FilterStorage.science != null) 'science': FilterStorage.science!,
          if (FilterStorage.type != null) 'type': FilterStorage.type!,
        },
      );
      context.go(uri.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_document == null || _document!.jogesetek.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Jogeset nem található'),
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: Theme.of(context).primaryColor,
            ),
            onPressed: _navigateBack,
          ),
        ),
        body: const Center(
          child:
              Text('Ez a jogeset nem található vagy nincs elérhető jogeset.'),
        ),
      );
    }

    final currentJogeset = _document!.jogesetek[_currentIndex];
    final totalJogesetek = _document!.jogesetek.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                currentJogeset.title,
                style: TextStyle(
                  fontSize: isMobile
                      ? 10.0
                      : 18.0, // Mobilnézetben 2px-el kisebb (12-2)
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_currentIndex + 1}/$totalJogesetek',
                style: TextStyle(
                  fontSize: isMobile ? 12.0 : 14.0,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: Theme.of(context).primaryColor,
            size: isMobile ? 18.0 : 22.0,
          ),
          onPressed: _navigateBack,
        ),
        actions: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.list),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => Container(
                    height: MediaQuery.of(context).size.height * 0.7,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: _buildJogesetNavigationList(isMobile: true),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Breadcrumb navigáció - elrejtve, ha kötegből jöttünk
          if (GoRouterState.of(context).uri.queryParameters['bundleId'] ==
                  null ||
              GoRouterState.of(context)
                  .uri
                  .queryParameters['bundleId']!
                  .isEmpty)
            BreadcrumbNavigation(
              category: _noteCategory,
              tag: _noteTag,
              noteTitle: _noteTitle,
              noteId: widget.documentId,
              fromBundleId:
                  GoRouterState.of(context).uri.queryParameters['bundleId'],
            ),

          // Tartalom
          Expanded(
            child: Row(
              children: [
                // Navigációs sidebar (csak asztali nézetben)
                if (!isMobile)
                  Container(
                    width: 300.0,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        right: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: _buildJogesetNavigationList(isMobile: false),
                  ),
                // Fő tartalom
                Expanded(
                  child: Container(
                    color: const Color(0xFFF8F9FA),
                    child: isMobile && _pageController != null
                        ? _buildMobilePagedContent(currentJogeset, isMobile)
                        : _buildDesktopContent(currentJogeset, isMobile),
                  ),
                ),
              ],
            ),
          ),

          // Léptetés vezérlők
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4.0,
                  offset: const Offset(0.0, -2.0),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _currentIndex > 0 ? _previousJogeset : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Előző'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 24,
                      vertical: isMobile ? 12 : 16,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed:
                      _currentIndex < totalJogesetek - 1 ? _nextJogeset : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Következő'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 24,
                      vertical: isMobile ? 12 : 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mobilnézeti lapozható tartalom
  Widget _buildMobilePagedContent(Jogeset currentJogeset, bool isMobile) {
    final pages = <Widget>[];

    // Oldal 1: Fikció
    pages.add(JogesetSectionWidgets.buildMobilePage(
      title: 'Fikció:',
      content: currentJogeset.tenyek,
      isMobile: isMobile,
    ));

    // Oldal 2: Jogi kérdés
    pages.add(JogesetSectionWidgets.buildMobilePageHighlighted(
      title: 'Kérdés',
      content: currentJogeset.kerdes,
      color: Colors.blue.shade50,
      borderColor: Colors.blue.shade200,
      isMobile: isMobile,
    ));

    // Oldal 3: Következtetés
    pages.add(JogesetSectionWidgets.buildMobilePageHighlighted(
      title: 'Következtetés',
      content: currentJogeset.megoldas,
      color: Colors.green.shade50,
      borderColor: Colors.green.shade300,
      isMobile: isMobile,
    ));

    // Oldal 4: Eredeti jogszabály (ha van)
    if (currentJogeset.eredetiJogszabalySzoveg != null &&
        currentJogeset.eredetiJogszabalySzoveg!.isNotEmpty) {
      pages.add(JogesetSectionWidgets.buildMobilePage(
        title: 'Eredeti jogszabály szöveg',
        content: currentJogeset.eredetiJogszabalySzoveg!,
        isMobile: isMobile,
        isItalic: true,
      ));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // Csak a függőleges görgetést figyeljük a belső tartalomnál (SingleChildScrollView)
          // Mivel a PageView alatt vannak, a depth itt 1 lesz
          if (notification.metrics.axis == Axis.vertical) {
            final pixels = notification.metrics.pixels;
            if (pixels > 40 && !_isHeaderCollapsedNotifier.value) {
              _isHeaderCollapsedNotifier.value = true;
            } else if (pixels < 20 && _isHeaderCollapsedNotifier.value) {
              _isHeaderCollapsedNotifier.value = false;
            }
          }
        }
        return false;
      },
      child: Column(
        children: [
          // Fix fejléc a mobil lapozó fölött (animált összecsukással)
          ValueListenableBuilder<bool>(
            valueListenable: _isHeaderCollapsedNotifier,
            builder: (context, isCollapsed, _) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  20.0,
                  isCollapsed ? 10.0 : 20.0,
                  20.0,
                  isCollapsed ? 10.0 : 0.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.2),
                      width: isCollapsed ? 1.0 : 0.0,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentJogeset.cim,
                      style: TextStyle(
                        fontSize: isCollapsed ? 9.0 : 14.0,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF202122),
                      ),
                      maxLines: isCollapsed ? 1 : null,
                      overflow: isCollapsed ? TextOverflow.ellipsis : null,
                    ),
                    if (!isCollapsed) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.swipe,
                            size: 14.0,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Lapozz jobbra a következő oldalért',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const PageScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              allowImplicitScrolling: false,
              itemCount: pages.length,
              itemBuilder: (context, index) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      pages[index],
                      // Oldal számláló
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          '${index + 1}/${pages.length}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Asztali nézeti tartalom (eredeti)
  Widget _buildDesktopContent(Jogeset currentJogeset, bool isMobile) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900.0),
        margin: const EdgeInsets.symmetric(horizontal: 0.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.all(isMobile ? 20.0 : 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cím
            Text(
              currentJogeset.cim,
              style: TextStyle(
                fontSize: isMobile ? 16.0 : 22.0,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF202122),
              ),
            ),

            const SizedBox(height: 24),

            // Fikció
            JogesetSectionWidgets.buildSection(
              title: 'Fikció:',
              content: currentJogeset.tenyek,
              isMobile: isMobile,
            ),

            const SizedBox(height: 24),

            // Kérdés (kiemelt)
            JogesetSectionWidgets.buildHighlightedSection(
              title: 'Kérdés',
              content: currentJogeset.kerdes,
              color: Colors.blue.shade50,
              borderColor: Colors.blue.shade200,
              isMobile: isMobile,
            ),

            const SizedBox(height: 8),

            // Következtetés megjelenítése/elrejtése gomb
            Center(
              child: ElevatedButton.icon(
                onPressed: _toggleMegoldas,
                icon: Icon(_isMegoldasVisible
                    ? Icons.visibility_off
                    : Icons.visibility),
                label: Text(_isMegoldasVisible
                    ? 'Következtetés elrejtése'
                    : 'Következtetés megjelenítése'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            // Következtetés (kiemelt, feltételesen látható)
            if (_isMegoldasVisible) ...[
              const SizedBox(height: 24),
              JogesetSectionWidgets.buildHighlightedSection(
                title: 'Következtetés',
                content: currentJogeset.megoldas,
                color: Colors.green.shade50,
                borderColor: Colors.green.shade300,
                isMobile: isMobile,
              ),
            ],

            // Eredeti jogszabály szöveg (expandable)
            if (currentJogeset.eredetiJogszabalySzoveg != null &&
                currentJogeset.eredetiJogszabalySzoveg!.isNotEmpty) ...[
              const SizedBox(height: 24),
              ExpansionTile(
                initiallyExpanded: false,
                title: const Text(
                  'Eredeti jogszabály szöveg',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      currentJogeset.eredetiJogszabalySzoveg!,
                      style: const TextStyle(
                        fontSize: 14.0,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF555555),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Jogeset navigációs lista (közös a mobil és asztali nézethez)
  Widget _buildJogesetNavigationList({required bool isMobile}) {
    if (_document == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMobile)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.list_alt, color: Theme.of(context).primaryColor),
                const SizedBox(width: 10),
                const Text(
                  'Tartalomjegyzék',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _document!.jogesetek.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final jogeset = _document!.jogesetek[index];
              final isSelected = index == _currentIndex;

              return ListTile(
                leading: CircleAvatar(
                  radius: 14.0,
                  backgroundColor: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade200,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12.0,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  jogeset.cim,
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 13,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  _jumpToJogeset(index);
                  if (isMobile) {
                    Navigator.pop(context); // Mobilnál bezárjuk a sheet-et
                  }
                },
                selected: isSelected,
                tileColor:
                    isSelected ? Colors.blue.withValues(alpha: 0.05) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
