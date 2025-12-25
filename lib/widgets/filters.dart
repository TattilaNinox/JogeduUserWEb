import 'package:flutter/material.dart';

class Filters extends StatefulWidget {
  final List<String> categories;
  final List<String> sciences;
  final List<String> tags;
  final String? selectedStatus;
  final String? selectedCategory;
  final String? selectedTag;
  final String? selectedScience;
  final String? selectedType;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onScienceChanged;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<String?> onTypeChanged;
  final VoidCallback onClearFilters;
  final bool vertical;
  final bool showStatus;
  final bool showType;

  const Filters({
    super.key,
    required this.categories,
    required this.sciences,
    required this.tags,
    required this.selectedStatus,
    required this.selectedCategory,
    required this.selectedTag,
    required this.selectedScience,
    required this.selectedType,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onScienceChanged,
    required this.onTagChanged,
    required this.onTypeChanged,
    required this.onClearFilters,
    this.vertical = false,
    this.showStatus = false,
    this.showType = true,
  });

  @override
  State<Filters> createState() => _FiltersState();
}

class _FiltersState extends State<Filters> {
  String? _status;
  String? _category;
  String? _science;
  String? _tag;
  String? _type;

  static const _noteTypes = [
    'text',
    'interactive',
    'dynamic_quiz',
    'dynamic_quiz_dual',
    'deck',
    'source',
    'memoriapalota_allomasok'
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.selectedStatus;
    _category = widget.selectedCategory;
    _science = widget.selectedScience;
    _tag = widget.selectedTag;
    // Normalizáljuk az "MP" értéket "memoriapalota_allomasok"-ra
    _type = widget.selectedType == 'MP'
        ? 'memoriapalota_allomasok'
        : widget.selectedType;
  }

  @override
  void didUpdateWidget(covariant Filters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedStatus != oldWidget.selectedStatus) {
      _status = widget.selectedStatus;
    }
    if (widget.selectedCategory != oldWidget.selectedCategory) {
      _category = widget.selectedCategory;
    }
    if (widget.selectedScience != oldWidget.selectedScience) {
      _science = widget.selectedScience;
    }
    if (widget.selectedTag != oldWidget.selectedTag) {
      _tag = widget.selectedTag;
    }
    if (widget.selectedType != oldWidget.selectedType) {
      // Normalizáljuk az "MP" értéket "memoriapalota_allomasok"-ra
      _type = widget.selectedType == 'MP'
          ? 'memoriapalota_allomasok'
          : widget.selectedType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final outerPadding = widget.vertical
        ? const EdgeInsets.all(0.0)
        : const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
    final gap = widget.vertical
        ? const SizedBox(height: 16)
        : const SizedBox(width: 16);

    final List<Widget> children = [];
    void add(Widget w) {
      if (children.isNotEmpty) children.add(gap);
      children.add(w);
    }

    if (widget.showType) {
      add(_buildDropdown<String>(
        hint: 'Típus',
        value: _type,
        items: _noteTypes,
        onChanged: (v) {
          // Normalizáljuk az "MP" értéket "memoriapalota_allomasok"-ra
          final normalizedValue = v == 'MP' ? 'memoriapalota_allomasok' : v;
          setState(() => _type = normalizedValue);
          widget.onTypeChanged(normalizedValue);
        },
        isExpanded: widget.vertical,
      ));
    }

    if (widget.showStatus) {
      add(_buildDropdown<String>(
        hint: 'Státusz',
        value: _status,
        items: const ['Draft', 'Published', 'Archived'],
        onChanged: (v) {
          setState(() => _status = v);
          widget.onStatusChanged(v);
        },
        isExpanded: widget.vertical,
      ));
    }

    add(_buildDropdown<String>(
      hint: 'Kategória',
      value: _category,
      items: widget.categories,
      onChanged: (v) {
        setState(() => _category = v);
        widget.onCategoryChanged(v);
      },
      isExpanded: widget.vertical,
    ));

    // Tudomány szűrő - jelenleg csak "Jogász" elérhető
    add(_buildDropdown<String>(
      hint: 'Tudomány',
      value: _science,
      items: widget.sciences,
      onChanged: (v) {
        setState(() => _science = v);
        widget.onScienceChanged(v);
      },
      isExpanded: widget.vertical,
    ));

    add(_buildDropdown<String>(
      hint: 'Címke',
      value: _tag,
      items: widget.tags,
      onChanged: (v) {
        setState(() => _tag = v);
        widget.onTagChanged(v);
      },
      isExpanded: widget.vertical,
    ));

    add(TextButton(
      onPressed: () {
        setState(() {
          _status = null;
          _category = null;
          _tag = null;
          _type = null;
          // _science NEM törlődik, mert fix a felhasználó tudományára
        });
        widget.onClearFilters();
        widget.onTypeChanged(null);
        // widget.onScienceChanged(null); <- NEM hívjuk meg, hogy a tudomány megmaradjon
      },
      child: const Text(
        'Szűrők törlése',
        style: TextStyle(fontSize: 13),
      ),
    ));

    return Padding(
      padding: outerPadding,
      child: widget.vertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children)
          : Row(
              children: children.map((w) {
                if (w is SizedBox) return w;
                if (w is TextButton) return w;
                return Expanded(child: w);
              }).toList(),
            ),
    );
  }

  Widget _buildDropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    bool isExpanded = false,
  }) {
    // Crash-proof: ha a value nincs benne az items listában, akkor null-ra állítjuk,
    // különben a DropdownButtonFormField assertel és összeomlik.
    final T? effectiveValue =
        ((value != null && items.any((e) => e == value)) ? value : null) as T?;

    return Theme(
      data: Theme.of(context).copyWith(
        dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: WidgetStateProperty.all(Colors.white),
            elevation: WidgetStateProperty.all(8),
            shadowColor:
                WidgetStateProperty.all(Colors.black.withValues(alpha: 0.1)),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
            ),
            padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 4)),
          ),
        ),
      ),
      child: DropdownButtonFormField<T>(
        key: ValueKey('${hint}_${items.length}_${items.join(",")}'),
        initialValue: effectiveValue,
        decoration: InputDecoration(
          labelText: hint,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 1.5),
          ),
          labelStyle: const TextStyle(
            fontSize: 13,
            color: Color(0xFF6B7280),
          ),
        ),
        isExpanded: true,
        menuMaxHeight: 300,
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(8),
        selectedItemBuilder: (BuildContext context) {
          return items.map<Widget>((T item) {
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                item.toString(),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList();
        },
        items: items
            .map((e) => DropdownMenuItem<T>(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Text(
                      e.toString(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ))
            .toList(),
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF111827),
        ),
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: Color(0xFF6B7280),
          size: 20,
        ),
      ),
    );
  }
}
