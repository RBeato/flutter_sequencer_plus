import 'package:flutter/services.dart';

class FlutterSequencer {
  static const MethodChannel _channel = MethodChannel('flutter_sequencer');

  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static void registerWith() {
    // Plugin registration code
  }
}
