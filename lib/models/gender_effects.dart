import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../ui/widgets/filter_selector.dart';

/// Gender type enum for effect filtering
enum EffectGender { male, female, both, unknown }

/// Service for dynamically loading gender-specific effects from synced assets
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
  String? _syncedAssetsPath;

  /// Reset the service to allow re-initialization (call before initialize to force refresh)
  void reset() {
    _isInitialized = false;
    _maleEffects = [];
    _femaleEffects = [];
    _bothEffects = [];
    _syncedAssetsPath = null;
    debugPrint('🔄 GenderEffectsService reset');
  }

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

  /// Initialize the service - loads effects from BOTH bundled AND synced assets
  /// [assetFolderName]: The folder name where synced assets are stored (e.g., 'morphy_assets')
  Future<void> initialize({String? assetFolderName}) async {
    if (_isInitialized) return;

    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🎭 GENDER EFFECTS SERVICE INITIALIZING');
      debugPrint('═══════════════════════════════════════════');

      // STEP 1: Always load bundled assets first (they're already in the app)
      debugPrint('📦 Loading bundled assets...');
      await _loadFromBundledAssets();
      
      final bundledMale = _maleEffects.length;
      final bundledFemale = _femaleEffects.length;
      final bundledBoth = _bothEffects.length;
      debugPrint('  Bundled: $bundledMale male, $bundledFemale female, $bundledBoth both');

      // STEP 2: Load additional synced assets (downloaded from GitHub)
      if (assetFolderName != null) {
        final baseDir = await getApplicationDocumentsDirectory();
        final syncedDir = Directory('${baseDir.path}/$assetFolderName');

        debugPrint('📥 Checking synced folder: ${syncedDir.path}');
        debugPrint('   Exists: ${await syncedDir.exists()}');
        
        // List contents
        if (await syncedDir.exists()) {
          final contents = syncedDir.listSync();
          debugPrint('   Contents: ${contents.length} items');
          for (final item in contents) {
            debugPrint('     - ${item.path}');
          }
        }

        if (await syncedDir.exists()) {
          _syncedAssetsPath = syncedDir.path;

          // Load synced effects and MERGE with bundled (avoiding duplicates)
          final syncedMale = await _loadEffectsFromDirectory('$_syncedAssetsPath/male', 'male');
          final syncedFemale = await _loadEffectsFromDirectory('$_syncedAssetsPath/female', 'female');
          final syncedBoth = await _loadEffectsFromDirectory('$_syncedAssetsPath/both', 'both');

          debugPrint('  Synced: ${syncedMale.length} male, ${syncedFemale.length} female, ${syncedBoth.length} both');

          // Merge: Add synced effects that aren't already in bundled
          _mergeEffects(_maleEffects, syncedMale);
          _mergeEffects(_femaleEffects, syncedFemale);
          _mergeEffects(_bothEffects, syncedBoth);
        } else {
          debugPrint('  Synced folder does not exist yet');
        }
      }

      _isInitialized = true;
      
      debugPrint('═══════════════════════════════════════════');
      debugPrint('✅ EFFECTS LOADED');
      debugPrint('  Total male: ${_maleEffects.length}');
      debugPrint('  Total female: ${_femaleEffects.length}');
      debugPrint('  Total both: ${_bothEffects.length}');
      debugPrint('═══════════════════════════════════════════');
    } catch (e) {
      debugPrint('❌ Error initializing GenderEffectsService: $e');
      _isInitialized = true;
    }
  }

  /// Merge synced effects into existing list, avoiding duplicates by ID
  void _mergeEffects(List<FilterItem> existing, List<FilterItem> toAdd) {
    final existingIds = existing.map((e) => e.id).toSet();
    for (final effect in toAdd) {
      if (!existingIds.contains(effect.id)) {
        existing.add(effect);
        debugPrint('  + Added synced effect: ${effect.name}');
      }
    }
  }

  /// Load effects from a directory (synced assets)
  Future<List<FilterItem>> _loadEffectsFromDirectory(
    String dirPath,
    String folder,
  ) async {
    final List<FilterItem> effects = [];
    final dir = Directory(dirPath);

    debugPrint('📂 Loading synced effects from: $dirPath');
    debugPrint('   Directory exists: ${await dir.exists()}');

    if (!await dir.exists()) {
      debugPrint('   ⚠️ Directory does not exist, returning empty list');
      return effects;
    }

    int colorIndex = 0;
    final entities = dir.listSync();
    debugPrint('   Found ${entities.length} entities');

    for (final entity in entities) {
      debugPrint('   Checking: ${entity.path}');
      debugPrint('      Is File: ${entity is File}');
      debugPrint('      Ends with .deepar: ${entity.path.endsWith('.deepar')}');
      if (entity is File && entity.path.endsWith('.deepar')) {
        final fileName = entity.uri.pathSegments.last;
        final effectName = _formatEffectName(fileName);
        final effectId = fileName
            .replaceAll('.deepar', '')
            .toLowerCase()
            .replaceAll(' ', '_');

        // Verify file size (small files might be LFS pointers or corrupted)
        final fileSize = await entity.length();
        debugPrint('      ✓ Adding synced effect: $effectName (id: $effectId)');
        debugPrint('        Full path: ${entity.path}');
        debugPrint('        File size: $fileSize bytes');
        
        if (fileSize < 1000) {
          debugPrint('        ⚠️ WARNING: File very small, might be invalid!');
          // Skip invalid files
          continue;
        }

        // Store the FULL ABSOLUTE PATH for synced effects
        effects.add(
          FilterItem(
            id: effectId,
            name: effectName,
            colors: _colorPalettes[colorIndex % _colorPalettes.length],
            effectFile: entity.path, // Full absolute path
          ),
        );
        colorIndex++;
      }
    }

    debugPrint('   📂 Loaded ${effects.length} effects from $folder');
    return effects;
  }

  /// Load effects from bundled Flutter assets
  Future<void> _loadFromBundledAssets() async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final allAssets = assetManifest.listAssets();

    debugPrint('  Found ${allAssets.length} total bundled assets');
    
    // Debug: show all .deepar assets found
    final deeparAssets = allAssets.where((a) => a.endsWith('.deepar')).toList();
    debugPrint('  Found ${deeparAssets.length} .deepar files:');
    for (final asset in deeparAssets) {
      debugPrint('    - $asset');
    }

    _maleEffects = _loadEffectsFromAssetList(allAssets, 'male');
    _femaleEffects = _loadEffectsFromAssetList(allAssets, 'female');
    _bothEffects = _loadEffectsFromAssetList(allAssets, 'both');
  }

  /// Load effects from asset list for a specific folder (bundled assets)
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

        // For bundled assets, store relative path (folder/filename)
        effects.add(
          FilterItem(
            id: effectId,
            name: effectName,
            colors: _colorPalettes[colorIndex % _colorPalettes.length],
            effectFile: '$folder/$fileName',
          ),
        );

        debugPrint('  Found bundled effect: $folder/$fileName');
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
  /// Before gender is detected, show only gender-neutral "both" filters
  List<FilterItem> getUnknownGenderFilters() {
    return [defaultFilter, ..._bothEffects];
  }

  /// Get filters based on gender string from classification
  List<FilterItem> getFiltersForGender(String gender) {
    debugPrint('getFiltersForGender: $gender');
    switch (gender.toLowerCase()) {
      case 'male':
        debugPrint('  Returning ${getMaleFilters().length} male filters');
        return getMaleFilters();
      case 'female':
        debugPrint('  Returning ${getFemaleFilters().length} female filters');
        return getFemaleFilters();
      default:
        debugPrint('  Returning ${getUnknownGenderFilters().length} unknown filters');
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

  /// Check if using synced assets (vs bundled)
  bool get usingSyncedAssets => _syncedAssetsPath != null;
}
