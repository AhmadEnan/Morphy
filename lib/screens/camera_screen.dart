import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/deepar_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({Key? key}) : super(key: key);
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late DeepARService _deepARService;
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isFrontCamera = true;
  String _currentEffect = 'none';
  int? _textureId; // Store texture ID for camera preview
  double _cameraAspectRatio = 16 / 9; // Default aspect ratio, will be updated

  // Available effects (matching Android implementation)
  final List<String> _effects = [
    'none',
    'viking_helmet.deepar',
    'MakeupLook.deepar',
    'Split_View_Look.deepar',
    'Emotions_Exaggerator.deepar',
    'Emotion_Meter.deepar',
    'Stallone.deepar',
    'flower_face.deepar',
    'galaxy_background.deepar',
    'Humanoid.deepar',
    'Neon_Devil_Horns.deepar',
    'Ping_Pong.deepar',
    'Pixel_Hearts.deepar',
    'Snail.deepar',
    'Hope.deepar',
    'Vendetta_Mask.deepar',
    'Fire_Effect.deepar',
    'burning_effect.deepar',
    'Elephant_Trunk.deepar',
  ];

  @override
  void initState() {
    super.initState();
    _deepARService = DeepARService();
    _setupCallbacks();
    _initialize();
  }

  void _setupCallbacks() {
    _deepARService.onInitialized = () {
      setState(() {
        _isInitialized = true;
      });
      _showMessage('DeepAR initialized');
    };

    _deepARService.onScreenshotTaken = (path) {
      _showMessage('Screenshot saved: $path');
    };

    _deepARService.onVideoRecordingStarted = () {
      setState(() {
        _isRecording = true;
      });
      _showMessage('Recording started');
    };

    _deepARService.onVideoRecordingFinished = () {
      setState(() {
        _isRecording = false;
      });
      _showMessage('Recording finished');
    };

    _deepARService.onVideoRecordingFailed = () {
      setState(() {
        _isRecording = false;
      });
      _showMessage('Recording failed');
    };

    _deepARService.onEffectSwitched = (effectName) {
      setState(() {
        _currentEffect = effectName;
      });
    };

    _deepARService.onError = (error) {
      _showMessage('Error: $error');
    };
  }

  Future<void> _initialize() async {
    // Request permissions
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    final storageStatus = await Permission.storage.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      _showMessage('Camera or microphone permission denied');
      return;
    }

    // Initialize DeepAR
    // IMPORTANT: Replace with your actual license key from https://developer.deepar.ai
    final initialized = await _deepARService.initialize(
      '4982a37c51bb6b7001492bc4765f7d7dac91a6ae234f4049a127e71851c37d4d90ce8bdff2fa06ae',
    );

    if (initialized) {
      // Start camera and get camera info (texture ID + dimensions)
      final cameraInfo = await _deepARService.startCamera();
      if (cameraInfo != null) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _switchCamera() async {
    await _deepARService.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  Future<void> _nextEffect() async {
    final effect = await _deepARService.nextEffect();
    if (effect != null) {
      setState(() {
        _currentEffect = effect;
      });
    }
  }

  Future<void> _previousEffect() async {
    final effect = await _deepARService.previousEffect();
    if (effect != null) {
      setState(() {
        _currentEffect = effect;
      });
    }
  }

  Future<void> _takeScreenshot() async {
    await _deepARService.takeScreenshot();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _deepARService.stopRecording();
    } else {
      await _deepARService.startRecording();
    }
  }

  @override
  void dispose() {
    _deepARService.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview - fits within screen without zooming or stretching
          // Frame rotated 90 degrees counter-clockwise
          if (_textureId != null)
            Center(
              child: RotatedBox(
                quarterTurns: 3, // 90 degrees counter-clockwise (left)
                child: AspectRatio(
                  aspectRatio: _cameraAspectRatio,
                  child: Texture(textureId: _textureId!),
                ),
              ),
            )
          else
            Container(
              color: Colors.black,
              child: Center(
                child: _isInitialized
                    ? const Text(
                        'Initializing camera...',
                        style: TextStyle(color: Colors.white),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),

          // UI Controls
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Switch camera button
                      IconButton(
                        icon: const Icon(
                          Icons.flip_camera_ios,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: _switchCamera,
                      ),

                      // Current effect name
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _currentEffect == 'none'
                              ? 'No Effect'
                              : _currentEffect.replaceAll('.deepar', ''),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),

                      const SizedBox(width: 48), // Spacer for symmetry
                    ],
                  ),
                ),

                const Spacer(),

                // Bottom controls
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Effect navigation
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Previous effect
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: _previousEffect,
                          ),

                          // Record/Screenshot button
                          GestureDetector(
                            onTap: _takeScreenshot,
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                                color: _isRecording
                                    ? Colors.red
                                    : Colors.transparent,
                              ),
                              child: _isRecording
                                  ? const Icon(
                                      Icons.stop,
                                      color: Colors.white,
                                      size: 32,
                                    )
                                  : const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                            ),
                          ),

                          // Next effect
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: _nextEffect,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Mode switcher
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildModeButton('Screenshot', !_isRecording, () {
                            // Switch to screenshot mode
                          }),
                          const SizedBox(width: 16),
                          _buildModeButton(
                            'Record',
                            _isRecording,
                            _toggleRecording,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, bool isActive, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
