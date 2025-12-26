import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/sidebar.dart';
import '../widgets/header.dart';
import '../widgets/bundle_card_grid.dart';

/// Felhasználói kötegek lista képernyő.
///
/// Ugyanazt az elrendezést használja, mint a NoteListScreen:
/// - Sidebar bal oldalon
/// - Header felül keresővel
/// - BundleCardGrid a kötegek megjelenítésére
class UserBundleListScreen extends StatefulWidget {
  const UserBundleListScreen({super.key});

  @override
  State<UserBundleListScreen> createState() => _UserBundleListScreenState();
}

class _UserBundleListScreenState extends State<UserBundleListScreen> {
  String _searchText = '';

  void _onSearchChanged(String value) {
    setState(() {
      _searchText = value;
    });
  }

  void _createNewBundle() {
    context.go('/my-bundles/create');
  }

  Widget _buildContent({
    required bool showSidebar,
    required bool includeHeader,
  }) {
    return Row(
      children: [
        if (showSidebar) const Sidebar(selectedMenu: 'my-bundles'),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (includeHeader)
                Header(
                  onSearchChanged: _onSearchChanged,
                  showActions: true,
                ),
              // Új köteg gomb mobil nézetben
              if (!showSidebar)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: _createNewBundle,
                    icon: const Icon(Icons.add),
                    label: const Text('Új köteg'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
              Expanded(
                child: BundleCardGrid(searchText: _searchText),
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
          // Desktop: sidebar + header + grid
          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            body: _buildContent(
              showSidebar: true,
              includeHeader: true,
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _createNewBundle,
              icon: const Icon(Icons.add),
              label: const Text('Új köteg'),
              backgroundColor: Theme.of(context).primaryColor,
            ),
          );
        } else if (width >= 600) {
          // Tablet: header + grid (sidebar drawer-ben)
          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            drawer: const Drawer(
              child: Sidebar(selectedMenu: 'my-bundles'),
            ),
            body: _buildContent(
              showSidebar: false,
              includeHeader: true,
            ),
          );
        } else {
          // Mobil: csak grid, header drawer-ben
          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: AppBar(
              title: const Text('Saját kötegek'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    showSearch(
                      context: context,
                      delegate: _BundleSearchDelegate(
                        onSearchChanged: _onSearchChanged,
                      ),
                    );
                  },
                ),
              ],
            ),
            drawer: const Drawer(
              child: Sidebar(selectedMenu: 'my-bundles'),
            ),
            body: _buildContent(
              showSidebar: false,
              includeHeader: false,
            ),
          );
        }
      },
    );
  }
}

/// Keresés delegate mobil nézethez
class _BundleSearchDelegate extends SearchDelegate<String> {
  final Function(String) onSearchChanged;

  _BundleSearchDelegate({required this.onSearchChanged});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          onSearchChanged('');
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    onSearchChanged(query);
    close(context, query);
    return Container();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Container();
  }
}
