import 'package:flutter/services.dart';

/// Opens an external web page without adding another AndroidX dependency.
class ExternalUrlLauncher {
  static const MethodChannel _channel = MethodChannel('bearfuel/external_url');

  static Future<bool> open(String url) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openUrl',
            <String, dynamic>{'url': url},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
