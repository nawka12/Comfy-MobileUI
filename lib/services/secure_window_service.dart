import 'dart:io';
import 'package:flutter/services.dart';

/// Toggles Android's `WindowManager.FLAG_SECURE`, which redacts the app's
/// snapshot in the recents/app-switcher view and blocks screenshots.
/// No-op on non-Android platforms.
class SecureWindowService {
  static const _channel =
      MethodChannel('com.kayfahaarukku.comfymobile/secure_window');

  static Future<void> setSecure(bool secure) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('setSecure', {'secure': secure});
    } catch (_) {}
  }
}
