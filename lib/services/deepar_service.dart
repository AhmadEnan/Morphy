import 'package:flutter/services.dart';

/// Holds camera texture information including dimensions
class CameraInfo {
  final int textureId;
  final int width;
  final int height;

  CameraInfo({
    required this.textureId,
    required this.width,
    required this.height,
  });

  double get aspectRatio => width / height;
}

/// Represents a gender classification result from the native classifier
class GenderClassificationResult {
  final String gender;
  final double confidence;

  GenderClassificationResult({required this.gender, required this.confidence});

  bool get isMale => gender == 'male';
  bool get isFemale => gender == 'female';
}

class DeepARService {
  static const MethodChannel _channel = MethodChannel('deepar_plugin');

  // Callbacks
  Function(String)? onScreenshotTaken;
  Function()? onVideoRecordingStarted;
  Function()? onVideoRecordingFinished;
  Function()? onVideoRecordingFailed;
  Function()? onInitialized;
  Function(bool)? onFaceVisibilityChanged;
  Function(String)? onEffectSwitched;
  Function(String)? onError;
  Function(GenderClassificationResult)? onGenderClassified;

  DeepARService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onScreenshotTaken':
        final path = call.arguments['path'] as String;
        onScreenshotTaken?.call(path);
        break;
      case 'onVideoRecordingStarted':
        onVideoRecordingStarted?.call();
        break;
      case 'onVideoRecordingFinished':
        onVideoRecordingFinished?.call();
        break;
      case 'onVideoRecordingFailed':
        onVideoRecordingFailed?.call();
        break;
      case 'onInitialized':
        onInitialized?.call();
        break;
      case 'onFaceVisibilityChanged':
        final visible = call.arguments['visible'] as bool;
        onFaceVisibilityChanged?.call(visible);
        break;
      case 'onEffectSwitched':
        final effectName = call.arguments['effectName'] as String?;
        if (effectName != null) {
          onEffectSwitched?.call(effectName);
        }
        break;
      case 'onError':
        final error =
            call.arguments['error'] as String? ??
            call.arguments['errorMessage'] as String? ??
            'Unknown error';
        onError?.call(error);
        break;
      case 'onGenderClassified':
        final gender = call.arguments['gender'] as String;
        final confidence = (call.arguments['confidence'] as num).toDouble();
        onGenderClassified?.call(
          GenderClassificationResult(gender: gender, confidence: confidence),
        );
        break;
    }
  }

  /// Initialize DeepAR with license key
  Future<bool> initialize(String licenseKey) async {
    try {
      final result = await _channel.invokeMethod('initialize', {
        'licenseKey': licenseKey,
      });
      return result as bool;
    } catch (e) {
      print('DeepAR initialization error: $e');
      return false;
    }
  }

  /// Start camera preview - returns camera info with texture ID and dimensions
  Future<CameraInfo?> startCamera() async {
    try {
      final result = await _channel.invokeMethod('startCamera');
      if (result is Map) {
        return CameraInfo(
          textureId: result['textureId'] as int,
          width: result['width'] as int,
          height: result['height'] as int,
        );
      }
      return null;
    } catch (e) {
      print('Start camera error: $e');
      return null;
    }
  }

  /// Switch between front and back camera
  Future<bool> switchCamera() async {
    try {
      final result = await _channel.invokeMethod('switchCamera');
      return result as bool;
    } catch (e) {
      print('Switch camera error: $e');
      return false;
    }
  }

  /// Switch to a specific effect
  Future<bool> switchEffect(String effectName) async {
    try {
      print('DeepARService.switchEffect: Sending effectName = "$effectName"');
      final result = await _channel.invokeMethod('switchEffect', {
        'effectName': effectName,
      });
      print('DeepARService.switchEffect: Result = $result');
      return result as bool;
    } catch (e) {
      print('Switch effect error: $e');
      return false;
    }
  }

  /// Go to next effect
  Future<String?> nextEffect() async {
    try {
      final result = await _channel.invokeMethod('nextEffect');
      return result as String?;
    } catch (e) {
      print('Next effect error: $e');
      return null;
    }
  }

  /// Go to previous effect
  Future<String?> previousEffect() async {
    try {
      final result = await _channel.invokeMethod('previousEffect');
      return result as String?;
    } catch (e) {
      print('Previous effect error: $e');
      return null;
    }
  }

  /// Take a screenshot
  Future<bool> takeScreenshot() async {
    try {
      final result = await _channel.invokeMethod('takeScreenshot');
      return result as bool;
    } catch (e) {
      print('Take screenshot error: $e');
      return false;
    }
  }

  /// Toggle flash/torch on or off (only works with back camera)
  Future<bool> setFlashEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod('setFlashEnabled', {
        'enabled': enabled,
      });
      return result as bool? ?? false;
    } catch (e) {
      print('Set flash error: $e');
      return false;
    }
  }

  /// Start video recording
  Future<String?> startRecording() async {
    try {
      final result = await _channel.invokeMethod('startRecording');
      return result as String?;
    } catch (e) {
      print('Start recording error: $e');
      return null;
    }
  }

  /// Stop video recording
  Future<String?> stopRecording() async {
    try {
      final result = await _channel.invokeMethod('stopRecording');
      return result as String?;
    } catch (e) {
      print('Stop recording error: $e');
      return null;
    }
  }

  /// Dispose and cleanup resources
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
    } catch (e) {
      print('Dispose error: $e');
    }
  }

  /// Enable or disable gender classification
  Future<bool> setClassificationEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod('setClassificationEnabled', {
        'enabled': enabled,
      });
      return result as bool;
    } catch (e) {
      print('Set classification enabled error: $e');
      return false;
    }
  }

  /// Change a float parameter on a DeepAR effect
  /// [gameObject] - The name of the GameObject in the effect (e.g., 'FilterNode')
  /// [component] - The component name, typically 'MeshRenderer' for materials
  /// [parameter] - The uniform variable name (e.g., 'u_intensity')
  /// [value] - The float value to set (typically 0.0 to 1.0)
  Future<bool> changeParameterFloat({
    required String gameObject,
    required String component,
    required String parameter,
    required double value,
  }) async {
    try {
      final result = await _channel.invokeMethod('changeParameterFloat', {
        'gameObject': gameObject,
        'component': component,
        'parameter': parameter,
        'value': value,
      });
      return result as bool? ?? true;
    } catch (e) {
      print('Change parameter float error: $e');
      return false;
    }
  }

  /// Change a vec4 parameter on a DeepAR effect (e.g., for RGBA color control)
  Future<bool> changeParameterVec4({
    required String gameObject,
    required String component,
    required String parameter,
    required double x,
    required double y,
    required double z,
    required double w,
  }) async {
    try {
      final result = await _channel.invokeMethod('changeParameterVec4', {
        'gameObject': gameObject,
        'component': component,
        'parameter': parameter,
        'x': x,
        'y': y,
        'z': z,
        'w': w,
      });
      return result as bool? ?? true;
    } catch (e) {
      print('Change parameter vec4 error: $e');
      return false;
    }
  }

  /// Set filter intensity using multiple approaches for compatibility
  /// Tries different parameter names commonly used in DeepAR effects
  Future<bool> setFilterIntensity(double intensity) async {
    final clampedValue = intensity.clamp(0.0, 1.0);

    // Try multiple common parameter configurations
    // These are common names used in DeepAR effects
    final attempts = [
      // Standard intensity parameters
      {
        'gameObject': 'FilterNode',
        'component': 'MeshRenderer',
        'parameter': 'u_intensity',
      },
      {
        'gameObject': 'effect',
        'component': 'MeshRenderer',
        'parameter': 'u_intensity',
      },
      {
        'gameObject': 'root',
        'component': 'MeshRenderer',
        'parameter': 'u_intensity',
      },
      // Opacity/alpha parameters
      {
        'gameObject': 'FilterNode',
        'component': 'MeshRenderer',
        'parameter': 'u_alpha',
      },
      {
        'gameObject': 'effect',
        'component': 'MeshRenderer',
        'parameter': 'u_alpha',
      },
      // Mix/blend parameters
      {
        'gameObject': 'FilterNode',
        'component': 'MeshRenderer',
        'parameter': 'u_mix',
      },
      {
        'gameObject': 'effect',
        'component': 'MeshRenderer',
        'parameter': 'u_mix',
      },
    ];

    bool anySuccess = false;
    for (final attempt in attempts) {
      final success = await changeParameterFloat(
        gameObject: attempt['gameObject']!,
        component: attempt['component']!,
        parameter: attempt['parameter']!,
        value: clampedValue,
      );
      if (success) {
        anySuccess = true;
        print(
          'setFilterIntensity: success with ${attempt['gameObject']}/${attempt['parameter']}',
        );
        break;
      }
    }

    return anySuccess;
  }
}
