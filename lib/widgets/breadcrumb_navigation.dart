import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/filter_storage.dart';

/// Breadcrumb navigációs widget, amely megjeleníti a navigációs hierarchiát
/// és lehetővé teszi a visszalépést bármely szintre.
///
/// A breadcrumb a jegyzet aktuális kategóriáját és címkéjét mutatja.
/// Amikor rákattintanak a kategóriára vagy címkére, akkor az adott kategóriára/címkére szűrt listára navigálnak.
class BreadcrumbNavigation extends StatelessWidget {
  final String? category; // Jegyzet aktuális kategóriája
  final String? tag; // Jegyzet aktuális címkéje
  final String? noteTitle;
  final String? noteId;

  const BreadcrumbNavigation({
    super.key,
    this.category,
    this.tag,
    this.noteTitle,
    this.noteId,
  });

  /// Navigál az adott szintre (kategória vagy címke alapján)
  /// Amikor rákattintanak a kategóriára vagy címkére, akkor az adott kategóriára/címkére szűrt listára navigálnak
  void _navigateToLevel(
    BuildContext context, {
    String? category,
    String? tag,
  }) {
    debugPrint('🔵 Breadcrumb navigáció: category=$category, tag=$tag');

    final queryParams = <String, String>{};

    // Kategória - csak akkor adjuk hozzá, ha van megadva
    if (category != null && category.isNotEmpty) {
      queryParams['category'] = category;
    }

    // Címke - csak akkor adjuk hozzá, ha van megadva
    if (tag != null && tag.isNotEmpty) {
      queryParams['tag'] = tag;
      debugPrint('🔵 Breadcrumb: tag hozzáadva: $tag');
    }

    // Tudomány - megőrizzük, ha van
    if (FilterStorage.science != null && FilterStorage.science!.isNotEmpty) {
      queryParams['science'] = FilterStorage.science!;
    }

    final uri = Uri(
      path: '/notes',
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    debugPrint('🔵 Breadcrumb navigáció URL: ${uri.toString()}');
    context.go(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final List<BreadcrumbItem> items = [];

    // Főoldal
    items.add(BreadcrumbItem(
      label: 'Főoldal',
      onTap: () => _navigateToLevel(context),
      isActive: noteTitle == null,
    ));

    // Kategória és címke változók előre deklarálása
    final effectiveCategory = category;
    final effectiveTag = tag;

    // Kategória (ha van) - a jegyzet aktuális kategóriáját mutatjuk
    if (effectiveCategory != null && effectiveCategory.isNotEmpty) {
      items.add(BreadcrumbItem(
        label: effectiveCategory,
        onTap: () => _navigateToLevel(context, category: effectiveCategory),
        isActive:
            noteTitle != null && (effectiveTag == null || effectiveTag.isEmpty),
      ));
    }

    // Címke (ha van) - a jegyzet aktuális címkéjét mutatjuk
    if (effectiveTag != null && effectiveTag.isNotEmpty) {
      items.add(BreadcrumbItem(
        label: effectiveTag,
        onTap: () {
          // Címkére navigálás: megőrizzük a kategóriát is, ha van
          _navigateToLevel(
            context,
            category: effectiveCategory, // Megőrizzük a kategóriát is
            tag: effectiveTag,
          );
        },
        isActive: noteTitle != null,
      ));
    }

    // Jegyzet cím (ha van)
    if (noteTitle != null && noteTitle!.isNotEmpty) {
      items.add(BreadcrumbItem(
        label: noteTitle!,
        onTap: null, // Aktuális oldal, nem kattintható
        isActive: true,
      ));
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.home,
            size: isMobile ? 16 : 18,
            color: Colors.grey.shade600,
          ),
          SizedBox(width: isMobile ? 4 : 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index > 0) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 4 : 8,
                          ),
                          child: Icon(
                            Icons.chevron_right,
                            size: isMobile ? 16 : 18,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                      GestureDetector(
                        onTap: item.onTap,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 6 : 8,
                            vertical: isMobile ? 2 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: item.isActive
                                ? Theme.of(context)
                                    .primaryColor
                                    .withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 14,
                              fontWeight: item.isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: item.onTap != null
                                  ? (item.isActive
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey.shade700)
                                  : Colors.grey.shade600,
                              decoration: item.onTap != null
                                  ? null
                                  : TextDecoration.none,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BreadcrumbItem {
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  BreadcrumbItem({
    required this.label,
    this.onTap,
    this.isActive = false,
  });
}
