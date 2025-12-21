import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_html/flutter_html.dart';
import '../core/firebase_config.dart';
import '../models/jogeset_models.dart';
import '../services/jogeset_service.dart';
import '../widgets/breadcrumb_navigation.dart';
import '../utils/filter_storage.dart';

/// Jogeset megjelenítő képernyő léptetéses navigációval.
///
/// Hasonló a memóriapalota állomások megjelenítéséhez, de jogeseteket jelenít meg.
/// Egy dokumentumban (paragrafusban) több jogeset van, ezeket lehet léptetni.
class JogesetViewScreen extends StatefulWidget {
  final String documentId;
  final int? jogesetId; // Opcionális: ha meg van adva, ezt a jogesetet nyitja meg
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
  int _currentPageIndex = 0;

  // Jegyzet adatok breadcrumb-hoz
  String? _noteTitle;
  String? _noteCategory;
  String? _noteTag;

  @override
  void initState() {
    super.initState();
    _loadFiltersFromUrl();
    _checkAdminStatus();
    _loadDocument();
  }

  @override
  void dispose() {
    _pageController?.dispose();
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
      setState(() => _isAdmin = false);
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

      setState(() {
        _isAdmin = userType == 'admin' || isAdminEmail || isAdminBool;
      });
    } catch (e) {
      debugPrint('🔴 Hiba az admin státusz ellenőrzésekor: $e');
      setState(() => _isAdmin = false);
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

      setState(() {
        _document = document;
        _currentIndex = initialIndex;
        _isLoading = false;
        _isMegoldasVisible = false;
        _currentPageIndex = 0;
      });
      
      // PageController inicializálása mobilnézetben
      final screenWidth = MediaQuery.of(context).size.width;
      final isMobile = screenWidth < 600;
      if (isMobile && document != null && document.jogesetek.isNotEmpty) {
        _pageController = PageController(initialPage: 0);
      }

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
      _currentPageIndex = 0;
    });
    
    // PageController újrainicializálása új jogesethez
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    if (isMobile && _document != null) {
      _pageController?.dispose();
      _pageController = PageController(initialPage: 0);
    }
  }

  /// Előző jogeset megjelenítése
  void _previousJogeset() {
    if (_currentIndex <= 0) {
      return;
    }

    setState(() {
      _currentIndex--;
      _isMegoldasVisible = false;
      _currentPageIndex = 0;
    });
    
    // PageController újrainicializálása új jogesethez
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    if (isMobile && _document != null) {
      _pageController?.dispose();
      _pageController = PageController(initialPage: 0);
    }
  }
  

  /// Megoldás láthatóságának váltása
  void _toggleMegoldas() {
    setState(() {
      _isMegoldasVisible = !_isMegoldasVisible;
    });
  }

  /// Vissza navigáció
  void _navigateBack() {
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
                  fontSize: isMobile ? 14 : 18, // Mobilnézetben 2px-el kisebb (16-2)
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
                  fontSize: 14,
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
            size: isMobile ? 20 : 22,
          ),
          onPressed: _navigateBack,
        ),
      ),
      body: Column(
        children: [
          // Breadcrumb navigáció
          BreadcrumbNavigation(
            category: _noteCategory,
            tag: _noteTag,
            noteTitle: _noteTitle,
            noteId: widget.documentId,
          ),

          // Tartalom
          Expanded(
            child: Container(
              color: const Color(0xFFF8F9FA),
              child: isMobile && _pageController != null
                  ? _buildMobilePagedContent(currentJogeset, isMobile)
                  : _buildDesktopContent(currentJogeset, isMobile),
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
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: isMobile && _pageController != null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Előző jogeset gomb
                      ElevatedButton.icon(
                        onPressed: _currentIndex > 0 ? _previousJogeset : null,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Előző jogeset'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      // Következő jogeset gomb
                      ElevatedButton.icon(
                        onPressed: _currentIndex < totalJogesetek - 1 ? _nextJogeset : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Következő jogeset'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
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
    
    // Oldal 1: Tényállás
    pages.add(_buildMobilePage(
      title: 'Tényállás',
      content: currentJogeset.tenyek,
      isMobile: isMobile,
    ));
    
    // Oldal 2: Jogi kérdés
    pages.add(_buildMobilePageHighlighted(
      title: 'Jogi kérdés',
      content: currentJogeset.kerdes,
      color: Colors.blue.shade50,
      borderColor: Colors.blue.shade200,
      isMobile: isMobile,
    ));
    
    // Oldal 3: Megoldás
    pages.add(_buildMobilePageHighlighted(
      title: 'Megoldás',
      content: currentJogeset.megoldas,
      color: Colors.green.shade50,
      borderColor: Colors.green.shade300,
      isMobile: isMobile,
    ));
    
    // Oldal 4: Eredeti jogszabály (ha van)
    if (currentJogeset.eredetiJogszabalySzoveg != null &&
        currentJogeset.eredetiJogszabalySzoveg!.isNotEmpty) {
      pages.add(_buildMobilePage(
        title: 'Eredeti jogszabály szöveg',
        content: currentJogeset.eredetiJogszabalySzoveg!,
        isMobile: isMobile,
        isItalic: true,
      ));
    }
    
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        setState(() {
          _currentPageIndex = index;
        });
      },
      itemCount: pages.length,
      itemBuilder: (context, index) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cím és komplexitás badge (csak első oldalon)
                if (index == 0) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentJogeset.cim,
                                  style: TextStyle(
                                    fontSize: 16, // További csökkentés: 18-2
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF202122),
                                  ),
                                ),
                                // Lapozási ikon és szöveg mobilnézetben
                                if (isMobile && _pageController != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.swipe,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Lapozz jobbra a következő oldalért',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    label: 'Alkalmazandó jogszabály:',
                    value: currentJogeset.alkalmazandoJogszabaly,
                    isMobile: true,
                  ),
                  const SizedBox(height: 24),
                ],
                pages[index],
                // Oldal számláló
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '${index + 1}/${pages.length}',
                    style: TextStyle(
                      fontSize: 12, // 14-2
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Asztali nézeti tartalom (eredeti)
  Widget _buildDesktopContent(Jogeset currentJogeset, bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900),
        margin: const EdgeInsets.symmetric(horizontal: 0),
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
        padding: EdgeInsets.all(isMobile ? 20 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cím
            Text(
              currentJogeset.cim,
              style: TextStyle(
                fontSize: isMobile ? 16 : 22, // Mobilnézetben tovább csökkentve: 18-2, asztali: 24-2
                fontWeight: FontWeight.bold,
                color: const Color(0xFF202122),
              ),
            ),

            const SizedBox(height: 24),

            // Tényállás
            _buildSection(
              title: 'Tényállás',
              content: currentJogeset.tenyek,
              isMobile: isMobile,
            ),

            const SizedBox(height: 24),

            // Kérdés (kiemelt)
            _buildHighlightedSection(
              title: 'Jogi kérdés',
              content: currentJogeset.kerdes,
              color: Colors.blue.shade50,
              borderColor: Colors.blue.shade200,
              isMobile: isMobile,
            ),

            const SizedBox(height: 24),

            // Alkalmazandó jogszabály
            _buildInfoRow(
              label: 'Alkalmazandó jogszabály:',
              value: currentJogeset.alkalmazandoJogszabaly,
              isMobile: isMobile,
            ),

            const SizedBox(height: 24),

            // Megoldás megjelenítése/elrejtése gomb
            Center(
              child: ElevatedButton.icon(
                onPressed: _toggleMegoldas,
                icon: Icon(_isMegoldasVisible
                    ? Icons.visibility_off
                    : Icons.visibility),
                label: Text(_isMegoldasVisible
                    ? 'Megoldás elrejtése'
                    : 'Megoldás megjelenítése'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            // Megoldás (kiemelt, feltételesen látható)
            if (_isMegoldasVisible) ...[
              const SizedBox(height: 24),
              _buildHighlightedSection(
                title: 'Megoldás',
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
                        fontSize: 14,
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

  /// Mobilnézeti oldal widget
  Widget _buildMobilePage({
    required String title,
    required String content,
    required bool isMobile,
    bool isItalic = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14, // 16-2
            fontWeight: FontWeight.w600,
            color: const Color(0xFF202122),
          ),
        ),
        const SizedBox(height: 8),
        Html(
          data: '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
          style: {
            "div": Style(
              fontSize: FontSize(12), // 14-2
              color: const Color(0xFF444444),
              lineHeight: const LineHeight(1.6),
              padding: HtmlPaddings.zero,
              margin: Margins.zero,
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            ),
          },
        ),
      ],
    );
  }

  /// Mobilnézeti kiemelt oldal widget
  Widget _buildMobilePageHighlighted({
    required String title,
    required String content,
    required Color color,
    required Color borderColor,
    required bool isMobile,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14, // 16-2
              fontWeight: FontWeight.w600,
              color: const Color(0xFF202122),
            ),
          ),
          const SizedBox(height: 8),
          Html(
            data: '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
            style: {
              "div": Style(
                fontSize: FontSize(12), // 14-2
                color: const Color(0xFF444444),
                lineHeight: const LineHeight(1.6),
                padding: HtmlPaddings.zero,
                margin: Margins.zero,
              ),
            },
          ),
        ],
      ),
    );
  }

  /// Szekció widget
  Widget _buildSection({
    required String title,
    required String content,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 14 : 18, // Mobilnézetben 2px-el kisebb (16-2)
            fontWeight: FontWeight.w600,
            color: const Color(0xFF202122),
          ),
        ),
        const SizedBox(height: 8),
        Html(
          data: '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
          style: {
            "div": Style(
              fontSize: FontSize(isMobile ? 12 : 16), // Mobilnézetben 2px-el kisebb (14-2)
              color: const Color(0xFF444444),
              lineHeight: const LineHeight(1.6),
              padding: HtmlPaddings.zero,
              margin: Margins.zero,
            ),
          },
        ),
      ],
    );
  }

  /// Kiemelt szekció widget
  Widget _buildHighlightedSection({
    required String title,
    required String content,
    required Color color,
    required Color borderColor,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 14 : 18, // Mobilnézetben 2px-el kisebb (16-2)
              fontWeight: FontWeight.w600,
              color: const Color(0xFF202122),
            ),
          ),
          const SizedBox(height: 8),
          Html(
            data: '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
            style: {
              "div": Style(
                fontSize: FontSize(isMobile ? 12 : 16), // Mobilnézetben 2px-el kisebb (14-2)
                color: const Color(0xFF444444),
                lineHeight: const LineHeight(1.6),
                padding: HtmlPaddings.zero,
                margin: Margins.zero,
              ),
            },
          ),
        ],
      ),
    );
  }

  /// Info sor widget
  Widget _buildInfoRow({
    required String label,
    required String value,
    required bool isMobile,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 12 : 16, // Mobilnézetben 2px-el kisebb (14-2)
            fontWeight: FontWeight.w600,
            color: const Color(0xFF202122),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Html(
            data: '<div style="text-align: justify;">${_escapeHtml(value)}</div>',
            style: {
              "div": Style(
                fontSize: FontSize(isMobile ? 12 : 16), // Mobilnézetben 2px-el kisebb (14-2)
                color: const Color(0xFF444444),
                padding: HtmlPaddings.zero,
                margin: Margins.zero,
              ),
            },
          ),
        ),
      ],
    );
  }

  /// HTML escape helper metódus
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
