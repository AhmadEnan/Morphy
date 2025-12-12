import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/colors.dart';
import '../widgets/filter_selector.dart';
import '../widgets/capture_button.dart';
import '../widgets/gender_indicator.dart';
import '../widgets/intensity_slider.dart';
import '../../services/deepar_service.dart';

/// Main camera screen with DeepAR integration
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
  bool _isRecording = false;

  // DeepAR
  late DeepARService _deepARService;
  int? _textureId;
  double _cameraAspectRatio = 9 / 16; // Portrait aspect ratio
  bool _isDeepARInitialized = false;
  bool _isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    _deepARService = DeepARService();
    _setupDeepARCallbacks();
    _initializeDeepAR();

    if (widget.syncFailed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asset Synchronization Failed'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  void _setupDeepARCallbacks() {
    _deepARService.onInitialized = () {
      if (mounted) {
        setState(() {
          _isDeepARInitialized = true;
        });
      }
      debugPrint('DeepAR initialized');
    };

    _deepARService.onScreenshotTaken = (path) {
      _showMessage('Screenshot saved: $path');
    };

    _deepARService.onVideoRecordingStarted = () {
      if (mounted) {
        setState(() {
          _isRecording = true;
        });
      }
      debugPrint('Recording started');
    };

    _deepARService.onVideoRecordingFinished = () {
      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }
      debugPrint('Recording finished');
    };

    _deepARService.onVideoRecordingFailed = () {
      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }
      _showMessage('Recording failed');
    };

    _deepARService.onEffectSwitched = (effectName) {
      debugPrint('Effect switched to: $effectName');
    };

    _deepARService.onError = (error) {
      debugPrint('DeepAR error: $error');
    };
  }

  Future<void> _initializeDeepAR() async {
    // Request permissions
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    await Permission.storage.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      _showMessage('Camera or microphone permission denied');
      return;
    }

    // Initialize DeepAR with license key
    final initialized = await _deepARService.initialize(
      '4982a37c51bb6b7001492bc4765f7d7dac91a6ae234f4049a127e71851c37d4d90ce8bdff2fa06ae',
    );

    if (initialized) {
      // Start camera
      final cameraInfo = await _deepARService.startCamera();
      if (cameraInfo != null && mounted) {
        setState(() {
          _textureId = cameraInfo.textureId;
          _cameraAspectRatio = cameraInfo.aspectRatio;
        });
      }
    } else {
      _showMessage('Failed to initialize DeepAR');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _deepARService.dispose();
    super.dispose();
  }

  // Get current filter
  FilterItem get _currentFilter => sampleFilters[_selectedFilterIndex];

  void _onFilterChanged(FilterItem filter, int index) {
    setState(() {
      _selectedFilterIndex = index;
    });
    // Switch DeepAR effect
    _deepARService.switchEffect(filter.effectFile);
    debugPrint('Filter changed to: ${filter.name} (${filter.effectFile})');
  }

  void _onIntensityChanged(double value) {
    setState(() {
      _filterIntensity = value;
    });
    debugPrint('Intensity: ${(value * 100).toInt()}%');
  }

  void _onCapture() {
    _deepARService.takeScreenshot();
    debugPrint('📸 Photo captured!');
  }

  Future<void> _onRecordingStart() async {
    if (_isRecording) return;
    await _deepARService.startRecording();
    debugPrint('🔴 Recording started');
  }

  Future<void> _onRecordingStop() async {
    if (!_isRecording) return;
    final path = await _deepARService.stopRecording();
    if (path != null) {
      debugPrint('⏹️ Recording stopped: $path');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video saved: ${path.split('/').last}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _cycleCamera() async {
    // Stop recording if in progress
    if (_isRecording) {
      await _deepARService.stopRecording();
      setState(() {
        _isRecording = false;
      });
    }

    await _deepARService.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background: DeepAR Camera preview
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

                // Bottom Controls
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

  /// DeepAR Camera preview
  Widget _buildCameraPreview() {
    if (_textureId != null) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraAspectRatio > 1 ? _cameraAspectRatio * 1000 : 1000,
            height: _cameraAspectRatio > 1 ? 1000 : 1000 / _cameraAspectRatio,
            child: Texture(textureId: _textureId!),
          ),
        ),
      );
    } else {
      return Container(
        color: Colors.black,
        child: Center(
          child: _isDeepARInitialized
              ? const Text(
                  'Initializing camera...',
                  style: TextStyle(color: Colors.white),
                )
              : const CircularProgressIndicator(
                  color: Colors.white24,
                  strokeWidth: 2,
                ),
        ),
      );
    }
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

  /// Top bar with gender indicator and camera switch
  Widget _buildTopBar() {
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

          // Camera switch button (right)
          IconButton(
            onPressed: _cycleCamera,
            icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
            tooltip: 'Switch Camera',
          ),
        ],
      ),
    );
  }

  /// Bottom controls with filter selector, intensity slider and capture button
  Widget _buildBottomControls() {
    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // 1. Filter Selector
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: FilterSelector(
              initialIndex: _selectedFilterIndex,
              onFilterChanged: _onFilterChanged,
            ),
          ),

          // 2. Capture Button
          Positioned(
            bottom: 48,
            child: CaptureButton(
              onTapCapture: _onCapture,
              onRecordingStart: _onRecordingStart,
              onRecordingStop: _onRecordingStop,
              filterColors: _currentFilter.colors,
            ),
          ),

          // 3. Intensity Slider
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
