import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/colors.dart';
import '../widgets/filter_selector.dart';
import '../widgets/capture_button.dart';
import '../widgets/flash_toggle.dart';
import '../widgets/gender_indicator.dart';
import '../widgets/intensity_slider.dart';

/// Main camera screen with full UI overlay
class CameraScreen extends StatefulWidget {
  final bool syncFailed;
  final String? videoOutputFolderName;

  const CameraScreen({
    super.key,
    this.syncFailed = false,
    this.videoOutputFolderName,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  // Current filter state
  int _selectedFilterIndex = 0;
  double _filterIntensity = 0.5;
  bool _isFlashOn = false;
  bool _isRecording = false;

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // For smooth switching
  final GlobalKey _camKey = GlobalKey();
  ui.Image? _lastFrame;

  @override
  void initState() {
    super.initState();
    _initializeCamera();

    if (widget.syncFailed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Use root ScaffoldMessenger to ensure visibility
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asset Synchronization Failed'),
            duration: Duration(seconds: 4), // 4 seconds
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Default to first camera (usually back)
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: true,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        await _controller!.initialize();

        // Start with flash off
        await _controller!.setFlashMode(FlashMode.off);

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Get current filter
  FilterItem get _currentFilter => sampleFilters[_selectedFilterIndex];

  void _onFilterChanged(FilterItem filter, int index) {
    setState(() {
      _selectedFilterIndex = index;
    });
    debugPrint('Filter changed to: ${filter.name}');
  }

  void _onIntensityChanged(double value) {
    setState(() {
      _filterIntensity = value;
    });
    debugPrint('Intensity: ${(value * 100).toInt()}%');
  }

  Future<void> _onFlashChanged(bool isOn) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _controller!.setFlashMode(isOn ? FlashMode.torch : FlashMode.off);
      setState(() {
        _isFlashOn = isOn;
      });
      debugPrint('Flash: ${isOn ? "ON" : "OFF"}');
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  void _onCapture() {
    debugPrint('📸 Photo captured!');
    // TODO: Implement photo capture
  }

  Future<void> _onRecordingStart() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isRecordingVideo) return;

    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
      });
      debugPrint('🔴 Recording started');
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _onRecordingStop() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) return;

    try {
      setState(() {
        _isRecording = false;
      });

      final XFile videoFile = await _controller!.stopVideoRecording();
      debugPrint('⏹️ Recording stopped');

      await _saveVideoFile(videoFile);
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  Future<void> _saveVideoFile(XFile sourceFile) async {
    final String folderName =
        widget.videoOutputFolderName ?? 'morphy_recordings';
    Directory? baseDir;

    // Determine saving directory
    if (Platform.isAndroid) {
      // Try Movies first, then Download
      baseDir = Directory('/storage/emulated/0/Movies');
      if (!await baseDir.exists()) {
        baseDir = Directory('/storage/emulated/0/Download');
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final Directory finalDir;
    Directory tempDir = Directory('${baseDir.path}/$folderName');

    bool dirExists = false;
    try {
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      dirExists = true;
    } catch (e) {
      debugPrint('Error creating public recording dir: $e');
    }

    if (dirExists) {
      finalDir = tempDir;
    } else {
      final internalDir = await getApplicationDocumentsDirectory();
      finalDir = Directory('${internalDir.path}/$folderName');
      if (!await finalDir.exists()) {
        await finalDir.create(recursive: true);
      }
    }

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String fileName = 'MORPH_$timestamp.mp4';
    final String filePath = '${finalDir.path}/$fileName';

    try {
      await sourceFile.saveTo(filePath);
      debugPrint('Video saved to: $filePath');

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved video to $fileName'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving video file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background: Camera preview placeholder
          _buildCameraPreview(),

          // Gradient overlay for better UI visibility
          _buildGradientOverlay(),

          // UI Overlays
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                _buildTopBar(),

                // Spacer to push everything down
                const Spacer(),

                // Bottom Controls (Stack for overlapping elements)
                _buildBottomControls(),
              ],
            ),
          ),

          // Recording indicator
          if (_isRecording) _buildRecordingIndicator(),
        ],
      ),
    );
  }

  Future<void> _captureLastFrame() async {
    try {
      final boundary =
          _camKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 1.0);
      setState(() {
        _lastFrame = image;
      });
    } catch (e) {
      debugPrint('Error capturing last frame: $e');
    }
  }

  /// Camera preview placeholder (gradient background)
  /// Camera preview placeholder (gradient background)
  Widget _buildCameraPreview() {
    Widget child;
    Key key;

    // Prioritize Frozen Frame (Screen Capture) if available to avoid Red Screen
    // This allows us to dispose the controller safely while showing a static image.
    if (_lastFrame != null) {
      key = const ValueKey('frozen');
      child = SizedBox.expand(
        child: RawImage(image: _lastFrame, fit: BoxFit.cover),
      );
    } else if (_isCameraInitialized &&
        _controller != null &&
        _controller!.value.isInitialized) {
      // Live Camera
      key = const ValueKey('live');
      child = RepaintBoundary(
        key: _camKey,
        child: SizedBox.expand(child: CameraPreview(_controller!)),
      );
    } else {
      // Loading State
      key = const ValueKey('loading');
      child = Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white24,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: AnimatedSwitcher(
        // If we have a frozen frame, switch instantly to it (duration 0)
        // so we can dispose the controller immediately without 'Red Screen' error.
        // When switching back to live ('frozen' -> 'live'), animate slowly (fade).
        duration: (_lastFrame != null && key == const ValueKey('frozen'))
            ? Duration.zero
            : const Duration(milliseconds: 600),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: KeyedSubtree(key: key, child: child),
      ),
    );
  }

  /// Gradient overlay for better visibility of UI elements
  Widget _buildGradientOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.cameraOverlayGradient,
        ),
      ),
    );
  }

  /// Top bar with gender indicator and flash toggle
  Widget _buildTopBar() {
    // Flash is only available on back camera usually
    final bool isFlashAvailable =
        _controller != null &&
        _controller!.description.lensDirection == CameraLensDirection.back;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Gender indicator (left)
          const GenderIndicator(gender: Gender.male),

          // App title (center)
          Text(
            'Morphy',
            style: GoogleFonts.outfit(
              color: AppColors.textPrimary.withValues(alpha: 0.9),
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),

          // Right side actions
          Row(
            children: [
              // Camera Switcher
              IconButton(
                onPressed: _cycleCamera,
                icon: const Icon(
                  Icons.cameraswitch_outlined,
                  color: Colors.white,
                ),
                tooltip: 'Switch Camera',
              ),
              const SizedBox(width: 8),
              // Flash toggle
              FlashToggle(
                initialState: _isFlashOn,
                onChanged: isFlashAvailable ? _onFlashChanged : null,
                isEnabled: isFlashAvailable,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cycleCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;

    // 1. Check if recording is in progress and stop it safely
    if (_isRecording &&
        _controller != null &&
        _controller!.value.isRecordingVideo) {
      try {
        final XFile videoFile = await _controller!.stopVideoRecording();

        // Non-blocking save: we don't await this to speed up UI,
        // OR we should await if we want to ensure it's saved before controller dies?
        // Disposing controller usually doesn't affect the file (XFile is temp path).
        // So we can trigger save async.
        // However, user said "recorder continue but not saved".
        // This implies we need to explicitly stop it here.
        _saveVideoFile(videoFile);

        setState(() {
          _isRecording = false;
        });
        debugPrint('Recording auto-stopped due to camera switch');
      } catch (e) {
        debugPrint('Error stopping recording during switch: $e');
      }
    }

    // 2. Capture current frame to display while switching
    await _captureLastFrame();

    final lensDirection = _controller?.description.lensDirection;
    CameraDescription newCamera;

    if (lensDirection == CameraLensDirection.back) {
      newCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras![0],
      );
    } else {
      newCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras![0],
      );
    }

    setState(() {
      _isCameraInitialized = false;
    });

    if (_controller != null) {
      // Explicitly turn off flash to prevent it from getting stuck on
      // if we are switching away from back camera
      if (_controller!.value.isInitialized &&
          _controller!.description.lensDirection == CameraLensDirection.back) {
        try {
          await _controller!.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      await _controller!.dispose();
    }

    // Initialize new controller
    _controller = CameraController(
      newCamera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      // Reset flash state potentially or keep it off
      await _controller!.setFlashMode(FlashMode.off);
      if (mounted) {
        setState(() {
          _isFlashOn = false;
          _isCameraInitialized = true;
          // Clear the frozen frame so we see the live camera again
          // Delay slightly to let the stream start
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _lastFrame = null;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error switching camera: $e');
    }
  }

  /// Bottom controls with filter selector, intensity slider and capture button
  Widget _buildBottomControls() {
    // Height calculation:
    // Capture button size (approx 90) + padding (24) = 114
    // Slider expanded height (220) needs to fit
    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // 1. Filter Selector (at bottom, same line as capture button)
          // Adjusted bottom padding to align center of filters with center of capture button
          // Capture button center is at bottom + 24 + 45 (half height) = 69px from bottom
          // Filter item height is approx 80px (54 circle + text)
          // We want center of circle (27px from top of item) to align with 69px
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: FilterSelector(
              initialIndex: _selectedFilterIndex,
              onFilterChanged: _onFilterChanged,
            ),
          ),

          // 2. Capture Button (Centered at bottom)
          Positioned(
            bottom: 48,
            child: CaptureButton(
              onTapCapture: _onCapture,
              onRecordingStart: _onRecordingStart,
              onRecordingStop: _onRecordingStop,
              filterColors: _currentFilter.colors,
            ),
          ),

          // 3. Intensity Slider (Centered above capture button)
          // Positioned higher up so the arrow sits above the button
          Positioned(
            bottom: 138,
            left: 0,
            right: 0,
            child: Center(
              child: IntensitySlider(
                initialValue: _filterIntensity,
                onChanged: _onIntensityChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Recording indicator at top
  Widget _buildRecordingIndicator() {
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.recording.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'REC',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
