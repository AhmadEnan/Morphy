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
      final result = await _channel.invokeMethod('switchEffect', {
        'effectName': effectName,
      });
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
}
