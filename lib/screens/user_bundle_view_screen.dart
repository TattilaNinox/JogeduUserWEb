import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../models/user_bundle.dart';
import '../models/user_bundle_item.dart';
import '../services/user_bundle_service.dart';
import '../utils/filter_storage.dart';
import '../widgets/mini_audio_player.dart';
import '../core/firebase_config.dart';

/// Köteg megtekintő képernyő.
///
/// Infinite Scroll paginációval tölti be az elemeket a subcollection-ből.
/// Támogatja a szűrést és a lazy cleanup-ot.
class UserBundleViewScreen extends StatefulWidget {
  final String bundleId;

  const UserBundleViewScreen({super.key, required this.bundleId});

  @override
  State<UserBundleViewScreen> createState() => _UserBundleViewScreenState();
}

class _UserBundleViewScreenState extends State<UserBundleViewScreen> {
  final _scrollController = ScrollController();

  UserBundle? _bundle;
  final List<UserBundleItem> _items = [];
  DocumentSnapshot? _lastDocument;
  bool _isLoadingBundle = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  // Szűrés
  String _selectedType = 'all';
  final Set<String> _availableTypes = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadBundle();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreItems();
    }
  }

  Future<void> _loadBundle() async {
    try {
      final bundle = await UserBundleService.getBundle(widget.bundleId);
      if (bundle == null) {
        setState(() {
          _error = 'Köteg nem található';
          _isLoadingBundle = false;
        });
        return;
      }

      setState(() {
        _bundle = bundle;
        _isLoadingBundle = false;
      });

      await _loadInitialItems();
    } catch (e) {
      setState(() {
        _error = 'Hiba: $e';
        _isLoadingBundle = false;
      });
    }
  }

  Future<void> _loadInitialItems() async {
    setState(() {
      _items.clear();
      _lastDocument = null;
      _hasMore = true;
    });
    await _loadMoreItems();
  }

  Future<void> _loadMoreItems() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final result = await UserBundleService.getItems(
        widget.bundleId,
        lastDocument: _lastDocument,
        limit: 20,
        typeFilter: _selectedType == 'all' ? null : _selectedType,
      );

      setState(() {
        _items.addAll(result.items);
        _lastDocument = result.lastDoc;
        _hasMore = result.items.length == 20;
        _isLoadingMore = false;

        // Elérhető típusok gyűjtése
        for (final item in result.items) {
          _availableTypes.add(item.type);
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba a betöltés során: $e')),
        );
      }
    }
  }

  void _onTypeFilterChanged(String? newType) {
    if (newType == null || newType == _selectedType) return;
    setState(() {
      _selectedType = newType;
    });
    _loadInitialItems();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (_isLoadingBundle) {
      return Scaffold(
        appBar: AppBar(title: const Text('Betöltés...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hiba')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/my-bundles'),
                child: const Text('Vissza'),
              ),
            ],
          ),
        ),
      );
    }

    final bundle = _bundle!;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: isMobile ? 18 : 20),
          onPressed: () => context.go('/my-bundles'),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_outlined, size: isMobile ? 22 : 24),
            onPressed: () => context.go('/my-bundles/edit/${widget.bundleId}'),
            tooltip: 'Szerkesztés',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header szekció
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Köteg neve
                  Text(
                    bundle.name,
                    style: TextStyle(
                      fontSize: isMobile ? 22 : 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2C3E50),
                    ),
                  ),
                  if (bundle.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      bundle.description,
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 15,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Statisztika
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _buildStatChip(
                          Icons.folder, 'Összes', bundle.totalCount, isMobile),
                      if (bundle.noteCount > 0)
                        _buildStatChip(Icons.description, 'Jegyzet',
                            bundle.noteCount, isMobile),
                      if (bundle.jogesetCount > 0)
                        _buildStatChip(Icons.gavel, 'Jogeset',
                            bundle.jogesetCount, isMobile),
                      if (bundle.dialogusCount > 0)
                        _buildStatChip(Icons.mic, 'Dialógus',
                            bundle.dialogusCount, isMobile),
                      if (bundle.allomasCount > 0)
                        _buildStatChip(Icons.route, 'Útvonal',
                            bundle.allomasCount, isMobile),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Szűrő (ha van több típus)
          if (_availableTypes.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 24.0),
                child: _buildTypeFilter(isMobile),
              ),
            ),

          // Lista elemek
          if (_items.isEmpty && !_isLoadingMore)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      _selectedType == 'all'
                          ? 'Ez a köteg még üres'
                          : 'Nincs ilyen típusú elem',
                      style:
                          TextStyle(fontSize: 16, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < _items.length) {
                      return _buildItemTile(_items[index], isMobile);
                    } else if (_hasMore) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return null;
                  },
                  childCount: _items.length + (_hasMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, int count, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 12,
        vertical: isMobile ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isMobile ? 14 : 16, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: isMobile ? 12 : 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter(bool isMobile) {
    final typeLabels = {
      'all': 'Összes',
      'text': 'Szöveg',
      'deck': 'Tanulókártya',
      'dynamic_quiz': 'Kvíz',
      'dynamic_quiz_dual': 'Páros kvíz',
      'interactive': 'Interaktív',
      'jogeset': 'Jogeset',
      'dialogus': 'Dialógus',
      'allomas': 'Memória útvonal',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedType,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: 'all', child: Text('Összes típus')),
            ..._availableTypes.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(typeLabels[type] ?? type),
                )),
          ],
          onChanged: _onTypeFilterChanged,
        ),
      ),
    );
  }

  Widget _buildItemTile(UserBundleItem item, bool isMobile) {
    final iconData = _getIconForType(item.type);
    final color = _getColorForType(item.type);
    final isDialogue = item.type == 'dialogus';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: isDialogue ? null : () => _navigateToItem(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(iconData, color: color, size: isMobile ? 18 : 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (item.science != null || item.category != null)
                          Text(
                            [item.science, item.category]
                                .whereType<String>()
                                .join(' • '),
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isDialogue)
                    Icon(Icons.chevron_right,
                        color: Colors.grey.shade400, size: 20),
                ],
              ),
              // Dialógus: audio player
              if (isDialogue) ...[
                const SizedBox(height: 12),
                FutureBuilder<String?>(
                  future: _getAudioUrl(item),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return MiniAudioPlayer(
                          audioUrl: snapshot.data!,
                          compact: false,
                          large: true);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'deck':
        return Icons.style;
      case 'dynamic_quiz':
      case 'dynamic_quiz_dual':
        return Icons.quiz;
      case 'interactive':
        return Icons.touch_app;
      case 'jogeset':
        return Icons.gavel;
      case 'dialogus':
        return Icons.mic;
      case 'allomas':
        return Icons.route;
      default:
        return Icons.description;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'deck':
        return Colors.purple.shade700;
      case 'dynamic_quiz':
      case 'dynamic_quiz_dual':
        return Colors.orange.shade700;
      case 'interactive':
        return Colors.teal.shade700;
      case 'jogeset':
        return const Color(0xFF1E3A8A);
      case 'dialogus':
        return Colors.green.shade700;
      case 'allomas':
        return Colors.amber.shade700;
      default:
        return Colors.blue.shade700;
    }
  }

  Future<String?> _getAudioUrl(UserBundleItem item) async {
    if (item.originalCollection != 'dialogus_fajlok') return null;
    final doc = await FirebaseConfig.firestore
        .collection(item.originalCollection)
        .doc(item.originalId)
        .get();
    return doc.data()?['audioUrl'] as String?;
  }

  Future<void> _navigateToItem(UserBundleItem item) async {
    // Ellenőrizzük, hogy az eredeti dokumentum létezik-e
    final exists = await UserBundleService.checkOriginalExists(item);

    if (!exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Ez az elem már nem elérhető. Eltávolítva a kötegből.')),
        );
        // Lazy cleanup
        await UserBundleService.cleanupInvalidItem(
          bundleId: widget.bundleId,
          item: item,
        );
        setState(() {
          _items.remove(item);
        });
        // Frissítjük a bundle-t is
        final updatedBundle =
            await UserBundleService.getBundle(widget.bundleId);
        if (updatedBundle != null) {
          setState(() => _bundle = updatedBundle);
        }
      }
      return;
    }

    // FilterStorage beállítása a visszanavigáláshoz
    FilterStorage.science = item.science;
    FilterStorage.category = item.category;
    FilterStorage.tag = item.tags.isNotEmpty ? item.tags.first : null;

    if (!mounted) return;

    final from = 'bundle&bundleId=${widget.bundleId}';

    switch (item.type) {
      case 'dynamic_quiz':
      case 'dynamic_quiz_dual':
        context.go('/quiz/${item.originalId}?from=$from');
        break;
      case 'deck':
        context.go('/deck/${item.originalId}/view?from=$from');
        break;
      case 'interactive':
        context.go('/interactive-note/${item.originalId}?from=$from');
        break;
      case 'jogeset':
        context.go('/jogeset/${item.originalId}?from=$from');
        break;
      case 'allomas':
        context.go('/memoriapalota-allomas/${item.originalId}?from=$from');
        break;
      default:
        context.go('/note/${item.originalId}?from=$from');
    }
  }
}
