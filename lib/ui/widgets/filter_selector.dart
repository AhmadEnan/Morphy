import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';

/// Filter data model with DeepAR effect support
class FilterItem {
  final String id;
  final String name;
  final List<Color> colors;

  /// DeepAR effect filename (e.g., 'MakeupLook.deepar') or 'none' for no effect
  final String effectFile;

  const FilterItem({
    required this.id,
    required this.name,
    required this.colors,
    this.effectFile = 'none',
  });
}

/// DeepAR filters from assets/effects folder
const List<FilterItem> sampleFilters = [
  FilterItem(
    id: 'original',
    name: 'Original',
    colors: [Color(0xFF333333), Color(0xFF555555)],
    effectFile: 'none',
  ),
  FilterItem(
    id: 'test',
    name: 'Test',
    colors: [Color(0xFF9370DB), Color(0xFF00CED1)],
    effectFile: 'test_euro_guy.deepar',
  ),
  FilterItem(
    id: 'makeup',
    name: 'Makeup',
    colors: [Color(0xFFFF6B9D), Color(0xFFC44569)],
    effectFile: 'MakeupLook.deepar',
  ),
  FilterItem(
    id: 'viking',
    name: 'Viking',
    colors: [Color(0xFF8B4513), Color(0xFFCD853F)],
    effectFile: 'viking_helmet.deepar',
  ),
  FilterItem(
    id: 'stallone',
    name: 'Stallone',
    colors: [Color(0xFFD4A373), Color(0xFFE9EDC9)],
    effectFile: 'Stallone.deepar',
  ),
  FilterItem(
    id: 'flower',
    name: 'Flower',
    colors: [Color(0xFFFF69B4), Color(0xFFFFB6C1)],
    effectFile: 'flower_face.deepar',
  ),
  FilterItem(
    id: 'fire',
    name: 'Fire',
    colors: [Color(0xFFFF4500), Color(0xFFFF6347)],
    effectFile: 'Fire_Effect.deepar',
  ),
  FilterItem(
    id: 'neon',
    name: 'Neon',
    colors: [Color(0xFF00F5D4), Color(0xFFF15BB5)],
    effectFile: 'Neon_Devil_Horns.deepar',
  ),
  FilterItem(
    id: 'humanoid',
    name: 'Humanoid',
    colors: [Color(0xFF2D3142), Color(0xFF4F5D75)],
    effectFile: 'Humanoid.deepar',
  ),
  FilterItem(
    id: 'hope',
    name: 'Hope',
    colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
    effectFile: 'Hope.deepar',
  ),
  FilterItem(
    id: 'elephant',
    name: 'Elephant',
    colors: [Color(0xFF808080), Color(0xFFA9A9A9)],
    effectFile: 'Elephant_Trunk.deepar',
  ),
  FilterItem(
    id: 'snail',
    name: 'Snail',
    colors: [Color(0xFF8B7355), Color(0xFFD2B48C)],
    effectFile: 'Snail.deepar',
  ),
  FilterItem(
    id: 'vendetta',
    name: 'Vendetta',
    colors: [Color(0xFF1A1A1A), Color(0xFF8B0000)],
    effectFile: 'Vendetta_Mask.deepar',
  ),
  FilterItem(
    id: 'pingpong',
    name: 'Ping Pong',
    colors: [Color(0xFFFF6600), Color(0xFFFFCC00)],
    effectFile: 'Ping_Pong.deepar',
  ),
  FilterItem(
    id: 'hearts',
    name: 'Hearts',
    colors: [Color(0xFFFF1493), Color(0xFFFF69B4)],
    effectFile: 'Pixel_Hearts.deepar',
  ),
  FilterItem(
    id: 'burning',
    name: 'Burning',
    colors: [Color(0xFFFF4500), Color(0xFF8B0000)],
    effectFile: 'burning_effect.deepar',
  ),
  FilterItem(
    id: 'emotions',
    name: 'Emotions',
    colors: [Color(0xFFFFD700), Color(0xFF32CD32)],
    effectFile: 'Emotions_Exaggerator.deepar',
  ),
  FilterItem(
    id: 'meter',
    name: 'Meter',
    colors: [Color(0xFF00CED1), Color(0xFF20B2AA)],
    effectFile: 'Emotion_Meter.deepar',
  ),
  FilterItem(
    id: 'split',
    name: 'Split View',
    colors: [Color(0xFF9370DB), Color(0xFF00CED1)],
    effectFile: 'Split_View_Look.deepar',
  ),
  FilterItem(
    id: 'galaxy',
    name: 'Galaxy',
    colors: [Color(0xFF191970), Color(0xFF4B0082)],
    effectFile: 'galaxy_background.deepar',
  ),
];

/// Instagram-style horizontal filter selector with snap-to-center
class FilterSelector extends StatefulWidget {
  final Function(FilterItem filter, int index)? onFilterChanged;
  final int initialIndex;

  const FilterSelector({
    super.key,
    this.onFilterChanged,
    this.initialIndex = 0,
  });

  @override
  State<FilterSelector> createState() => _FilterSelectorState();
}

class _FilterSelectorState extends State<FilterSelector> {
  late PageController _pageController;
  late int _selectedIndex;
  static const double _viewportFraction = 0.18;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pageController = PageController(
      viewportFraction: _viewportFraction,
      initialPage: _selectedIndex,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
      HapticFeedback.selectionClick();
      widget.onFilterChanged?.call(sampleFilters[index], index);
    }
  }

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
            itemCount: sampleFilters.length,
            itemBuilder: (context, index) {
              return _FilterCircle(
                filter: sampleFilters[index],
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
