import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_audio_recorder/flutter_audio_recorder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhasspy_mobile_app/utils/utils.dart';

class AudioRecorderIsolate {
  SendPort _sendPort;

  Isolate _isolate;
  SendPort otherIsolate;
  final _isolateReady = Completer<void>();
  FlutterAudioRecorder _recorder;
  Future<bool> get isRecording async {
    if ((await _recorder?.current())?.status == RecordingStatus.Recording) {
      return true;
    } else {
      return false;
    }
  }

  AudioRecorderIsolate({this.otherIsolate}) {
    init();
    setOtherIsolate(otherIsolate);
  }

  Future<void> get isReady => _isolateReady.future;

  void dispose() {
    _isolate.kill();
  }

  Future<void> init() async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    errorPort.listen(print);
    receivePort.listen(_handleMessage);
    _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort,
        onError: errorPort.sendPort,
        debugName: "recorder",
        errorsAreFatal: false);
  }

  Future<void> setOtherIsolate([SendPort otherIsolate]) async {
    await isReady;
    if (otherIsolate == null) otherIsolate = this.otherIsolate;
    _sendPort.send(otherIsolate);
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      _isolateReady.complete();
      return;
    }
  }

  Future<void> startRecording() async {
    Directory appDocDirectory = await getApplicationDocumentsDirectory();
    String pathFile = appDocDirectory.path + "/speech_to_text.wav";
    if (File(pathFile).existsSync()) File(pathFile).deleteSync();
    _recorder = FlutterAudioRecorder(pathFile, audioFormat: AudioFormat.WAV);
    await _recorder.initialized;
    await _recorder.start();
    _sendPort.send({"StartRecording": pathFile});
  }

  void stopRecording() {
    if (_recorder != null) {
      _recorder.stop();
      _sendPort.send("StopRecording");
    }
  }

  static Future<void> _isolateEntry(dynamic message) async {
    SendPort sendPort;
    SendPort otherIsolate;
    final receivePort = ReceivePort();
    Timer timerForAudio;
    receivePort.listen((dynamic message) async {
      print("message $message is a istance of ${message.runtimeType}");
      if (message is Map<String, dynamic>) {
        if (message.containsKey("StartRecording")) {
          int previousLength = 0;
          // prepare the file that will contain the audio stream
          File audioFile = File(message["StartRecording"] + ".temp");
          int chunkSize = 2048;
          int byteRate = (16000 * 16 * 1 ~/ 8);
          bool active = false;
          timerForAudio =
              Timer.periodic(Duration(milliseconds: 1), (Timer t) async {
            int fileLength;
            try {
              fileLength = audioFile.lengthSync();
            } on FileSystemException {
              t.cancel();
            }
            // if a chunk is available to send
            if ((fileLength - previousLength) >= chunkSize) {
              if (active) {
                return;
              }
              active = true;
              // start reading the last chunk
              Stream<List<int>> dataStream = audioFile.openRead(
                  previousLength, previousLength + chunkSize);
              List<int> dataFile = [];
              dataStream.listen(
                (data) {
                  dataFile += data;
                },
                onDone: () async {
                  if (dataFile.isNotEmpty) {
                    print("previous length: $previousLength");
                    print("Length: $fileLength");
                    previousLength += chunkSize;
                    // append the header to the beginning of the chunk
                    Uint8List header =
                        waveHeader(chunkSize, 16000, 1, byteRate);
                    dataFile.insertAll(0, header);
                    otherIsolate.send(Uint8List.fromList(dataFile));
                    // audioStreamcontroller.add(Uint8List.fromList(dataFile));
                    active = false;
                  }
                },
              );
            }
          });
        }
      }
      if (message is String) {
        switch (message) {
          case "StopRecording":
            timerForAudio.cancel();
            break;
          default:
        }
      }
      if (message is SendPort) {
        otherIsolate = message;
      }
    });
    if (message is SendPort) {
      if (sendPort == null) {
        sendPort = message;
        sendPort.send(receivePort.sendPort);
        return;
      }
    }
  }
}
