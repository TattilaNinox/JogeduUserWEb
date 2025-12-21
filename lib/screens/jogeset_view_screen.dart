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
  final String? from;

  const JogesetViewScreen({
    super.key,
    required this.documentId,
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

      setState(() {
        _document = document;
        _currentIndex = 0;
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
    });
  }

  /// Előző jogeset megjelenítése
  void _previousJogeset() {
    if (_currentIndex <= 0) {
      return;
    }

    setState(() {
      _currentIndex--;
      _isMegoldasVisible = false;
    });
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
                  fontSize: isMobile ? 16 : 18,
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
              child: SingleChildScrollView(
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
                      // Cím és komplexitás badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              currentJogeset.cim,
                              style: TextStyle(
                                fontSize: isMobile ? 20 : 24,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF202122),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildKomplexitasBadge(currentJogeset.komplexitas),
                        ],
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
                          currentJogeset
                              .eredetiJogszabalySzoveg!.isNotEmpty) ...[
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
              ),
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

  /// Komplexitás badge widget
  Widget _buildKomplexitasBadge(String komplexitas) {
    Color backgroundColor;
    switch (komplexitas.toLowerCase()) {
      case 'egyszerű':
        backgroundColor = const Color(0xFF4CAF50); // zöld
        break;
      case 'közepes':
        backgroundColor = const Color(0xFFFF9800); // narancs
        break;
      case 'komplex':
        backgroundColor = const Color(0xFFF44336); // piros
        break;
      default:
        backgroundColor = const Color(0xFFFF9800); // alapértelmezett: narancs
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        komplexitas,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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
            fontSize: isMobile ? 16 : 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF202122),
          ),
        ),
        const SizedBox(height: 8),
        Html(
          data: '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
          style: {
            "div": Style(
              fontSize: FontSize(isMobile ? 14 : 16),
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
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF202122),
            ),
          ),
          const SizedBox(height: 8),
          Html(
            data: '<div style="text-align: justify;">${_escapeHtml(content)}</div>',
            style: {
              "div": Style(
                fontSize: FontSize(isMobile ? 14 : 16),
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
            fontSize: isMobile ? 14 : 16,
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
                fontSize: FontSize(isMobile ? 14 : 16),
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
