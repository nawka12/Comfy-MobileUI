import 'dart:io';
import 'package:flutter/services.dart';

class AndroidForegroundService {
  static const _channel = MethodChannel('com.kayfahaarukku.comfymobile/foreground_service');

  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('start');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
