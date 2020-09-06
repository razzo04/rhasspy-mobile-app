import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rhasspy_mobile_app/wake_word/wake_word_base.dart';

class UdpWakeWord extends WakeWordBase {
  String ip;
  int port;
  UdpWakeWord(this.ip, this.port);
  @visibleForTesting
  static const MethodChannel channel = const MethodChannel('wake_word');

  @override
  Future<bool> get isAvailable async {
    List<String> availableWakeWordDetector =
        await super.availableWakeWordDetector;
    return availableWakeWordDetector.contains(name);
  }

  @override
  Future<bool> startListening() {
    return channel.invokeMethod(
        "start", {"ip": this.ip, "port": this.port, "wakeWordDetector": name});
  }

  @override
  Future<bool> stopListening() {
    return channel.invokeMethod("stop");
  }

  @override
  String name = "UDP";
}
