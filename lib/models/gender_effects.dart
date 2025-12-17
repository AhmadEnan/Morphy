import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/widgets/filter_selector.dart';

/// Gender type enum for effect filtering
enum EffectGender { male, female, both, unknown }

/// Service for dynamically loading gender-specific effects from assets
class GenderEffectsService {
  static GenderEffectsService? _instance;
  static GenderEffectsService get instance =>
      _instance ??= GenderEffectsService._();

  GenderEffectsService._();

  /// Loaded effect lists
  List<FilterItem> _maleEffects = [];
  List<FilterItem> _femaleEffects = [];
  List<FilterItem> _bothEffects = [];

  bool _isInitialized = false;

  /// Default "no effect" filter item
  static const FilterItem defaultFilter = FilterItem(
    id: 'original',
    name: 'Original',
    colors: [Color(0xFF333333), Color(0xFF555555)],
    effectFile: 'none',
  );

  /// Predefined color palettes for auto-generated filters
  static const List<List<Color>> _colorPalettes = [
    [Color(0xFFFF6B9D), Color(0xFFC44569)], // Pink
    [Color(0xFF8B4513), Color(0xFFCD853F)], // Brown
    [Color(0xFFD4A373), Color(0xFFE9EDC9)], // Beige
    [Color(0xFFFF69B4), Color(0xFFFFB6C1)], // Light Pink
    [Color(0xFFFF4500), Color(0xFFFF6347)], // Orange-Red
    [Color(0xFF00F5D4), Color(0xFFF15BB5)], // Cyan-Magenta
    [Color(0xFF2D3142), Color(0xFF4F5D75)], // Dark Blue-Gray
    [Color(0xFFFFD700), Color(0xFFB8860B)], // Gold
    [Color(0xFF808080), Color(0xFFA9A9A9)], // Gray
    [Color(0xFF8B7355), Color(0xFFD2B48C)], // Tan
    [Color(0xFF1A1A1A), Color(0xFF8B0000)], // Black-Red
    [Color(0xFFFF6600), Color(0xFFFFCC00)], // Orange-Yellow
    [Color(0xFFFF1493), Color(0xFFFF69B4)], // Deep Pink
    [Color(0xFF00CED1), Color(0xFF20B2AA)], // Teal
    [Color(0xFF9370DB), Color(0xFF00CED1)], // Purple-Cyan
    [Color(0xFF191970), Color(0xFF4B0082)], // Navy-Indigo
    [Color(0xFF32CD32), Color(0xFF228B22)], // Green
    [Color(0xFF4169E1), Color(0xFF1E90FF)], // Royal Blue
  ];

  /// Initialize the service - loads effects from asset folders
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load effects from each folder using the new AssetManifest API
      final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = assetManifest.listAssets();

      debugPrint(
        'GenderEffectsService: Found ${allAssets.length} total assets',
      );

      // Filter and load effects from each folder
      _maleEffects = _loadEffectsFromAssetList(allAssets, 'male');
      _femaleEffects = _loadEffectsFromAssetList(allAssets, 'female');
      _bothEffects = _loadEffectsFromAssetList(allAssets, 'both');

      _isInitialized = true;
      debugPrint('GenderEffectsService initialized:');
      debugPrint('  Male effects: ${_maleEffects.length}');
      debugPrint('  Female effects: ${_femaleEffects.length}');
      debugPrint('  Both effects: ${_bothEffects.length}');
    } catch (e) {
      debugPrint('Error initializing GenderEffectsService: $e');
      _isInitialized =
          true; // Mark as initialized even on error to prevent retries
    }
  }

  /// Load effects from asset list for a specific folder
  List<FilterItem> _loadEffectsFromAssetList(
    List<String> allAssets,
    String folder,
  ) {
    final List<FilterItem> effects = [];
    final folderPath = 'assets/effects/$folder/';

    int colorIndex = 0;
    for (final assetPath in allAssets) {
      // Check if this asset is in our target folder and is a .deepar file
      if (assetPath.startsWith(folderPath) && assetPath.endsWith('.deepar')) {
        // Extract just the filename
        final fileName = assetPath.substring(folderPath.length);

        // Skip if it's in a subfolder (contains more path separators)
        if (fileName.contains('/')) continue;

        // Create a filter item for this effect
        final effectName = _formatEffectName(fileName);
        final effectId = fileName
            .replaceAll('.deepar', '')
            .toLowerCase()
            .replaceAll(' ', '_');

        effects.add(
          FilterItem(
            id: effectId,
            name: effectName,
            colors: _colorPalettes[colorIndex % _colorPalettes.length],
            effectFile: '$folder/$fileName',
          ),
        );

        debugPrint('  Found effect: $folder/$fileName');
        colorIndex++;
      }
    }

    return effects;
  }

  /// Format effect filename to display name
  String _formatEffectName(String fileName) {
    // Remove .deepar extension
    String name = fileName.replaceAll('.deepar', '');
    // Replace underscores with spaces
    name = name.replaceAll('_', ' ');
    // Capitalize each word
    name = name
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
    return name;
  }

  /// Get complete filter list for male users (default + male effects + both effects)
  List<FilterItem> getMaleFilters() {
    return [defaultFilter, ..._maleEffects, ..._bothEffects];
  }

  /// Get complete filter list for female users (default + female effects + both effects)
  List<FilterItem> getFemaleFilters() {
    return [defaultFilter, ..._femaleEffects, ..._bothEffects];
  }

  /// Get filters for unknown/undetected gender (default + both effects only)
  List<FilterItem> getUnknownGenderFilters() {
    return [defaultFilter, ..._bothEffects];
  }

  /// Get filters based on gender string from classification
  List<FilterItem> getFiltersForGender(String gender) {
    switch (gender.toLowerCase()) {
      case 'male':
        return getMaleFilters();
      case 'female':
        return getFemaleFilters();
      default:
        return getUnknownGenderFilters();
    }
  }

  /// Get filters based on EffectGender enum
  List<FilterItem> getFiltersForEffectGender(EffectGender gender) {
    switch (gender) {
      case EffectGender.male:
        return getMaleFilters();
      case EffectGender.female:
        return getFemaleFilters();
      case EffectGender.both:
      case EffectGender.unknown:
        return getUnknownGenderFilters();
    }
  }

  /// Get raw male-only effects (without default or both)
  List<FilterItem> get maleOnlyEffects => _maleEffects;

  /// Get raw female-only effects (without default or both)
  List<FilterItem> get femaleOnlyEffects => _femaleEffects;

  /// Get raw both effects (without default)
  List<FilterItem> get bothOnlyEffects => _bothEffects;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}
