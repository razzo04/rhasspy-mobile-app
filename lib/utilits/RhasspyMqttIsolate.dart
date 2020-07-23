import 'dart:typed_data';

import 'dart:async';
import 'dart:isolate';
import 'package:rhasspy_mobile_app/utilits/RhasspyMqttApi.dart';

import 'JsonHelperClass.dart';

class RhasspyMqttIsolate implements RhasspyMqttApi {
  int port;
  String host;
  bool ssl;
  String username;
  String password;
  String siteId;
  Stream<Uint8List> audioStream;
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  int lastConnectionCode;

  bool isSessionStarted = false;
  String pemFilePath;
  SendPort _sendPort;
  Isolate _isolate;
  Completer<int> _connectCompleter = Completer<int>();
  final _isolateReady = Completer<void>();
  int timeOutIntent;
  void Function(HermesNluIntentParsed) onReceivedIntent;
  void Function(HermesTextCaptured) onReceivedText;

  Future<bool> Function(List<int>) onReceivedAudio;
  void Function(HermesEndSession) onReceivedEndSession;
  void Function(HermesContinueSession) onReceivedContinueSession;
  void Function(HermesNluIntentParsed) onTimeoutIntentHandle;
  void Function() stopRecording;
  Future<bool> Function() startRecording;
  void Function(DialogueStartSession) onStartSession;
  void Function() onConnected;
  void Function() onDisconnected;

  @override
  Future<bool> get connected async {
    if (await _connectCompleter.future == 0) {
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
      this.onConnected,
      this.onDisconnected,
      this.onStartSession,
      this.startRecording,
      this.audioStream,
      this.stopRecording,
      this.pemFilePath}) {
    _init();
    _initializeMqtt();
    audioStream?.listen((event) {
      _sendPort.send(event);
    });
  }
  void dispose() {
    _isolate.kill();
  }

  void subscribeCallback({
    void Function(HermesNluIntentParsed) onReceivedIntent,
    void Function(HermesTextCaptured) onReceivedText,
    Future<bool> Function(List<int>) onReceivedAudio,
    void Function(HermesEndSession) onReceivedEndSession,
    void Function(HermesContinueSession) onReceivedContinueSession,
    void Function(HermesNluIntentParsed) onTimeoutIntentHandle,
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
    await _isolateReady.future;
    _sendPort.send("connect");
    return _connectCompleter.future;
  }

  Future<void> _init() async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    errorPort.listen(print);
    receivePort.listen(_handleMessage);
    _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort,
        onError: errorPort.sendPort, debugName: "Mqtt", errorsAreFatal: false);
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

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      _isolateReady.complete();
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
          if (onConnected != null) onConnected();
          break;
        case "onDisconnected":
          _isConnected = false;
          if (onDisconnected != null) onDisconnected();
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
    }
  }

  static void _isolateEntry(dynamic message) async {
    SendPort sendPort;
    RhasspyMqttApi rhasspyMqtt;
    final receivePort = ReceivePort();
    Completer<bool> _receivedAudio = Completer<bool>();
    Completer<bool> _startRecordingCompleter = Completer<bool>();
    StreamController<Uint8List> audioStream = StreamController();

    receivePort.listen(
      (dynamic message) async {
        // print("Isolate message: is a instance of ${message.runtimeType}");
        if (message is RhasspyMqttArguments) {
          if (rhasspyMqtt != null) {
            rhasspyMqtt.dispose();
            audioStream.close();
            audioStream = StreamController();
          }
          rhasspyMqtt = RhasspyMqttApi(
            message.host,
            message.port,
            message.ssl,
            message.username,
            message.password,
            message.siteId,
            timeOutIntent: message.timeOutIntent,
            pemFilePath: message.pemFilePath,
            audioStream: audioStream.stream,
            onReceivedAudio: (value) async {
              print("onReceivedAudio isolate");
              sendPort.send({"onReceivedAudio": value});
              return _receivedAudio.future;
            },
            onReceivedText: (textCapture) {
              sendPort.send({"onReceivedText": textCapture});
            },
            onReceivedIntent: (intentParsed) {
              sendPort.send({"onReceivedIntent": intentParsed});
            },
            onReceivedEndSession: (endSession) {
              sendPort.send({"onReceivedEndSession": endSession});
              sendPort.send({"isSessionStarted": false});
            },
            onReceivedContinueSession: (continueSession) {
              sendPort.send({"onReceivedContinueSession": continueSession});
            },
            onTimeoutIntentHandle: (intentParsed) {
              sendPort.send({"onTimeoutIntentHandle": intentParsed});
            },
            onConnected: () {
              sendPort.send("onConnected");
            },
            onDisconnected: () {
              sendPort.send("onDisconnected");
            },
            onStartSession: (startSession) {
              sendPort.send({"onStartSession": startSession});
              //TODO get isSessionStarted directly
              sendPort.send({"isSessionStarted": rhasspyMqtt.isSessionStarted});
            },
            stopRecording: () {
              sendPort.send("stopRecording");
            },
            startRecording: () {
              sendPort.send("startRecording");
              return _startRecordingCompleter.future;
            },
          );
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
          if (message.containsKey("startRecording")) {
            _startRecordingCompleter.complete(message["startRecording"]);
            _startRecordingCompleter = Completer();
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
