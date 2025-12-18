import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;

/// Result of a sync operation with details about downloaded files
class SyncResult {
  final List<String> downloadedFiles;
  final List<String> existingFiles;
  final List<String> failedFiles;
  final Map<String, List<String>> filesByCategory;

  SyncResult({
    this.downloadedFiles = const [],
    this.existingFiles = const [],
    this.failedFiles = const [],
    this.filesByCategory = const {},
  });

  int get totalFiles =>
      downloadedFiles.length + existingFiles.length + failedFiles.length;
  int get successCount => downloadedFiles.length + existingFiles.length;

  SyncResult merge(SyncResult other) {
    return SyncResult(
      downloadedFiles: [...downloadedFiles, ...other.downloadedFiles],
      existingFiles: [...existingFiles, ...other.existingFiles],
      failedFiles: [...failedFiles, ...other.failedFiles],
      filesByCategory: {...filesByCategory, ...other.filesByCategory},
    );
  }
}

typedef SyncProgressCallback =
    void Function(String status, double progress, String? currentFile);

/// Asset Sync Service - Syncs files from a GitHub folder to local storage
class AssetSyncService {
  String? _owner;
  String? _repo;
  String? _branch;
  String? _localBasePath;
  Set<String> _bundledAssetNames = {};

  /// Get list of bundled .deepar asset NAMES (not paths) from the APK
  Future<Set<String>> _getBundledAssetNames() async {
    final bundledNames = <String>{};
    try {
      // Use AssetManifest.loadFromAssetBundle (the correct modern API)
      final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = assetManifest.listAssets();
      
      debugPrint('📦 Scanning bundled assets in APK (${allAssets.length} total assets)...');
      for (final assetPath in allAssets) {
        if (assetPath.contains('assets/effects/') && assetPath.endsWith('.deepar')) {
          // Extract just the filename
          final fileName = assetPath.split('/').last;
          bundledNames.add(fileName);
          debugPrint('   📦 Bundled: $fileName (from $assetPath)');
        }
      }
      debugPrint('📦 Total bundled .deepar files: ${bundledNames.length}');
    } catch (e) {
      debugPrint('⚠️ Could not read asset manifest: $e');
    }
    
    // If manifest reading failed or returned nothing, the bundled check won't work
    // This is fine - we'll just download the files (they might already exist locally)
    if (bundledNames.isEmpty) {
      debugPrint('⚠️ No bundled assets found in manifest - bundled check disabled');
    }
    
    return bundledNames;
  }

  Future<SyncResult> syncAssets({
    required String targetUrl,
    required String localFolderName,
    SyncProgressCallback? onProgress,
  }) async {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('📦 ASSET SYNC STARTING');
    debugPrint('   URL: $targetUrl');
    debugPrint('   Local folder: $localFolderName');
    debugPrint('═══════════════════════════════════════════');

    onProgress?.call('Connecting to GitHub...', 0.0, null);

    final baseDir = await getApplicationDocumentsDirectory();
    final localDir = Directory('${baseDir.path}/$localFolderName');
    _localBasePath = localDir.path;

    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    debugPrint('📁 Local directory: ${localDir.path}');

    // Get list of bundled asset names (files already in the APK)
    _bundledAssetNames = await _getBundledAssetNames();
    debugPrint('📦 Found ${_bundledAssetNames.length} bundled assets in APK:');
    for (final name in _bundledAssetNames) {
      debugPrint('   📦 $name');
    }

    // List ALL existing .deepar files BEFORE sync
    final existingFiles = await _listAllDeeparFiles(localDir);
    debugPrint('📋 Found ${existingFiles.length} existing .deepar files:');
    for (final f in existingFiles) {
      debugPrint('   ✓ $f');
    }

    final result = await _syncGitHubFolder(
      targetUrl,
      localDir,
      existingFiles,
      onProgress,
    );

    debugPrint('═══════════════════════════════════════════');
    debugPrint('✅ SYNC COMPLETE');
    debugPrint('   Downloaded: ${result.downloadedFiles.length} files');
    debugPrint('   Already existed: ${result.existingFiles.length} files');
    debugPrint('   Failed: ${result.failedFiles.length} files');
    debugPrint('═══════════════════════════════════════════');

    return result;
  }

  /// List all .deepar files recursively
  Future<Set<String>> _listAllDeeparFiles(Directory dir) async {
    final files = <String>{};
    if (!await dir.exists()) return files;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.deepar')) {
        final size = await entity.length();
        if (size > 1000) {
          // Only count files > 1KB as valid
          files.add(entity.path);
        }
      }
    }
    return files;
  }

  static Future<String> getAssetsBasePath(String localFolderName) async {
    final baseDir = await getApplicationDocumentsDirectory();
    return '${baseDir.path}/$localFolderName';
  }

  Future<SyncResult> _syncGitHubFolder(
    String url,
    Directory localDir,
    Set<String> existingFiles,
    SyncProgressCallback? onProgress,
  ) async {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;

    if (segments.length < 2) {
      debugPrint('❌ Invalid GitHub URL: $url');
      return SyncResult(failedFiles: ['Invalid URL']);
    }

    _owner = segments[0];
    _repo = segments[1];
    String? path;

    if (segments.length >= 4 && segments[2] == 'tree') {
      _branch = segments[3];
      if (segments.length > 4) {
        path = segments.sublist(4).join('/');
      }
    } else {
      _branch = 'main';
    }

    debugPrint('📊 Parsed: Owner=$_owner, Repo=$_repo, Branch=$_branch, Path=$path');

    String apiUrl =
        'https://api.github.com/repos/$_owner/$_repo/contents/${path ?? ""}';
    if (_branch != null) {
      apiUrl += '?ref=$_branch';
    }

    debugPrint('🔗 GitHub API: $apiUrl');
    onProgress?.call('Fetching file list...', 0.1, null);

    try {
      final response = await http
          .get(Uri.parse(apiUrl), headers: {'Accept': 'application/vnd.github.v3+json'})
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('❌ GitHub API error: ${response.statusCode}');
        return SyncResult(failedFiles: ['API Error: ${response.statusCode}']);
      }

      final data = json.decode(response.body);

      if (data is List) {
        return await _processDirectory(
          data, localDir, path ?? '', existingFiles, onProgress, 0.1, 1.0,
        );
      }

      return SyncResult();
    } catch (e) {
      debugPrint('❌ Sync error: $e');
      return SyncResult(failedFiles: ['Error: $e']);
    }
  }

  Future<SyncResult> _processDirectory(
    List<dynamic> contents,
    Directory localDir,
    String currentPath,
    Set<String> existingFiles,
    SyncProgressCallback? onProgress,
    double progressStart,
    double progressEnd,
  ) async {
    final downloaded = <String>[];
    final existing = <String>[];
    final failed = <String>[];

    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    final files = contents.where((item) => item['type'] == 'file').toList();
    final dirs = contents.where((item) => item['type'] == 'dir').toList();

    final totalItems = files.length + dirs.length;
    var processedItems = 0;

    // Process files
    for (final item in files) {
      final String name = item['name'];
      final String? downloadUrl = item['download_url'];
      final String repoPath = item['path'] ?? '$currentPath/$name';

      if (downloadUrl == null) continue;

      // The FULL LOCAL PATH where this file should be
      final localFilePath = '${localDir.path}/$name';
      final file = File(localFilePath);

      processedItems++;
      final progress = progressStart +
          (processedItems / totalItems) * (progressEnd - progressStart);

      // CHECK 1: Is this file already bundled in the APK?
      final isBundled = _bundledAssetNames.contains(name);
      debugPrint('   Checking: $name');
      debugPrint('      Is bundled: $isBundled (bundledAssets has ${_bundledAssetNames.length} items)');
      
      if (isBundled) {
        debugPrint('   ✓ SKIP (bundled in APK): $name');
        existing.add(name);
        onProgress?.call('Bundled: $name', progress, name);
        continue;
      }

      // CHECK 2: Does this file already exist in our pre-scanned list?
      final fileExists = existingFiles.contains(localFilePath);
      
      debugPrint('   Checking: $name');
      debugPrint('      Local path: $localFilePath');
      debugPrint('      In existing set: $fileExists');

      if (fileExists) {
        debugPrint('   ✓ SKIP (already exists): $name');
        existing.add(name);
        onProgress?.call('Already have $name', progress, name);
        continue;
      }

      // Double-check by actually looking at the file
      if (await file.exists()) {
        final size = await file.length();
        if (size > 1000) {
          debugPrint('   ✓ SKIP (found on disk): $name ($size bytes)');
          existing.add(name);
          onProgress?.call('Already have $name', progress, name);
          continue;
        }
      }

      // Need to download
      debugPrint('   ⬇ DOWNLOADING: $name');
      debugPrint('      Download URL: $downloadUrl');
      debugPrint('      Repo path: $repoPath');
      debugPrint('      Local file: ${file.path}');
      onProgress?.call('Downloading $name...', progress, name);

      try {
        await _downloadFile(downloadUrl, file, repoPath);
        final newSize = await file.length();
        debugPrint('   ✓ Downloaded: $name ($newSize bytes)');
        
        // Verify the downloaded file
        if (newSize < 200) {
          debugPrint('   ⚠️ WARNING: File is very small, might be corrupted!');
          final content = await file.readAsString();
          debugPrint('   File content preview: ${content.substring(0, content.length.clamp(0, 100))}');
        }
        
        downloaded.add(name);
      } catch (e) {
        debugPrint('   ✗ Failed: $name - $e');
        failed.add(name);
      }
    }

    // Process subdirectories
    for (final item in dirs) {
      final String name = item['name'];
      final String subdirApiUrl = item['url'];
      final String subdirPath = item['path'] ?? '$currentPath/$name';
      final subdir = Directory('${localDir.path}/$name');

      debugPrint('📂 Entering: $name/');

      processedItems++;
      final progress = progressStart +
          (processedItems / totalItems) * (progressEnd - progressStart);
      onProgress?.call('Syncing $name/...', progress, name);

      try {
        final response = await http
            .get(Uri.parse(subdirApiUrl), headers: {'Accept': 'application/vnd.github.v3+json'})
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final subdirContents = json.decode(response.body) as List;
          final subdirResult = await _processDirectory(
            subdirContents, subdir, subdirPath, existingFiles, onProgress, progress, progressEnd,
          );

          downloaded.addAll(subdirResult.downloadedFiles.map((f) => '$name/$f'));
          existing.addAll(subdirResult.existingFiles.map((f) => '$name/$f'));
          failed.addAll(subdirResult.failedFiles.map((f) => '$name/$f'));
        }
      } catch (e) {
        debugPrint('   ✗ Failed to sync $name/: $e');
        failed.add('$name/');
      }
    }

    return SyncResult(
      downloadedFiles: downloaded,
      existingFiles: existing,
      failedFiles: failed,
    );
  }

  Future<void> _downloadFile(String url, File targetFile, String repoPath) async {
    final parentDir = targetFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }

    final content = response.body;
    if (_isLfsPointer(content)) {
      debugPrint('      🔗 LFS pointer detected, fetching actual file...');
      await _downloadLfsFile(targetFile, repoPath);
    } else {
      await targetFile.writeAsBytes(response.bodyBytes);
      debugPrint('      ✓ Saved: ${targetFile.path}');
    }
  }

  bool _isLfsPointer(String content) {
    return content.startsWith('version https://git-lfs.github.com/spec/v1') &&
        content.contains('oid sha256:') &&
        content.contains('size ');
  }

  Future<void> _downloadLfsFile(File targetFile, String repoPath) async {
    if (_owner == null || _repo == null || _branch == null) {
      throw Exception('Repository info not available for LFS download');
    }

    final parentDir = targetFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final lfsUrl =
        'https://media.githubusercontent.com/media/$_owner/$_repo/$_branch/$repoPath';

    debugPrint('      📥 LFS Download:');
    debugPrint('         Owner: $_owner');
    debugPrint('         Repo: $_repo');
    debugPrint('         Branch: $_branch');
    debugPrint('         RepoPath: $repoPath');
    debugPrint('         Full URL: $lfsUrl');

    final response = await http
        .get(Uri.parse(lfsUrl))
        .timeout(const Duration(seconds: 120));

    debugPrint('         Response status: ${response.statusCode}');
    debugPrint('         Response size: ${response.bodyBytes.length} bytes');

    if (response.statusCode == 200) {
      await targetFile.writeAsBytes(response.bodyBytes);
      debugPrint('      ✓ LFS saved: ${targetFile.path}');
      debugPrint('      ✓ Size: ${response.bodyBytes.length} bytes');
    } else {
      throw Exception('LFS download failed: ${response.statusCode}');
    }
  }
}
