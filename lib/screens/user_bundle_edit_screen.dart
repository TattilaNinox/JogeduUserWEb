import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../models/user_bundle.dart';
import '../models/user_bundle_item.dart';
import '../services/user_bundle_service.dart';

/// Köteg szerkesztő képernyő (Új architektúra: Subcollection alapú).
///
/// Új köteg létrehozása vagy meglévő szerkesztése.
class UserBundleEditScreen extends StatefulWidget {
  final String? bundleId;

  const UserBundleEditScreen({super.key, this.bundleId});

  @override
  State<UserBundleEditScreen> createState() => _UserBundleEditScreenState();
}

class _UserBundleEditScreenState extends State<UserBundleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _scrollController = ScrollController();

  UserBundle? _bundle;
  final List<UserBundleItem> _items = [];
  DocumentSnapshot? _lastDocument;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadBundle();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(UserBundleEditScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bundleId != widget.bundleId) {
      _loadBundle();
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreItems();
    }
  }

  Future<void> _loadBundle() async {
    if (widget.bundleId != null) {
      final bundle = await UserBundleService.getBundle(widget.bundleId!);
      if (bundle != null) {
        _nameController.text = bundle.name;
        _descriptionController.text = bundle.description;
        setState(() {
          _bundle = bundle;
        });
        await _loadItems();
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadItems() async {
    if (widget.bundleId == null) return;

    setState(() {
      _items.clear();
      _lastDocument = null;
      _hasMore = true;
    });
    await _loadMoreItems();
  }

  Future<void> _loadMoreItems() async {
    if (widget.bundleId == null || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final result = await UserBundleService.getItems(
        widget.bundleId!,
        lastDocument: _lastDocument,
        limit: 50,
      );

      setState(() {
        _items.addAll(result.items);
        _lastDocument = result.lastDoc;
        _hasMore = result.items.length == 50;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
      debugPrint('Hiba az elemek betöltésekor: $e');
    }
  }

  Future<void> _saveBundle() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (widget.bundleId == null) {
        // Új köteg létrehozása
        final bundleId = await UserBundleService.createBundle(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Köteg sikeresen létrehozva!')),
          );
          context.go('/my-bundles/edit/$bundleId');
        }
      } else {
        // Meglévő köteg frissítése
        final updatedBundle = _bundle!.copyWith(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          modifiedAt: DateTime.now(),
        );
        await UserBundleService.updateBundle(updatedBundle);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Köteg sikeresen frissítve!')),
          );
          context.go('/my-bundles');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba történt: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteBundle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Köteg törlése'),
        content: const Text(
            'Biztosan törölni szeretnéd ezt a köteget? Ez a művelet nem vonható vissza.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Mégse'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSaving = true);

      try {
        await UserBundleService.deleteBundle(widget.bundleId!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Köteg sikeresen törölve')),
          );
          context.go('/my-bundles');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hiba a törlés során: $e')),
          );
          setState(() => _isSaving = false);
        }
      }
    }
  }

  void _addDocuments(String type) {
    final bundleId = widget.bundleId ?? 'create';
    context.go('/my-bundles/edit/$bundleId/add-$type');
  }

  Future<void> _removeItem(UserBundleItem item) async {
    if (widget.bundleId == null) return;

    try {
      await UserBundleService.removeItemFromBundle(
        bundleId: widget.bundleId!,
        itemId: item.id,
        itemType: item.type,
      );

      setState(() {
        _items.remove(item);
        // Frissítjük a bundle számlálóit
        if (_bundle != null) {
          _bundle = _bundle!.decrementCounter(item.type);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba az elem törlésekor: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Betöltés...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.bundleId == null ? 'Új köteg' : 'Köteg szerkesztése'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/my-bundles'),
        ),
        actions: [
          if (widget.bundleId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _isSaving ? null : _deleteBundle,
              tooltip: 'Köteg törlése',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Alapadatok
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.edit_note,
                                color: Theme.of(context).primaryColor),
                            const SizedBox(width: 12),
                            const Text(
                              'Alapadatok',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Köteg neve',
                            hintText: 'Pl. Polgári jog vizsga',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'A név megadása kötelező';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: InputDecoration(
                            labelText: 'Leírás (opcionális)',
                            hintText: 'Rövid leírás a kötegről',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Dokumentum szekciók
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    _buildDocumentSection(
                      title: 'Tanulókártyák és kvíz kérdések',
                      icon: Icons.school,
                      count: _bundle?.noteCount ?? 0,
                      type: 'notes',
                      isMobile: isMobile,
                    ),
                    const SizedBox(height: 12),
                    _buildDocumentSection(
                      title: 'Memória útvonalak',
                      icon: Icons.route,
                      count: _bundle?.allomasCount ?? 0,
                      type: 'allomasok',
                      isMobile: isMobile,
                    ),
                    const SizedBox(height: 12),
                    _buildDocumentSection(
                      title: 'Dialógusok',
                      icon: Icons.headset,
                      count: _bundle?.dialogusCount ?? 0,
                      type: 'dialogus',
                      isMobile: isMobile,
                    ),
                    const SizedBox(height: 12),
                    _buildDocumentSection(
                      title: 'Jogesetek',
                      icon: Icons.gavel,
                      count: _bundle?.jogesetCount ?? 0,
                      type: 'jogeset',
                      isMobile: isMobile,
                    ),
                  ],
                ),
              ),
            ),

            // Elemek listája
            if (_items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Elemek a kötegben (${_items.length})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ..._items.map((item) => _buildItemTile(item)),
                        if (_hasMore && _isLoadingMore)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // Mentés gomb
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: _isSaving ? null : _saveBundle,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(widget.bundleId == null
                                    ? 'Létrehozás'
                                    : 'Mentés'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _isSaving
                                ? null
                                : () => context.go('/my-bundles'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            child: const Text('Mégse'),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _isSaving
                                ? null
                                : () => context.go('/my-bundles'),
                            child: const Text('Mégse'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _isSaving ? null : _saveBundle,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(widget.bundleId == null
                                    ? 'Létrehozás'
                                    : 'Mentés'),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentSection({
    required String title,
    required IconData icon,
    required int count,
    required String type,
    required bool isMobile,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text('$count elem'),
        trailing: ElevatedButton.icon(
          onPressed: () => _addDocuments(type),
          icon: const Icon(Icons.add, size: 16),
          label: Text(isMobile ? '' : 'Hozzáadás'),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12, vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile(UserBundleItem item) {
    final iconData = _getIconForType(item.type);

    return ListTile(
      leading: Icon(iconData, color: Theme.of(context).primaryColor),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: item.science != null ? Text(item.science!) : null,
      trailing: IconButton(
        icon: Icon(Icons.close, color: Colors.grey.shade600, size: 18),
        onPressed: () => _removeItem(item),
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
}
