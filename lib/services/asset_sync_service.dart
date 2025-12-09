import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class AssetSyncService {
  /// Syncs local files with a remote source (JSON manifest, GitHub folder, or specific file).
  ///
  /// [targetUrl]: The URL of the source (JSON manifest, GitHub file, or GitHub folder).
  /// [localFolderName]: The name of the local folder to sync (e.g., 'asset_test').
  ///
  /// Valid formats for [targetUrl]:
  /// - JSON Manifest: "https://myserver.com/manifest.json"
  /// - GitHub File (Blob): "https://github.com/user/repo/blob/main/image.png"
  /// - GitHub Folder: "https://github.com/user/repo/tree/main/assets"
  /// - Google Drive File/Manifest: "https://drive.google.com/file/d/.../view"
  Future<void> syncAssets({
    required String targetUrl,
    required String localFolderName,
  }) async {
    debugPrint('Starting sync for $localFolderName from $targetUrl...');

    // 1. Setup Local Directory
    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = Directory('/storage/emulated/0/Download');
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final localDir = Directory('${baseDir.path}/$localFolderName');

    // Ensure directory exists
    if (!await localDir.exists()) {
      try {
        await localDir.create(recursive: true);
      } catch (e) {
        debugPrint('Error creating dir: $e. Fallback to app docs.');
        final internalDir = await getApplicationDocumentsDirectory();
        await Directory(
          '${internalDir.path}/$localFolderName',
        ).create(recursive: true);
      }
    }

    // 2. Identify Source Type
    if (_isGitHubUrl(targetUrl)) {
      await _syncGitHubSource(targetUrl, localDir);
    } else {
      await _processGenericSource(targetUrl, localDir);
    }

    debugPrint('Asset sync completed for $localFolderName');
  }

  // --- GitHub Logic ---

  bool _isGitHubUrl(String url) {
    return url.contains('github.com') ||
        url.contains('raw.githubusercontent.com');
  }

  Future<void> _syncGitHubSource(String url, Directory localDir) async {
    // 0. Handle Raw Links directly
    if (url.contains('raw.githubusercontent.com')) {
      // Remove query parameters from filename (e.g. ?token=...)
      final fileName = url.split('/').last.split('?').first;
      debugPrint('Detected Raw GitHub link. Downloading: $fileName');
      await _downloadFile(url, File('${localDir.path}/$fileName'));
      return;
    }

    // 1. Direct File Handling (Blob)
    // Format: https://github.com/USER/REPO/blob/main/path/to/image.png
    if (url.contains('/blob/')) {
      // Use GitHub's own raw redirection by adding ?raw=true
      // This handles LFS and other complexities better than manual rewriting
      final cleanUrl = url.split('?').first;
      final rawUrl = '$cleanUrl?raw=true';
      // Decode filename to remove %20 etc, then remove query params
      final rawFileName = cleanUrl.split('/').last;
      final fileName = Uri.decodeComponent(rawFileName);

      debugPrint('Detected GitHub blob. Downloading via raw param: $fileName');
      debugPrint('Target Path: ${localDir.path}/$fileName');

      await _downloadFile(rawUrl, File('${localDir.path}/$fileName'));
      return;
    }

    // 2. Directory Handling (Tree or Root)
    // Parse URL: https://github.com/USER/REPO/tree/BRANCH/PATH...
    final uri = Uri.parse(url);
    final segments =
        uri.pathSegments; // [USER, REPO, tree/blob, BRANCH, ...PATH]

    if (segments.length < 2) return;

    final user = segments[0];
    final repo = segments[1];

    // Default to handling root if path missing, or extract path
    String? path;
    String? ref; // Branch name

    if (segments.length >= 4) {
      // segment[2] is 'tree'
      ref = segments[3];
      if (segments.length > 4) {
        path = segments.sublist(4).join('/');
      }
    }

    // API: GET /repos/:owner/:repo/contents/:path?ref=:ref
    String apiUrl =
        'https://api.github.com/repos/$user/$repo/contents/${path ?? ""}';
    if (ref != null) {
      apiUrl += '?ref=$ref';
    }

    debugPrint('Querying GitHub API: $apiUrl');
    final response = await http.get(Uri.parse(apiUrl));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data is List) {
        // It's a directory!
        await _processGitHubDirectory(data, localDir);
      } else if (data is Map && data['type'] == 'file') {
        // It's a single file (unlikely from contents API unless path is exact file)
        await _processGitHubFile(data, localDir);
      }
    } else {
      // Only log error, don't throw to avoid stopping if API limits are hit,
      // unless it's critical. But since we handled blob above, this is likely a structured error.
      debugPrint(
        'GitHub API failed: ${response.statusCode} - ${response.body}',
      );
      throw Exception('GitHub API Failed: ${response.statusCode}');
    }
  }

  Future<void> _processGitHubDirectory(
    List<dynamic> contents,
    Directory currentLocalDir,
  ) async {
    // 1. Collect remote file names for cleanup
    final Set<String> remoteNames = {};

    if (!await currentLocalDir.exists()) {
      await currentLocalDir.create(recursive: true);
    }

    for (var item in contents) {
      final String name = item['name'];
      final String type = item['type']; // 'file' or 'dir'
      final String? downloadUrl = item['download_url'];
      remoteNames.add(name);

      if (type == 'file' && downloadUrl != null) {
        final file = File('${currentLocalDir.path}/$name');
        if (!await file.exists()) {
          debugPrint('GitHub: Downloading $name...');
          await _downloadFile(downloadUrl, file);
          debugPrint('Success! Downloaded to: ${file.path}');
        } else {
          debugPrint('File exists: $name');
        }
      } else if (type == 'dir') {
        // Recursive sync for subfolders
        // API URL for subdir
        final String subdirUrl = item['url']; // This is the API url for the dir
        final Directory subdir = Directory('${currentLocalDir.path}/$name');

        debugPrint('Entering subfolder: $name');
        final response = await http.get(Uri.parse(subdirUrl));
        if (response.statusCode == 200) {
          await _processGitHubDirectory(json.decode(response.body), subdir);
        }
      }
    }

    // Cleanup local files not in remote (only for this level)
    // Note: Be careful with recursive cleanup to not delete valid sub-sub things if API fails mid-way
    // For now, we only delete FILES in the current dir that are obsolete.
    if (await currentLocalDir.exists()) {
      final localEntities = currentLocalDir.listSync();
      for (var entity in localEntities) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (!remoteNames.contains(name)) {
            debugPrint('Deleting obsolete local file: $name');
            await entity.delete();
          }
        }
      }
    }
  }

  Future<void> _processGitHubFile(
    Map<dynamic, dynamic> item,
    Directory localDir,
  ) async {
    final String name = item['name'];
    final String? downloadUrl = item['download_url'];
    if (downloadUrl != null) {
      await _downloadFile(downloadUrl, File('${localDir.path}/$name'));
    }
  }

  // --- Original JSON Manifest Logic (Renamed) ---

  // --- Generic Source Logic (Manifest OR Single File) ---

  // Replaces _syncJsonManifest to handle any generic URL.
  // If the content is valid JSON with a "files" list, it's treated as a manifest.
  // Otherwise, it's treated as a direct file download.
  Future<void> _processGenericSource(String url, Directory localDir) async {
    // Detect & Convert Google Drive Links and GitHub Blobs (View -> Export/Raw)
    final directUrl = _convertToDirectDownloadUrl(url);
    debugPrint('Fetching content from generic source: $directUrl');

    // We fetch the response first to inspect it
    final response = await http
        .get(Uri.parse(directUrl))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch from generic source: ${response.statusCode}',
      );
    }

    // 1. Try to parse as JSON Manifest
    bool isManifest = false;
    Map<String, dynamic>? manifest;

    try {
      // Basic check: is header json? or text?
      final contentType = response.headers['content-type'] ?? '';

      // Heuristic: If it's explicitly binary/image, don't try JSON parse as it might be huge
      if (!contentType.contains('image/') && !contentType.contains('video/')) {
        String jsonString = response.body;
        // Clean up potential trailing commas
        jsonString = jsonString.replaceAll(RegExp(r',\s*]'), ']');
        jsonString = jsonString.replaceAll(RegExp(r',\s*}'), '}');

        final decoded = json.decode(jsonString);
        if (decoded is Map<String, dynamic> && decoded.containsKey('files')) {
          isManifest = true;
          manifest = decoded;
        }
      }
    } catch (_) {
      // Not a valid JSON manifest, proceed to single file logic
    }

    if (isManifest && manifest != null) {
      debugPrint('Detected Valid JSON Manifest. Syncing files...');
      await _syncManifestContent(manifest, localDir);
    } else {
      debugPrint('Not a manifest. Treating as single file download.');
      await _saveSingleFileResponse(response, directUrl, localDir);
    }
  }

  Future<void> _syncManifestContent(
    Map<String, dynamic> manifest,
    Directory localDir,
  ) async {
    final List<dynamic> fileList = manifest['files'] ?? [];
    final Set<String> serverFileNames = fileList
        .map((f) => f['name'].toString())
        .toSet();

    // Delete obsolete
    if (await localDir.exists()) {
      for (var entity in localDir.listSync()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (!serverFileNames.contains(name)) {
            await entity.delete();
          }
        }
      }
    }

    // Download
    for (var fileItem in fileList) {
      final String fileName = fileItem['name'];
      final String fileUrl = _convertToDirectDownloadUrl(fileItem['url']);
      final File localFile = File('${localDir.path}/$fileName');

      if (!await localFile.exists()) {
        debugPrint('Downloading $fileName...');
        await _downloadFile(fileUrl, localFile);
        debugPrint('Success! Downloaded to: ${localFile.path}');
      }
    }
  }

  Future<void> _saveSingleFileResponse(
    http.Response response,
    String sourceUrl,
    Directory localDir,
  ) async {
    String fileName =
        'downloaded_asset_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Try Content-Disposition
    final disposition = response.headers['content-disposition'];
    if (disposition != null) {
      // Look for filename="name" or filename=name
      final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
      if (match != null) {
        fileName = match.group(1)!;
      }
    } else {
      // 2. Try URL path (if not simple "uc" Google drive link)
      // Google Drive direct links usually end in /uc?export... so path is useless.
      // But normal URLs might be useful.
      final uri = Uri.parse(sourceUrl);
      if (uri.pathSegments.isNotEmpty &&
          !uri.host.contains('drive.google.com')) {
        fileName = uri.pathSegments.last;
      }
    }

    // Decode in case of URL encoding
    fileName = Uri.decodeComponent(fileName);
    debugPrint('Saving single file as: $fileName');

    final file = File('${localDir.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes);
  }

  // --- Shared Helpers ---

  Future<void> _downloadFile(String url, File targetFile) async {
    int redirectCount = 0;
    String currentUrl = url;

    while (redirectCount < 5) {
      final response = await http
          .get(Uri.parse(currentUrl))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await targetFile.writeAsBytes(response.bodyBytes);
        return;
      } else if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 307) {
        final newUrl = response.headers['location'];
        if (newUrl != null) {
          redirectCount++;
          currentUrl = newUrl;
          debugPrint('Redirecting to: $currentUrl');
          continue;
        }
      }

      throw Exception(
        'Failed to download file: $currentUrl (${response.statusCode})',
      );
    }
    throw Exception('Too many redirects');
  }

  String _convertToDirectDownloadUrl(String url) {
    final uri = Uri.parse(url);

    // 1. Google Drive
    if (uri.host.contains('drive.google.com') &&
        uri.pathSegments.contains('view')) {
      final idIndex = uri.pathSegments.indexOf('d') + 1;
      if (idIndex > 0 && idIndex < uri.pathSegments.length) {
        final id = uri.pathSegments[idIndex];
        return 'https://drive.google.com/uc?export=download&id=$id';
      }
    }

    // 2. GitHub Blobs (Auto-append ?raw=true)
    if (url.contains('github.com') && url.contains('/blob/')) {
      // Check if raw param is missing
      if (!url.contains('?raw=true') && !url.contains('&raw=true')) {
        return url.contains('?') ? '$url&raw=true' : '$url?raw=true';
      }
    }

    return url;
  }
}
