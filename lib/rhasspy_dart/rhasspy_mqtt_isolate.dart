import 'dart:typed_data';

import 'dart:async';
import 'dart:isolate';

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
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  int lastConnectionCode;
  WakeWordBase _wakeWordBase;

  bool isSessionStarted = false;
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
    errorPort.listen(print);
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
          print(startRecording);
          startRecording().then((value) {
            _sendPort.send({"startRecording": value});
          });
          break;
        case "onConnected":
          _isConnected = true;
          _connectCompleter.complete(0);
          _connectCompleter = Completer<int>();
          if (onConnected != null) onConnected();
          break;
        case "onDisconnected":
          _isConnected = false;
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
      // print("message is a map ${message.toString()}");
      if (message.containsKey("connectCode")) {
        print("connected code: ${message["connectCode"]}");
        _connectCompleter.complete(message["connectCode"]);
        _connectCompleter = Completer<int>();
        lastConnectionCode = message["connectCode"];
      }
      if (message.containsKey("onReceivedAudio")) {
        onReceivedAudio(message["onReceivedAudio"])
            .then((value) => _sendPort.send({"onReceivedAudio": value}));
      }
      if (message.containsKey("onReceivedText")) {
        onReceivedText(message["onReceivedText"]);
      }
      if (message.containsKey("onReceivedIntent")) {
        onReceivedIntent(message["onReceivedIntent"]);
      }
      if (message.containsKey("onReceivedEndSession")) {
        onReceivedEndSession(message["onReceivedEndSession"]);
      }
      if (message.containsKey("onReceivedContinueSession")) {
        onReceivedContinueSession(message["onReceivedContinueSession"]);
      }
      if (message.containsKey("onTimeoutIntentHandle")) {
        onTimeoutIntentHandle(message["onTimeoutIntentHandle"]);
      }
      if (message.containsKey("onStartSession")) {
        if (onStartSession != null) onStartSession(message["onStartSession"]);
      }
      if (message.containsKey("isSessionStarted")) {
        isSessionStarted = message["isSessionStarted"];
      }
      if (message.containsKey("onIntentNotRecognized")) {
        onIntentNotRecognized(message["onIntentNotRecognized"]);
      }
      if (message.containsKey("onHotwordDetected")) {
        onHotwordDetected(message["onHotwordDetected"]);
      }
      if (message.containsKey("WakeWord")) {
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
        }
      }
    }
  }

  static void _isolateEntry(dynamic message) async {
    SendPort sendPort;
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
          rhasspyMqtt = RhasspyMqttApi(message.host, message.port, message.ssl,
              message.username, message.password, message.siteId,
              timeOutIntent: message.timeOutIntent,
              pemFilePath: message.pemFilePath,
              audioStream: audioStream.stream, onReceivedAudio: (value) async {
            print("onReceivedAudio isolate");
            sendPort.send({"onReceivedAudio": value});
            return _receivedAudio.future;
          }, onReceivedText: (textCapture) {
            sendPort.send({"onReceivedText": textCapture});
          }, onReceivedIntent: (intentParsed) {
            sendPort.send({"onReceivedIntent": intentParsed});
          }, onReceivedEndSession: (endSession) {
            sendPort.send({"onReceivedEndSession": endSession});
            sendPort.send({"isSessionStarted": false});
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
            sendPort.send({"isSessionStarted": rhasspyMqtt.isSessionStarted});
          }, stopRecording: () {
            sendPort.send("stopRecording");
          }, startRecording: () {
            sendPort.send("startRecording");
            return _startRecordingCompleter.future;
          }, onIntentNotRecognized: (intent) {
            sendPort.send({"onIntentNotRecognized": intent});
          });
        }
        if (message is String) {
          switch (message) {
            case "connect":
              int result = await rhasspyMqtt.connect();
              sendPort.send({"connectCode": result});
              break;
            case "stoplistening":
              rhasspyMqtt.stoplistening();
              break;
            case "cleanSession":
              rhasspyMqtt.cleanSession();
              break;
            case "enableWakeWord":
              _wakeWordIsolate = WakeWordBaseIsolate(sendPort: sendPort);
              rhasspyMqtt.enableWakeWord(_wakeWordIsolate);
              break;

            default:
              throw UnimplementedError(
                  "Undefined behavior for message: $message");
          }
        }
        if (message is Map<String, dynamic>) {
          // debugPrint("isolate recevied map: ${message.toString()}");
          if (message.containsKey("onReceivedAudio")) {
            _receivedAudio.complete(message["onReceivedAudio"]);
            _receivedAudio = Completer();
          }
          if (message.containsKey("speechTotext")) {
            rhasspyMqtt.speechTotext(message["speechTotext"]["dataAudio"],
                cleanSession: message["speechTotext"]["cleanSession"]);
          }
          if (message.containsKey("textToIntent")) {
            rhasspyMqtt.textToIntent(message["textToIntent"]["text"],
                handle: message["textToIntent"]["handle"]);
          }
          if (message.containsKey("textToSpeech")) {
            rhasspyMqtt.textToSpeech(message["textToSpeech"]["text"],
                generateSessionId: message["textToSpeech"]
                    ["generateSessionId"]);
          }
          if (message.containsKey("enableWakeWord")) {
            rhasspyMqtt.enableWakeWord(message["enableWakeWord"]);
          }
          if (message.containsKey("startRecording")) {
            _startRecordingCompleter.complete(message["startRecording"]);
            _startRecordingCompleter = Completer();
          }
          if (message.containsKey("isRunning")) {
            _wakeWordIsolate.isRunningCompleter.complete(message["isRunning"]);
            _wakeWordIsolate.isRunningCompleter = Completer();
          }
          if (message.containsKey("availableWakeWordDetector")) {
            _wakeWordIsolate.availableWakeWordDetectorCompleter
                .complete(message["availableWakeWordDetector"]);
            _wakeWordIsolate.availableWakeWordDetectorCompleter = Completer();
          }
        }
        if (message is Uint8List) {
          audioStream.add(message);
        }
      },
    );

    if (message is SendPort) {
      sendPort = message;
      sendPort.send(receivePort.sendPort);
      return;
    }
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
  void stoplistening() {
    _sendPort.send("stoplistening");
  }

  @override
  void textToIntent(String text, {bool handle = true}) {
    _sendPort.send({
      "textToIntent": {"text": text, "handle": handle}
    });
  }

  @override
  void textToSpeech(String text, {bool generateSessionId = false}) {
    print(generateSessionId);
    _sendPort.send({
      "textToSpeech": {"text": text, "generateSessionId": generateSessionId}
    });
  }

  void cleanSession() {
    _sendPort.send("cleanSession");
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
