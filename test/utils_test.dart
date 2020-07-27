import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rhasspy_mobile_app/utils/utils.dart';

main() {
  test("test wave header", () {
    List<int> inputData = [];
    inputData
        .addAll(File('test_resources/audio/inputAudio1').readAsBytesSync());
    int sampleRate = 16000;
    int byteRate = (sampleRate * 16 * 1 ~/ 8);
    Uint8List header = waveHeader(inputData.length, sampleRate, 1, byteRate);
    inputData.insertAll(0, header);
    expect(
      inputData,
      File('test_resources/audio/outputAudio1.wav').readAsBytesSync(),
    );
  });
}
