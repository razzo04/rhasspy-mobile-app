import 'package:flutter/services.dart';

class WakeWordUtils {
  static const MethodChannel _channel = const MethodChannel('wake_word');

  Future<bool> get isRunning {
    return _channel.invokeMethod("isRunning");
  }

  Future<bool> get isListening {
    return _channel.invokeMethod("isListening");
  }

  Future<List<String>> get availableWakeWordDetector async {
    return List.castFrom<dynamic, String>(
        (await _channel.invokeMethod("getWakeWordDetector")));
  }

  Future<bool> pause() {
    return _channel.invokeMethod("pause");
  }

  Future<bool> resume() {
    return _channel.invokeMethod("resume");
  }
}
