import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:morphy/services/asset_sync_service.dart';
import 'package:morphy/ui/screens/camera_screen.dart';
import 'package:morphy/models/gender_effects.dart';
import 'dart:math' as math;

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

class _StartupScreenState extends State<StartupScreen>
    with TickerProviderStateMixin {
  String _status = 'Initializing...';
  double _progress = 0.0;
  String? _currentFile;
  bool _syncFailed = false;
  SyncResult? _syncResult;
  bool _showFileLog = false;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAppSequence();
    });
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _fadeController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _startAppSequence() async {
    await _requestPermissions();
    await _syncAssets();

    // Load gender-based effects from asset folders
    setState(() {
      _status = 'Loading effects...';
      _progress = 0.95;
    });
    await GenderEffectsService.instance.initialize(
      assetFolderName: widget.assetFolderName,
    );
    setState(() {
      _progress = 1.0;
    });

    // Show file log briefly before navigating
    if (_syncResult != null && _syncResult!.totalFiles > 0) {
      setState(() => _showFileLog = true);
      await Future.delayed(const Duration(seconds: 3));
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => CameraScreen(
            syncFailed: _syncFailed,
            videoOutputFolderName: widget.videoOutputFolderName,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _status = 'Checking permissions...';
      _progress = 0.05;
    });

    await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.camera,
      Permission.microphone,
    ].request();
  }

  Future<void> _syncAssets() async {
    try {
      setState(() {
        _status = 'Connecting to server...';
        _progress = 0.1;
      });

      final result = await AssetSyncService().syncAssets(
        targetUrl: widget.manifestUrl,
        localFolderName: widget.assetFolderName,
        onProgress: (status, progress, currentFile) {
          if (mounted) {
            setState(() {
              _status = status;
              _progress = progress;
              _currentFile = currentFile;
            });
          }
        },
      );

      _syncResult = result;

      // Log results
      debugPrint('═══════════════════════════════════════════');
      debugPrint('📦 SYNC COMPLETE');
      debugPrint('───────────────────────────────────────────');
      debugPrint('✅ Downloaded: ${result.downloadedFiles.length} files');
      for (final file in result.downloadedFiles) {
        debugPrint('   • $file');
      }
      debugPrint('📁 Already existed: ${result.existingFiles.length} files');
      for (final file in result.existingFiles) {
        debugPrint('   • $file');
      }
      if (result.failedFiles.isNotEmpty) {
        debugPrint('❌ Failed: ${result.failedFiles.length} files');
        for (final file in result.failedFiles) {
          debugPrint('   • $file');
        }
      }
      debugPrint('───────────────────────────────────────────');
      debugPrint('📂 Files by category:');
      result.filesByCategory.forEach((category, files) {
        if (files.isNotEmpty) {
          debugPrint('   $category: ${files.length} files');
        }
      });
      debugPrint('═══════════════════════════════════════════');

      setState(() {
        _status = 'Sync complete!';
        _progress = 1.0;
        _currentFile = null;
      });
    } catch (e) {
      debugPrint('Startup Asset Sync Failed: $e');
      _syncFailed = true;
      if (mounted) {
        setState(() {
          _status = 'Sync failed. Using cached assets...';
          _progress = 1.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0D0D), Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Stack(
              children: [
                // Animated background particles
                ...List.generate(20, (index) => _buildParticle(index)),

                // Main content
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(flex: 2),
                        // Animated Logo
                        _buildAnimatedLogo(),
                        const SizedBox(height: 16),
                        // App Name
                        _buildAppName(),
                        const SizedBox(height: 8),
                        // Tagline
                        Text(
                          'Transform your reality',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 14,
                            letterSpacing: 2,
                          ),
                        ),
                        const Spacer(),
                        // Progress Section
                        _buildProgressSection(),
                        const SizedBox(height: 24),
                        // File Log (shown after sync)
                        if (_showFileLog && _syncResult != null)
                          _buildFileLog(),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParticle(int index) {
    final random = math.Random(index);
    final size = random.nextDouble() * 4 + 2;
    final left = random.nextDouble() * MediaQuery.of(context).size.width;
    final top = random.nextDouble() * MediaQuery.of(context).size.height;
    final delay = random.nextDouble() * 2;

    return Positioned(
      left: left,
      top: top,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final opacity =
              (math.sin((_pulseController.value + delay) * math.pi) + 1) / 4;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(opacity * 0.3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(opacity * 0.5),
                  blurRadius: size * 2,
                  spreadRadius: size / 2,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedLogo() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              return Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    startAngle: _rotationController.value * 2 * math.pi,
                    colors: const [
                      Color(0xFF6366F1),
                      Color(0xFF8B5CF6),
                      Color(0xFFEC4899),
                      Color(0xFF6366F1),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0D0D0D),
                  ),
                  child: const Icon(
                    Icons.face_retouching_natural,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAppName() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899)],
      ).createShader(bounds),
      child: const Text(
        'MORPHY',
        style: TextStyle(
          color: Colors.white,
          fontSize: 42,
          fontWeight: FontWeight.w900,
          letterSpacing: 8,
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Column(
      children: [
        // Progress bar
        Container(
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: Colors.white.withOpacity(0.1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: MediaQuery.of(context).size.width * 0.7 * _progress,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF6366F1),
                        Color(0xFF8B5CF6),
                        Color(0xFFEC4899),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Status text
        Text(
          _status,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
        ),
        if (_currentFile != null) ...[
          const SizedBox(height: 4),
          Text(
            _currentFile!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF6366F1).withOpacity(0.8),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Progress percentage
        Text(
          '${(_progress * 100).toInt()}%',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFileLog() {
    final result = _syncResult!;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: _showFileLog ? 1.0 : 0.0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF22C55E),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Assets Loaded',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFileCategory(
              'Downloaded',
              result.downloadedFiles.length,
              const Color(0xFF6366F1),
            ),
            _buildFileCategory(
              'Cached',
              result.existingFiles.length,
              const Color(0xFF22C55E),
            ),
            if (result.failedFiles.isNotEmpty)
              _buildFileCategory(
                'Failed',
                result.failedFiles.length,
                const Color(0xFFEF4444),
              ),
            const Divider(color: Colors.white12, height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: result.filesByCategory.entries
                  .where((e) => e.value.isNotEmpty)
                  .map((e) => _buildCategoryBadge(e.key, e.value.length))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCategory(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
          Text(
            '$count files',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge(String category, int count) {
    final icons = {
      'male': Icons.male,
      'female': Icons.female,
      'both': Icons.people,
    };
    final colors = {
      'male': const Color(0xFF3B82F6),
      'female': const Color(0xFFEC4899),
      'both': const Color(0xFF8B5CF6),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors[category]?.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors[category]?.withOpacity(0.3) ?? Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icons[category] ?? Icons.folder,
            size: 14,
            color: colors[category],
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              color: colors[category],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
