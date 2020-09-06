import 'package:rhasspy_mobile_app/wake_word/wake_word_utils.dart';

abstract class WakeWordBase extends WakeWordUtils {
  String name;
  Future<bool> get isAvailable;
  Future<bool> startListening();
  Future<bool> stopListening();
}
