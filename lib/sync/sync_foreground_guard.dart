import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SyncForegroundGuard {
  static const MethodChannel _channel = MethodChannel(
    'love_diary/sync_foreground',
  );

  static Future<void> start({
    required String label,
    double? progress,
  }) async {
    if (!_isAndroid) {
      return;
    }
    await _invokeSafely('start', label: label, progress: progress);
  }

  static Future<void> update({
    required String label,
    double? progress,
  }) async {
    if (!_isAndroid) {
      return;
    }
    await _invokeSafely('update', label: label, progress: progress);
  }

  static Future<void> stop() async {
    if (!_isAndroid) {
      return;
    }
    await _invokeSafely('stop');
  }

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<void> _invokeSafely(
    String method, {
    String? label,
    double? progress,
  }) async {
    try {
      await _channel.invokeMethod<void>(method, <String, Object?>{
        if (label != null) 'label': label,
        if (progress != null) 'progress': progress.clamp(0, 1),
      });
    } on PlatformException catch (error) {
      debugPrint('Sync foreground guard failed: $error');
    } catch (error) {
      debugPrint('Sync foreground guard failed: $error');
    }
  }
}
