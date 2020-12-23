import 'dart:typed_data';

import 'dart:async';
import 'dart:isolate';

import 'package:rhasspy_mobile_app/main.dart';
import 'package:rhasspy_mobile_app/wake_word/wake_word_base.dart';

import 'parse_messages.dart';
import 'rhasspy_mqtt_api.dart';

class RhasspyMqttIsolate {
  int port;
  String host;
  bool ssl;
  String username;
  String password;
  String siteId;
  bool autoRestart = true;
  Stream<Uint8List> audioStream;
  Completer<bool> _isConnectedCompleter = Completer<bool>();
  Future<bool> get isConnected async {
    if (_sendPort == null) {
      print("Starting to wait");
      print(_isolateReady.isCompleted);
      await isReady;
      print("finished to wait");
    }

    _sendPort.send("isConnected");
    return _isConnectedCompleter.future;
  }

  int lastConnectionCode;
  WakeWordBase _wakeWordBase;

  bool isSessionManaged = false;
  String pemFilePath;
  SendPort _sendPort;
  ReceivePort _receivePort;

  /// the port to send message to isolate
  SendPort get sendPort => _sendPort;
  Isolate _isolate;
  Completer<int> _connectCompleter = Completer<int>();
  Completer<void> _isolateReady = Completer<void>();
  int timeOutIntent;
  void Function(NluIntentParsed) onReceivedIntent;
  void Function(AsrTextCaptured) onReceivedText;
  void Function(NluIntentNotRecognized) onIntentNotRecognized;
  Future<bool> Function(List<int>) onReceivedAudio;
  void Function(DialogueEndSession) onReceivedEndSession;
  void Function(DialogueContinueSession) onReceivedContinueSession;
  void Function(HotwordDetected) onHotwordDetected;
  void Function(NluIntentParsed) onTimeoutIntentHandle;
  void Function() stopRecording;
  Future<bool> Function() startRecording;
  void Function(DialogueStartSession) onStartSession;
  void Function() onConnected;
  void Function() onDisconnected;
  void Function(double volume) onSetVolume;

  @override
  Future<bool> get connected async {
    if ((await _connectCompleter.future) == 0) {
      return true;
    } else {
      return false;
    }
  }

  Future<void> get isReady => _isolateReady.future;

  RhasspyMqttIsolate(
      this.host, this.port, this.ssl, this.username, this.password, this.siteId,
      {this.timeOutIntent = 4,
      this.onReceivedIntent,
      this.onReceivedText,
      this.onReceivedAudio,
      this.onReceivedEndSession,
      this.onReceivedContinueSession,
      this.onTimeoutIntentHandle,
      this.onIntentNotRecognized,
      this.onHotwordDetected,
      this.onConnected,
      this.onDisconnected,
      this.onStartSession,
      this.startRecording,
      this.audioStream,
      this.stopRecording,
      this.onSetVolume,
      this.pemFilePath}) {
    _init();
  }

  void _init() {
    _initIsolate();
    _initializeMqtt();
    audioStream?.listen((event) {
      _sendPort.send(event);
    });
  }

  void dispose() {
    _isolate.kill();
  }

  void subscribeCallback({
    void Function(NluIntentParsed) onReceivedIntent,
    void Function(AsrTextCaptured) onReceivedText,
    Future<bool> Function(List<int>) onReceivedAudio,
    void Function(DialogueEndSession) onReceivedEndSession,
    void Function(DialogueContinueSession) onReceivedContinueSession,
    void Function(NluIntentParsed) onTimeoutIntentHandle,
    void Function(NluIntentNotRecognized) onIntentNotRecognized,
    void Function(HotwordDetected) onHotwordDetected,
    void Function() onConnected,
    void Function() onDisconnected,
    void Function(DialogueStartSession) onStartSession,
    Future<bool> Function() startRecording,
    void Function(double volume) onSetVolume,
    void Function() stopRecording,
    Stream<Uint8List> audioStream,
  }) {
    this.onReceivedIntent = onReceivedIntent;
    this.onReceivedText = onReceivedText;
    this.onReceivedAudio = onReceivedAudio;
    this.onReceivedEndSession = onReceivedEndSession;
    this.onReceivedContinueSession = onReceivedContinueSession;
    this.onTimeoutIntentHandle = onTimeoutIntentHandle;
    this.onIntentNotRecognized = onIntentNotRecognized;
    this.onHotwordDetected = onHotwordDetected;
    this.onStartSession = onStartSession;
    this.onConnected = onConnected;
    this.onDisconnected = onDisconnected;
    this.startRecording = startRecording;
    this.stopRecording = stopRecording;
    this.onSetVolume = onSetVolume;
    this.audioStream = audioStream;
    audioStream?.listen((event) {
      _sendPort.send(event);
    });
  }

  Future<int> connect() async {
    if (_sendPort == null) {
      await _isolateReady.future;
    }
    _sendPort.send("connect");
    return _connectCompleter.future;
  }

  Future<void> _initIsolate() async {
    _receivePort = ReceivePort();
    final errorPort = ReceivePort();
    errorPort.listen((error) {
      if (error is List) {
        if (error[0].contains("SocketException:")) {
          connect();
        }
      }
    });

    _receivePort.listen(_handleMessage);
    _isolate = await Isolate.spawn(_isolateEntry, _receivePort.sendPort,
        onError: errorPort.sendPort, debugName: "Mqtt", errorsAreFatal: false);
    _isolate.addOnExitListener(_receivePort.sendPort, response: "exit");
  }

  Future<void> _initializeMqtt() async {
    RhasspyMqttArguments rhasspyMqttArguments = RhasspyMqttArguments(
        this.host,
        this.port,
        this.ssl,
        this.username,
        this.password,
        this.siteId,
        this.pemFilePath,
        timeOutIntent: this.timeOutIntent,
        enableStream: this.audioStream == null ? false : true);
    await _isolateReady.future;
    _sendPort.send(rhasspyMqttArguments);
  }

  void update(String host, int port, bool ssl, String username, String password,
      String siteId, String pemFilePath) {
    RhasspyMqttArguments rhasspyMqttArguments = RhasspyMqttArguments(
      host,
      port,
      ssl,
      username,
      password,
      siteId,
      pemFilePath,
    );
    _sendPort.send(rhasspyMqttArguments);
  }

  void _handleMessage(dynamic message) async {
    if (message is SendPort) {
      _sendPort = message;
      _isolateReady.complete();
      _isolateReady = Completer();
      return;
    }
    if (message is String) {
      switch (message) {
        case "stopRecording":
          stopRecording();
          break;
        case "startRecording":
          startRecording().then((value) {
            _sendPort.send({"startRecording": value});
          });
          break;
        case "onConnected":
          _connectCompleter.complete(0);
          _connectCompleter = Completer<int>();
          if (onConnected != null) onConnected();
          break;
        case "onDisconnected":
          if (onDisconnected != null) onDisconnected();
          break;
        case "exit":
          if (autoRestart) {
            _init();
          }
          break;
        default:
      }
    }
    if (message is Map<String, Object>) {
      switch (message.keys.first) {
        case "connectCode":
          _connectCompleter.complete(message["connectCode"]);
          _connectCompleter = Completer<int>();
          lastConnectionCode = message["connectCode"];
          break;
        case "onReceivedAudio":
          onReceivedAudio(message["onReceivedAudio"])
              .then((value) => _sendPort.send({"onReceivedAudio": value}));
          break;
        case "onReceivedText":
          onReceivedText(message["onReceivedText"]);
          break;
        case "onReceivedIntent":
          onReceivedIntent(message["onReceivedIntent"]);
          break;
        case "onReceivedEndSession":
          onReceivedEndSession(message["onReceivedEndSession"]);
          break;
        case "onReceivedContinueSession":
          onReceivedContinueSession(message["onReceivedContinueSession"]);
          break;
        case "onTimeoutIntentHandle":
          onTimeoutIntentHandle(message["onTimeoutIntentHandle"]);
          break;
        case "onStartSession":
          if (onStartSession != null) onStartSession(message["onStartSession"]);
          break;
        case "isSessionManaged":
          isSessionManaged = message["isSessionManaged"];
          break;
        case "onIntentNotRecognized":
          onIntentNotRecognized(message["onIntentNotRecognized"]);
          break;
        case "onHotwordDetected":
          onHotwordDetected(message["onHotwordDetected"]);
          break;
        case "IsConnected":
          _isConnectedCompleter.complete(message["IsConnected"]);
          _isConnectedCompleter = Completer<bool>();
          break;
        case "onSetVolume":
          onSetVolume(message["onSetVolume"]);
          break;
        case "print":
          String messageToPrint = message["print"];
          if (messageToPrint.startsWith("[D] ")) {
            log.d(messageToPrint.replaceFirst("[D] ", ""), "MQTT");
          } else if (messageToPrint.startsWith("[I] ")) {
            log.i(messageToPrint.replaceFirst("[I] ", ""), "MQTT");
          } else if (messageToPrint.startsWith("[E] ")) {
            log.e(messageToPrint.replaceFirst("[E] ", ""), "MQTT");
          } else if (messageToPrint.startsWith("[W] ")) {
            log.w(messageToPrint.replaceFirst("[W] ", ""), "MQTT");
          }
          break;
        case "WakeWord":
          switch (message["WakeWord"]) {
            case "availableWakeWordDetector":
              sendPort.send({
                "availableWakeWordDetector":
                    await _wakeWordBase.availableWakeWordDetector
              });
              break;
            case "isRunning":
              sendPort.send({"isRunning": await _wakeWordBase.isRunning});
              break;
            case "pause":
              sendPort.send({"pause": await _wakeWordBase.pause()});
              break;
            case "resume":
              sendPort.send({"resume": await _wakeWordBase.resume()});
              break;
            default:
              throw UnimplementedError(
                  "Undefined behavior for message: $message");
          }
          break;
        default:
          throw UnimplementedError("Undefined behavior for message: $message");
      }
    }
  }

  static void _isolateEntry(dynamic message) async {
    SendPort sendPort;
    runZoned(() {
      RhasspyMqttApi rhasspyMqtt;
      final receivePort = ReceivePort();
      Completer<bool> _receivedAudio = Completer<bool>();
      Completer<bool> _startRecordingCompleter = Completer<bool>();
      StreamController<Uint8List> audioStream = StreamController();
      WakeWordBaseIsolate _wakeWordIsolate;
      receivePort.listen(
        (dynamic message) async {
          if (message is RhasspyMqttArguments) {
            if (rhasspyMqtt != null) {
              rhasspyMqtt.dispose();
              audioStream.close();
              audioStream = StreamController();
            }
            rhasspyMqtt = RhasspyMqttApi(message.host, message.port,
                message.ssl, message.username, message.password, message.siteId,
                timeOutIntent: message.timeOutIntent,
                pemFilePath: message.pemFilePath,
                audioStream: audioStream.stream,
                onReceivedAudio: (value) async {
              print("onReceivedAudio isolate");
              sendPort.send({"onReceivedAudio": value});
              return _receivedAudio.future;
            }, onReceivedText: (textCapture) {
              sendPort.send({"onReceivedText": textCapture});
            }, onReceivedIntent: (intentParsed) {
              sendPort.send({"onReceivedIntent": intentParsed});
            }, onReceivedEndSession: (endSession) {
              sendPort.send({"onReceivedEndSession": endSession});
              sendPort.send({"isSessionManaged": false});
            }, onReceivedContinueSession: (continueSession) {
              sendPort.send({"onReceivedContinueSession": continueSession});
            }, onTimeoutIntentHandle: (intentParsed) {
              sendPort.send({"onTimeoutIntentHandle": intentParsed});
            }, onConnected: () {
              sendPort.send("onConnected");
            }, onDisconnected: () {
              sendPort.send("onDisconnected");
            }, onHotwordDetected: (hotwordDetected) {
              sendPort.send({"onHotwordDetected": hotwordDetected});
            }, onStartSession: (startSession) {
              sendPort.send({"onStartSession": startSession});
              //TODO get isSessionStarted directly
              sendPort.send({"isSessionManaged": rhasspyMqtt.isSessionManaged});
            }, stopRecording: () {
              sendPort.send("stopRecording");
            }, startRecording: () {
              sendPort.send("startRecording");
              return _startRecordingCompleter.future;
            }, onIntentNotRecognized: (intent) {
              sendPort.send({"onIntentNotRecognized": intent});
            }, onSetVolume: (volume) {
              sendPort.send({"onSetVolume": volume});
            });
          } else if (message is String) {
            switch (message) {
              case "connect":
                int result = await rhasspyMqtt.connect();
                sendPort.send({"connectCode": result});
                break;
              case "stopListening":
                rhasspyMqtt.stopListening();
                break;
              case "cleanSession":
                rhasspyMqtt.cleanSession();
                break;
              case "enableWakeWord":
                _wakeWordIsolate = WakeWordBaseIsolate(sendPort: sendPort);
                rhasspyMqtt.enableWakeWord(_wakeWordIsolate);
                break;
              case "isConnected":
                sendPort.send({"IsConnected": rhasspyMqtt.isConnected});
                break;
              default:
                throw UnimplementedError(
                    "Undefined behavior for message: $message");
            }
          } else if (message is Map<String, dynamic>) {
            switch (message.keys.first) {
              case "onReceivedAudio":
                _receivedAudio.complete(message["onReceivedAudio"]);
                _receivedAudio = Completer();
                break;
              case "speechTotext":
                rhasspyMqtt.speechTotext(message["speechTotext"]["dataAudio"],
                    cleanSession: message["speechTotext"]["cleanSession"]);
                break;
              case "textToIntent":
                rhasspyMqtt.textToIntent(message["textToIntent"]["text"],
                    handle: message["textToIntent"]["handle"]);
                break;
              case "textToSpeech":
                rhasspyMqtt.textToSpeech(message["textToSpeech"]["text"],
                    generateSessionId: message["textToSpeech"]
                        ["generateSessionId"]);
                break;
              case "enableWakeWord":
                rhasspyMqtt.enableWakeWord(message["enableWakeWord"]);
                break;
              case "startRecording":
                _startRecordingCompleter.complete(message["startRecording"]);
                _startRecordingCompleter = Completer();
                break;
              case "isRunning":
                _wakeWordIsolate.isRunningCompleter
                    .complete(message["isRunning"]);
                _wakeWordIsolate.isRunningCompleter = Completer();
                break;
              case "wake":
                rhasspyMqtt.wake(
                    message["wake"]["hotWord"], message["wake"]["wakeWordId"]);
                break;
              case "availableWakeWordDetector":
                _wakeWordIsolate.availableWakeWordDetectorCompleter
                    .complete(message["availableWakeWordDetector"]);
                _wakeWordIsolate.availableWakeWordDetectorCompleter =
                    Completer();
                break;
              default:
                throw UnimplementedError(
                    "Undefined behavior for message: $message");
            }
          } else if (message is Uint8List) {
            audioStream.add(message);
          }
        },
      );

      if (message is SendPort) {
        sendPort = message;
        sendPort.send(receivePort.sendPort);
        return;
      }
    }, zoneSpecification:
        ZoneSpecification(print: (self, parent, zone, message) {
      sendPort.send({"print": message});
    }));
  }

  @override
  void speechTotext(Uint8List dataAudio, {bool cleanSession = true}) {
    _sendPort.send({
      "speechTotext": {"dataAudio": dataAudio, "cleanSession": cleanSession}
    });
  }

  void enableWakeWord(WakeWordBase wakeWord) {
    _wakeWordBase = wakeWord;
    _sendPort.send("enableWakeWord");
  }

  @override
  void stopListening() {
    _sendPort.send("stopListening");
  }

  @override
  void textToIntent(String text, {bool handle = true}) {
    _sendPort.send({
      "textToIntent": {"text": text, "handle": handle}
    });
  }

  @override
  void textToSpeech(String text, {bool generateSessionId = false}) {
    _sendPort.send({
      "textToSpeech": {"text": text, "generateSessionId": generateSessionId}
    });
  }

  void cleanSession() {
    _sendPort.send("cleanSession");
  }

  void wake(HotwordDetected hotWord, String wakeWordId) {
    _sendPort.send({
      "wake": {"hotWord": hotWord, "wakeWordId": wakeWordId}
    });
  }
}

class RhasspyMqttArguments {
  int port;
  String host;
  bool ssl;
  String username;
  String password;
  String siteId;
  String pemFilePath;
  int timeOutIntent;
  bool enableStream;
  RhasspyMqttArguments(
    this.host,
    this.port,
    this.ssl,
    this.username,
    this.password,
    this.siteId,
    this.pemFilePath, {
    this.timeOutIntent = 4,
    this.enableStream = false,
  });
}

class WakeWordBaseIsolate implements WakeWordBase {
  SendPort sendPort;
  WakeWordBaseIsolate({this.sendPort});
  Completer<bool> isRunningCompleter = Completer();
  Completer<bool> resumeCompleter = Completer();
  Completer<bool> pauseCompleter = Completer();
  Completer<bool> isListeningCompleter = Completer();
  Completer<List<String>> availableWakeWordDetectorCompleter = Completer();

  @override
  String name;

  @override
  Future<List<String>> get availableWakeWordDetector {
    sendPort.send({"WakeWord": "availableWakeWordDetector"});
    return availableWakeWordDetectorCompleter.future;
  }

  @override
  Future<bool> get isAvailable => throw UnimplementedError();

  @override
  Future<bool> get isRunning {
    sendPort.send({"WakeWord": "isRunning"});
    return isRunningCompleter.future;
  }

  @override
  Future<bool> pause() {
    sendPort.send({"WakeWord": "pause"});
    return pauseCompleter.future;
  }

  @override
  Future<bool> resume() {
    sendPort.send({"WakeWord": "resume"});
    return resumeCompleter.future;
  }

  @override
  Future<bool> startListening() {
    throw UnimplementedError();
  }

  @override
  Future<bool> stopListening() {
    sendPort.send({"WakeWord": "stopListening"});
  }

  @override
  Future<bool> get isListening {
    sendPort.send({"WakeWord": "stopListening"});
    return isListeningCompleter.future;
  }
}
