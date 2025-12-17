import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/colors.dart';
import '../widgets/filter_selector.dart';
import '../widgets/capture_button.dart';
import '../widgets/gender_indicator.dart';
import '../widgets/intensity_slider.dart';
import '../../services/deepar_service.dart';
import '../../models/gender_effects.dart';

/// Main camera screen with DeepAR integration and gender-based effects
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

  // Gender classification
  Gender _detectedGender = Gender.unknown;
  double _genderConfidence = 0.0;
  String _lastGenderString = 'unknown'; // Track gender to detect changes

  // Temporal smoothing for gender detection
  int _consecutiveGenderCount = 0;
  String _pendingGender = 'unknown';
  static const int _requiredConsecutiveCount =
      3; // Require 3 consistent results

  // DeepAR
  late DeepARService _deepARService;
  int? _textureId;
  double _cameraAspectRatio = 9 / 16; // Portrait aspect ratio
  bool _isDeepARInitialized = false;
  bool _isFrontCamera = true;
  bool _isFlashOn = false;

  // Gender-based filters
  List<FilterItem> _currentFilters = [];
  final GlobalKey<FilterSelectorState> _filterSelectorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _deepARService = DeepARService();
    _initializeEffectsAndDeepAR();

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

  Future<void> _initializeEffectsAndDeepAR() async {
    // Initialize the gender effects service first
    await GenderEffectsService.instance.initialize();

    // Set initial filters (unknown gender = both only)
    setState(() {
      _currentFilters = GenderEffectsService.instance.getUnknownGenderFilters();
    });

    // Now setup DeepAR
    _setupDeepARCallbacks();
    await _initializeDeepAR();
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

    // Gender classification callback with temporal smoothing
    _deepARService.onGenderClassified = (result) {
      if (mounted && result.confidence > 0.6) {
        final newGender = result.isMale ? 'male' : 'female';

        // Temporal smoothing: count consecutive same-gender results
        if (newGender == _pendingGender) {
          _consecutiveGenderCount++;
        } else {
          _pendingGender = newGender;
          _consecutiveGenderCount = 1;
        }

        // Always update confidence display
        setState(() {
          _genderConfidence = result.confidence;
        });

        // Only switch gender after N consecutive same results
        if (_consecutiveGenderCount >= _requiredConsecutiveCount &&
            newGender != _lastGenderString) {
          _lastGenderString = newGender;
          setState(() {
            _detectedGender = result.isMale ? Gender.male : Gender.female;
          });
          _updateFiltersForGender(newGender);
          debugPrint(
            'Gender switched to: $newGender (after $_consecutiveGenderCount consistent results)',
          );
        }

        debugPrint(
          'Gender: ${result.gender} (${(result.confidence * 100).toInt()}%) - consecutive: $_consecutiveGenderCount',
        );
      }
    };
  }

  /// Update the filter list when gender changes
  void _updateFiltersForGender(String gender) {
    final newFilters = GenderEffectsService.instance.getFiltersForGender(
      gender,
    );

    if (newFilters.isEmpty) return;

    setState(() {
      _currentFilters = newFilters;
      _selectedFilterIndex = 0; // Reset to default filter
    });

    // Update the filter selector widget
    _filterSelectorKey.currentState?.updateFilters(newFilters);

    debugPrint(
      'Switched to $gender filter list (${newFilters.length} filters)',
    );
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
  FilterItem get _currentFilter => _selectedFilterIndex < _currentFilters.length
      ? _currentFilters[_selectedFilterIndex]
      : GenderEffectsService.defaultFilter;

  void _onFilterChanged(FilterItem filter, int index) {
    setState(() {
      _selectedFilterIndex = index;
    });
    // Switch DeepAR effect
    _deepARService.switchEffect(filter.effectFile);

    // Apply current intensity to the new filter
    if (_isDeepARInitialized) {
      _deepARService.setFilterIntensity(_filterIntensity);
    }

    debugPrint('Filter changed to: ${filter.name} (${filter.effectFile})');
  }

  void _onIntensityChanged(double value) {
    setState(() {
      _filterIntensity = value;
    });

    // Update DeepAR filter intensity if initialized
    if (_isDeepARInitialized) {
      _deepARService.setFilterIntensity(value);
    }

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

    // Turn off flash when switching cameras
    if (_isFlashOn) {
      await _deepARService.setFlashEnabled(false);
      setState(() {
        _isFlashOn = false;
      });
    }

    await _deepARService.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  Future<void> _toggleFlash() async {
    if (_isFrontCamera) return; // Flash only works with back camera

    final newState = !_isFlashOn;
    final success = await _deepARService.setFlashEnabled(newState);
    if (success) {
      setState(() {
        _isFlashOn = newState;
      });
    }
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
            // Use aspect ratio from native side (now portrait: 1080x1920)
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

  /// Top bar with gender indicator, flash button, and camera switch
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Gender indicator (left)
          GenderIndicator(
            gender: _detectedGender,
            confidence: _genderConfidence,
          ),

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

          // Flash and Camera switch buttons (right)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flash button - only visible when back camera is active
              if (!_isFrontCamera)
                IconButton(
                  onPressed: _toggleFlash,
                  icon: Icon(
                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                    color: _isFlashOn ? Colors.yellow : Colors.white,
                  ),
                  tooltip: _isFlashOn ? 'Turn off flash' : 'Turn on flash',
                ),
              // Camera switch button
              IconButton(
                onPressed: _cycleCamera,
                icon: const Icon(
                  Icons.cameraswitch_outlined,
                  color: Colors.white,
                ),
                tooltip: 'Switch Camera',
              ),
            ],
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
          // 1. Filter Selector - now uses dynamic gender-based filters
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: FilterSelector(
              key: _filterSelectorKey,
              initialIndex: _selectedFilterIndex,
              onFilterChanged: _onFilterChanged,
              filters: _currentFilters,
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
