import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/deck_collection.dart';
import '../services/deck_collection_service.dart';
import '../widgets/sidebar.dart';

/// Gyűjtemények listája képernyő.
/// Megjeleníti az összes deck_collections dokumentumot szűrési lehetőséggel.
class DeckCollectionListScreen extends StatefulWidget {
  const DeckCollectionListScreen({super.key});

  @override
  State<DeckCollectionListScreen> createState() =>
      _DeckCollectionListScreenState();
}

class _DeckCollectionListScreenState extends State<DeckCollectionListScreen> {
  List<DeckCollection> _collections = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedCategory;

  // Lazy loading: statisztikák gyűjteményenként
  final Map<String, Map<String, int>> _collectionStats = {};
  final Set<String> _loadingStats = {};

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final collections = await DeckCollectionService.getCollections();
      if (mounted) {
        setState(() {
          _collections = collections;
          _isLoading = false;
        });

        // Lazy loading: statisztikák betöltése az első néhány elemhez
        _loadVisibleStats();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Statisztikák betöltése látható elemekhez (max 5 egyszerre)
  Future<void> _loadVisibleStats() async {
    final toLoad = _collections
        .where((c) =>
            !_collectionStats.containsKey(c.id) &&
            !_loadingStats.contains(c.id))
        .take(5)
        .toList();

    for (final collection in toLoad) {
      _loadStatsForCollection(collection.id);
    }
  }

  Future<void> _loadStatsForCollection(String collectionId) async {
    if (_loadingStats.contains(collectionId)) return;

    setState(() {
      _loadingStats.add(collectionId);
    });

    try {
      final stats =
          await DeckCollectionService.getCollectionStats(collectionId);
      if (mounted) {
        setState(() {
          _collectionStats[collectionId] = stats;
          _loadingStats.remove(collectionId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingStats.remove(collectionId);
        });
      }
    }
  }

  List<DeckCollection> get _filteredCollections {
    if (_selectedCategory == null) return _collections;
    return _collections.where((c) => c.category == _selectedCategory).toList();
  }

  Set<String> get _availableCategories {
    return _collections
        .map((c) => c.category)
        .where((c) => c != null)
        .cast<String>()
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 1200;

      final content = _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Hiba: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadCollections,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Újratöltés'),
                      ),
                    ],
                  ),
                )
              : _filteredCollections.isEmpty
                  ? const Center(
                      child: Text('Nincsenek gyűjtemények.'),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(isMobile ? 8 : 16),
                      itemCount: _filteredCollections.length,
                      itemBuilder: (context, index) {
                        final collection = _filteredCollections[index];
                        final stats = _collectionStats[collection.id];
                        final isLoadingStats =
                            _loadingStats.contains(collection.id);

                        // Lazy loading: ha még nincs statisztika, töltsd be
                        if (stats == null && !isLoadingStats) {
                          _loadStatsForCollection(collection.id);
                        }

                        return _buildCollectionCard(
                          collection,
                          stats,
                          isLoadingStats,
                          isMobile,
                        );
                      },
                    );

      if (isWide) {
        return Scaffold(
          appBar: _buildAppBar(isMobile),
          body: Row(
            children: [
              const Sidebar(selectedMenu: 'deck-collections'),
              Expanded(child: content),
            ],
          ),
        );
      }

      return Scaffold(
        appBar: _buildAppBar(isMobile),
        drawer: const Drawer(
          child: SafeArea(
            child: Sidebar(selectedMenu: 'deck-collections'),
          ),
        ),
        body: content,
      );
    });
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    return AppBar(
      title: Text(
        'Paklik',
        style: TextStyle(
          fontSize: isMobile ? 16 : 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Colors.white,
      elevation: 1,
      centerTitle: true,
      actions: [
        if (_availableCategories.isNotEmpty)
          PopupMenuButton<String?>(
            icon: Icon(
              Icons.filter_list,
              color: _selectedCategory != null
                  ? const Color(0xFF1E3A8A)
                  : Colors.grey,
            ),
            tooltip: 'Szűrés kategória szerint',
            onSelected: (value) {
              setState(() {
                _selectedCategory = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(
                value: null,
                child: Text('Összes kategória'),
              ),
              const PopupMenuDivider(),
              ..._availableCategories.map(
                (category) => PopupMenuItem<String?>(
                  value: category,
                  child: Text(category),
                ),
              ),
            ],
          ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Color(0xFF1E3A8A)),
          tooltip: 'Frissítés',
          onPressed: () {
            DeckCollectionService.clearAllCaches();
            _collectionStats.clear();
            _loadCollections();
          },
        ),
      ],
    );
  }

  Widget _buildCollectionCard(
    DeckCollection collection,
    Map<String, int>? stats,
    bool isLoadingStats,
    bool isMobile,
  ) {
    return Card(
      margin: EdgeInsets.only(bottom: isMobile ? 8 : 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          context.go('/deck-collections/${collection.id}');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder_special,
                      color: Color(0xFF1E3A8A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collection.title,
                          style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (collection.category != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  collection.category!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              '${collection.deckCount} pakli',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              // Statisztikák
              if (isLoadingStats)
                const SizedBox(
                  height: 24,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (stats != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatChip(
                      'Esedékes',
                      stats['due'] ?? 0,
                      Colors.orange,
                    ),
                    _buildStatChip(
                      'Új',
                      stats['new'] ?? 0,
                      Colors.blue,
                    ),
                    _buildStatChip(
                      'Tanulás alatt',
                      stats['learning'] ?? 0,
                      Colors.purple,
                    ),
                    _buildStatChip(
                      'Átnézett',
                      stats['review'] ?? 0,
                      Colors.green,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
