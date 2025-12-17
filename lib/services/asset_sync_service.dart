import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

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

  /// Merge two SyncResults
  SyncResult merge(SyncResult other) {
    return SyncResult(
      downloadedFiles: [...downloadedFiles, ...other.downloadedFiles],
      existingFiles: [...existingFiles, ...other.existingFiles],
      failedFiles: [...failedFiles, ...other.failedFiles],
      filesByCategory: {...filesByCategory, ...other.filesByCategory},
    );
  }
}

/// Callback for sync progress updates
typedef SyncProgressCallback =
    void Function(String status, double progress, String? currentFile);

/// Asset Sync Service - Syncs files from a GitHub folder to local storage
///
/// Supports Git LFS files - automatically detects LFS pointers and fetches
/// the actual binary files from GitHub's media server.
///
/// Usage:
/// ```dart
/// final result = await AssetSyncService().syncAssets(
///   targetUrl: 'https://github.com/user/repo/tree/main/effects',
///   localFolderName: 'my_assets',
/// );
/// ```
class AssetSyncService {
  // GitHub repo info extracted from URL (needed for LFS resolution)
  String? _owner;
  String? _repo;
  String? _branch;

  /// Syncs local files with a GitHub folder.
  ///
  /// [targetUrl]: GitHub folder URL (e.g., https://github.com/user/repo/tree/main/effects)
  /// [localFolderName]: The name of the local folder to sync to (e.g., 'morphy_assets')
  /// [onProgress]: Optional callback for progress updates.
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

    // Setup Local Directory
    final baseDir = await getApplicationDocumentsDirectory();
    final localDir = Directory('${baseDir.path}/$localFolderName');

    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    debugPrint('📁 Local directory: ${localDir.path}');

    // Debug: List existing files
    if (await localDir.exists()) {
      final existingEntities = localDir.listSync(recursive: true);
      debugPrint('📄 Existing files in local directory:');
      for (final e in existingEntities) {
        if (e is File) {
          final size = await e.length();
          debugPrint('   - ${e.path} ($size bytes)');
        } else if (e is Directory) {
          debugPrint('   📂 ${e.path}/');
        }
      }
    }

    // Sync from GitHub folder
    final result = await _syncGitHubFolder(targetUrl, localDir, onProgress);

    // Debug: List files after sync
    debugPrint('📄 Files AFTER sync:');
    if (await localDir.exists()) {
      final entities = localDir.listSync(recursive: true);
      for (final e in entities) {
        if (e is File) {
          final size = await e.length();
          debugPrint('   ✓ ${e.path} ($size bytes)');
        }
      }
    }

    debugPrint('═══════════════════════════════════════════');
    debugPrint('✅ SYNC COMPLETE');
    debugPrint('   Downloaded: ${result.downloadedFiles.length} files');
    debugPrint('   Already existed: ${result.existingFiles.length} files');
    debugPrint('   Failed: ${result.failedFiles.length} files');
    debugPrint('═══════════════════════════════════════════');

    return result;
  }

  /// Get the base directory path for assets
  static Future<String> getAssetsBasePath(String localFolderName) async {
    final baseDir = await getApplicationDocumentsDirectory();
    return '${baseDir.path}/$localFolderName';
  }

  /// Sync from a GitHub folder URL
  Future<SyncResult> _syncGitHubFolder(
    String url,
    Directory localDir,
    SyncProgressCallback? onProgress,
  ) async {
    // Parse GitHub URL: https://github.com/USER/REPO/tree/BRANCH/PATH
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;

    if (segments.length < 2) {
      debugPrint('❌ Invalid GitHub URL: $url');
      return SyncResult(failedFiles: ['Invalid URL']);
    }

    _owner = segments[0];
    _repo = segments[1];
    String? path;

    // Extract branch and path from URL
    if (segments.length >= 4 && segments[2] == 'tree') {
      _branch = segments[3];
      if (segments.length > 4) {
        path = segments.sublist(4).join('/');
      }
    } else {
      _branch = 'main'; // Default branch
    }

    debugPrint('📊 Parsed URL:');
    debugPrint('   Owner: $_owner, Repo: $_repo');
    debugPrint('   Branch: $_branch, Path: $path');

    // Query GitHub API
    String apiUrl =
        'https://api.github.com/repos/$_owner/$_repo/contents/${path ?? ""}';
    if (_branch != null) {
      apiUrl += '?ref=$_branch';
    }

    debugPrint('🔗 GitHub API: $apiUrl');
    onProgress?.call('Fetching file list...', 0.1, null);

    try {
      final response = await http
          .get(
            Uri.parse(apiUrl),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('❌ GitHub API error: ${response.statusCode}');
        debugPrint('   ${response.body}');
        return SyncResult(failedFiles: ['API Error: ${response.statusCode}']);
      }

      final data = json.decode(response.body);

      if (data is List) {
        // It's a directory - process it recursively
        return await _processDirectory(
          data,
          localDir,
          path ?? '',
          onProgress,
          0.1,
          1.0,
        );
      } else if (data is Map && data['type'] == 'file') {
        // Single file
        return await _downloadSingleFile(data, localDir, path ?? '');
      }

      return SyncResult();
    } catch (e) {
      debugPrint('❌ Sync error: $e');
      return SyncResult(failedFiles: ['Error: $e']);
    }
  }

  /// Process a GitHub directory recursively
  Future<SyncResult> _processDirectory(
    List<dynamic> contents,
    Directory localDir,
    String currentPath,
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

    // Separate files and directories
    final files = contents.where((item) => item['type'] == 'file').toList();
    final dirs = contents.where((item) => item['type'] == 'dir').toList();

    final totalItems = files.length + dirs.length;
    var processedItems = 0;

    // Process files first
    for (final item in files) {
      final String name = item['name'];
      final String? downloadUrl = item['download_url'];
      final String filePath = item['path'] ?? '$currentPath/$name';
      final int? size = item['size'];

      if (downloadUrl == null) continue;

      final file = File('${localDir.path}/$name');

      // Update progress
      processedItems++;
      final progress =
          progressStart +
          (processedItems / totalItems) * (progressEnd - progressStart);
      onProgress?.call('Checking $name...', progress, name);

      // Check if file exists and has actual content (not empty or stub)
      if (await file.exists()) {
        final existingSize = await file.length();
        // Consider file valid if it exists and has content (> 500 bytes to avoid stubs)
        if (existingSize > 500) {
          debugPrint('   ✓ Exists: $name ($existingSize bytes)');
          existing.add(name);
          continue;
        } else {
          debugPrint('   ⚠ File too small, re-downloading: $name ($existingSize bytes)');
        }
      }

      debugPrint('   ⬇ Downloading: $name');
      onProgress?.call('Downloading $name...', progress, name);

      try {
        await _downloadFileWithLfsSupport(downloadUrl, file, filePath);
        final newSize = await file.length();
        debugPrint('   ✓ Downloaded: $name ($newSize bytes)');
        downloaded.add(name);
      } catch (e) {
        debugPrint('   ✗ Failed: $name - $e');
        failed.add(name);
      }
    }

    // Process subdirectories recursively
    for (final item in dirs) {
      final String name = item['name'];
      final String subdirApiUrl = item['url'];
      final String subdirPath = item['path'] ?? '$currentPath/$name';
      final subdir = Directory('${localDir.path}/$name');

      debugPrint('📂 Entering: $name/');

      processedItems++;
      final progress =
          progressStart +
          (processedItems / totalItems) * (progressEnd - progressStart);
      onProgress?.call('Syncing $name/...', progress, name);

      try {
        final response = await http
            .get(
              Uri.parse(subdirApiUrl),
              headers: {'Accept': 'application/vnd.github.v3+json'},
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final subdirContents = json.decode(response.body) as List;
          final subdirResult = await _processDirectory(
            subdirContents,
            subdir,
            subdirPath,
            onProgress,
            progress,
            progressEnd,
          );

          // Merge results
          downloaded.addAll(
            subdirResult.downloadedFiles.map((f) => '$name/$f'),
          );
          existing.addAll(subdirResult.existingFiles.map((f) => '$name/$f'));
          failed.addAll(subdirResult.failedFiles.map((f) => '$name/$f'));
        }
      } catch (e) {
        debugPrint('   ✗ Failed to sync $name/: $e');
        failed.add('$name/');
      }
    }

    // Clean up obsolete local files
    final remoteNames = contents.map((item) => item['name'] as String).toSet();
    await _cleanupObsoleteFiles(localDir, remoteNames);

    return SyncResult(
      downloadedFiles: downloaded,
      existingFiles: existing,
      failedFiles: failed,
    );
  }

  /// Download a single file with Git LFS support
  Future<SyncResult> _downloadSingleFile(
    Map<dynamic, dynamic> item,
    Directory localDir,
    String filePath,
  ) async {
    final String name = item['name'];
    final String? downloadUrl = item['download_url'];

    if (downloadUrl == null) {
      return SyncResult(failedFiles: [name]);
    }

    final file = File('${localDir.path}/$name');

    // Check if file exists and has actual content (> 500 bytes)
    if (await file.exists()) {
      final existingSize = await file.length();
      if (existingSize > 500) {
        debugPrint('   ✓ Exists: $name ($existingSize bytes)');
        return SyncResult(existingFiles: [name]);
      }
    }

    try {
      await _downloadFileWithLfsSupport(downloadUrl, file, filePath);
      return SyncResult(downloadedFiles: [name]);
    } catch (e) {
      return SyncResult(failedFiles: [name]);
    }
  }

  /// Download a file, automatically handling Git LFS pointers
  Future<void> _downloadFileWithLfsSupport(
    String url,
    File targetFile,
    String repoPath,
  ) async {
    // First, download from raw URL
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }

    // Check if this is a Git LFS pointer file
    final content = response.body;
    if (_isLfsPointer(content)) {
      debugPrint('      🔗 Detected LFS pointer, fetching actual file...');
      await _downloadLfsFile(targetFile, repoPath);
    } else {
      // Regular file, save directly
      await targetFile.writeAsBytes(response.bodyBytes);
    }
  }

  /// Check if content is a Git LFS pointer file
  bool _isLfsPointer(String content) {
    // LFS pointer files start with "version https://git-lfs.github.com/spec/v1"
    // and contain "oid sha256:" and "size"
    return content.startsWith('version https://git-lfs.github.com/spec/v1') &&
        content.contains('oid sha256:') &&
        content.contains('size ');
  }

  /// Download the actual file from Git LFS
  Future<void> _downloadLfsFile(File targetFile, String repoPath) async {
    if (_owner == null || _repo == null || _branch == null) {
      throw Exception('Repository info not available for LFS download');
    }

    // GitHub serves LFS files through media.githubusercontent.com
    // URL format: https://media.githubusercontent.com/media/{owner}/{repo}/{branch}/{path}
    final lfsUrl =
        'https://media.githubusercontent.com/media/$_owner/$_repo/$_branch/$repoPath';

    debugPrint('      📥 LFS URL: $lfsUrl');

    final response = await http
        .get(Uri.parse(lfsUrl))
        .timeout(
          const Duration(seconds: 120), // LFS files can be large
        );

    if (response.statusCode == 200) {
      await targetFile.writeAsBytes(response.bodyBytes);
      debugPrint(
        '      ✓ LFS download complete (${response.bodyBytes.length} bytes)',
      );
    } else {
      throw Exception('LFS download failed: ${response.statusCode}');
    }
  }

  /// Remove local files that no longer exist in remote
  Future<void> _cleanupObsoleteFiles(
    Directory dir,
    Set<String> remoteNames,
  ) async {
    if (!await dir.exists()) return;

    final localEntities = dir.listSync();
    for (final entity in localEntities) {
      final name = entity.uri.pathSegments.last;
      // Skip hidden files like .gitkeep
      if (name.startsWith('.')) continue;

      if (!remoteNames.contains(name)) {
        debugPrint('   🗑 Removing obsolete: $name');
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          debugPrint('   ✗ Failed to delete: $name');
        }
      }
    }
  }
}
