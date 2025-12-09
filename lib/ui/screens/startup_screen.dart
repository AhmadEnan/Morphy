import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:morphy/services/asset_sync_service.dart';
import 'package:morphy/ui/screens/camera_screen.dart';

class StartupScreen extends StatefulWidget {
  final String manifestUrl;
  final String assetFolderName;
  final String videoOutputFolderName;

  const StartupScreen({
    super.key,
    required this.manifestUrl,
    required this.assetFolderName,
    required this.videoOutputFolderName,
  });

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  String _status = 'Initializing...';
  double? _progress; // Null means indeterminate
  bool _syncFailed = false;

  @override
  void initState() {
    super.initState();
    // Start the startup sequence after the first frame to ensure UI is visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAppSequence();
    });
  }

  Future<void> _startAppSequence() async {
    // 1. Request Permissions
    await _requestPermissions();

    // 2. Sync Assets
    await _syncAssets();

    // 3. Navigate to Main Screen
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CameraScreen(
            syncFailed: _syncFailed,
            videoOutputFolderName: widget.videoOutputFolderName,
          ),
        ),
      );
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _status = 'Checking permissions...';
    });

    // Request storage permissions
    // For Android 13+ (API 33+), we might need PHOTOS/VIDEOS instead of STORAGE,
    // but Manage External Storage is usually for broader access.
    // simpler approach:
    await [
      Permission.storage,
      Permission.manageExternalStorage, // For accessing Downloads if needed
      Permission.camera,
      Permission.microphone,
    ].request();

    // We strictly won't block if denied, we'll try to sync anyway
    // and let the service handle errors (fallback to app docs).
  }

  Future<void> _syncAssets() async {
    try {
      setState(() {
        _status = 'Syncing assets... \nThis may take a moment.';
      });
      await AssetSyncService().syncAssets(
        targetUrl: widget.manifestUrl,
        localFolderName: widget.assetFolderName,
      );

      setState(() {
        _status = 'Sync succeeded...\nYour morphs are up to date';
      });
    } catch (e) {
      debugPrint('Startup Asset Sync Failed: $e');
      _syncFailed = true;
      if (mounted) {
        setState(() {
          _status = 'Sync failed. Starting app on the current assets...';
        });
      }
    }
    // Give the user a brief moment to see the sync results message
    await Future.delayed(const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo or App Name could go here
              const Text(
                'Morphy',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 48),
              CircularProgressIndicator(
                value: _progress,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
