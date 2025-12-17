import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../../models/gender_effects.dart';

/// Filter data model with DeepAR effect support
class FilterItem {
  final String id;
  final String name;
  final List<Color> colors;

  /// DeepAR effect filename (e.g., 'MakeupLook.deepar') or 'none' for no effect
  /// For gender-specific effects, includes folder: 'male/effect.deepar'
  final String effectFile;

  const FilterItem({
    required this.id,
    required this.name,
    required this.colors,
    this.effectFile = 'none',
  });
}

/// Instagram-style horizontal filter selector with snap-to-center
/// Now supports dynamic filter lists that can change based on detected gender
class FilterSelector extends StatefulWidget {
  final Function(FilterItem filter, int index)? onFilterChanged;
  final int initialIndex;

  /// Optional external filter list - if not provided, uses unknown gender filters
  final List<FilterItem>? filters;

  const FilterSelector({
    super.key,
    this.onFilterChanged,
    this.initialIndex = 0,
    this.filters,
  });

  @override
  State<FilterSelector> createState() => FilterSelectorState();
}

class FilterSelectorState extends State<FilterSelector> {
  late PageController _pageController;
  late int _selectedIndex;
  late List<FilterItem> _currentFilters;
  static const double _viewportFraction = 0.18;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _currentFilters =
        widget.filters ??
        GenderEffectsService.instance.getUnknownGenderFilters();

    // If no effects loaded yet, show at least the default
    if (_currentFilters.isEmpty) {
      _currentFilters = [GenderEffectsService.defaultFilter];
    }

    _pageController = PageController(
      viewportFraction: _viewportFraction,
      initialPage: _selectedIndex.clamp(0, _currentFilters.length - 1),
    );
  }

  @override
  void didUpdateWidget(FilterSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update filters if external list changed
    if (widget.filters != oldWidget.filters && widget.filters != null) {
      _updateFilters(widget.filters!);
    }
  }

  /// Update the filter list (called when gender changes)
  void updateFilters(List<FilterItem> newFilters) {
    _updateFilters(newFilters);
  }

  void _updateFilters(List<FilterItem> newFilters) {
    if (newFilters.isEmpty) return;

    setState(() {
      final currentEffectFile =
          _currentFilters.isNotEmpty && _selectedIndex < _currentFilters.length
          ? _currentFilters[_selectedIndex].effectFile
          : 'none';

      _currentFilters = newFilters;

      // Try to find the same effect in the new list
      int newIndex = newFilters.indexWhere(
        (f) => f.effectFile == currentEffectFile,
      );
      if (newIndex < 0) {
        newIndex = 0; // Default to first (Original) if not found
      }

      _selectedIndex = newIndex;
    });

    // Animate to the new position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _selectedIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (_selectedIndex != index && index < _currentFilters.length) {
      setState(() {
        _selectedIndex = index;
      });
      HapticFeedback.selectionClick();
      widget.onFilterChanged?.call(_currentFilters[index], index);
    }
  }

  /// Get current filter
  FilterItem get currentFilter => _selectedIndex < _currentFilters.length
      ? _currentFilters[_selectedIndex]
      : GenderEffectsService.defaultFilter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Scrollable filter list
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            physics: const BouncingScrollPhysics(),
            itemCount: _currentFilters.length,
            itemBuilder: (context, index) {
              return _FilterCircle(
                filter: _currentFilters[index],
                isSelected: index == _selectedIndex,
                onTap: () {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Individual filter circle widget with scale animation
class _FilterCircle extends StatelessWidget {
  final FilterItem filter;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterCircle({
    required this.filter,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: AnimatedScale(
          scale: isSelected ? 1.2 : 0.85,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isSelected ? 1.0 : 0.6,
            duration: const Duration(milliseconds: 200),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: filter.colors,
                    ),
                    border: Border.all(
                      color: AppColors.filterUnselected,
                      width: 1.5,
                    ),
                    boxShadow: null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  filter.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
