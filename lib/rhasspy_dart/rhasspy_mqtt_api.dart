import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/exceptions.dart';
import 'package:rhasspy_mobile_app/wake_word/wake_word_base.dart';
import './utility/rhasspy_mqtt_logger.dart';
import 'parse_messages.dart';

class RhasspyMqttApi {
  int port;
  String host;
  bool ssl;
  String username;
  String password;
  String siteId;
  @visibleForTesting
  MqttServerClient client;
  bool get isConnected {
    if (_lastPong != null &&
        (DateTime.now().difference(_lastPong)).inSeconds >
            keepAlivePeriod + 1) {
      return false;
    }
    MqttConnectionState state = client.connectionStatus.state;
    if (state == MqttConnectionState.connected) {
      return true;
    } else {
      return false;
    }
  }

  bool _intentHandled = false;
  bool _streamActive = false;
  bool _badCertificate = false;
  bool _intentNeedHandle = true;
  WakeWordBase _wakeWord;
  bool autoReconnect = true;
  int keepAlivePeriod = 15;
  Timer _keepAliveTimer;
  bool _keepAlivePong = false;
  bool _isWaitForHandleIntent = false;

  /// Becomes true when there is an active session and
  /// there is a Dialogue Manager who manages the session.
  bool isSessionManaged = false;
  Logger log = Logger();
  DialogueStartSession _lastStartSession;
  Stream<Uint8List> audioStream;
  String pemFilePath;
  SecurityContext _securityContext;
  int _countChunk = 0;
  StreamSubscription _audioStreamSubscription;
  Completer<bool> _completerConnected = Completer();
  Future<bool> get connected => _completerConnected.future;
  DateTime _lastPong;

  /// the time to wait before calling onTimeoutIntentHandle
  /// if endSession or continueSession is not received
  int timeOutIntent;
  String _currentSessionId;
  void Function(NluIntentParsed) onReceivedIntent;
  void Function(AsrTextCaptured) onReceivedText;

  /// call when audio data are available to play.
  /// if the function returns true send playFinished
  Future<bool> Function(List<int>) onReceivedAudio;
  void Function(DialogueEndSession) onReceivedEndSession;
  void Function(DialogueContinueSession) onReceivedContinueSession;
  void Function(NluIntentParsed) onTimeoutIntentHandle;
  void Function(NluIntentNotRecognized) onIntentNotRecognized;
  void Function(HotwordDetected) onHotwordDetected;
  void Function() stopRecording;
  void Function(double volume) onSetVolume;

  /// call when there is a need to record audio.
  /// if the function returns true enable asr system.
  Future<bool> Function() startRecording;
  void Function(DialogueStartSession) onStartSession;
  void Function() onConnected;
  void Function() onDisconnected;

  RhasspyMqttApi(
    this.host,
    this.port,
    this.ssl,
    this.username,
    this.password,
    this.siteId, {
    this.timeOutIntent = 4,
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
    this.pemFilePath,
    this.client,
  }) {
    if (client == null)
      client = MqttServerClient.withPort(host, siteId, port,
          maxConnectionAttempts: 1);
    client.keepAlivePeriod = keepAlivePeriod;
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;
    client.pongCallback = _pong;
    client.autoReconnect = autoReconnect;
    client.onAutoReconnect = _onAutoReconnect;
    client.onAutoReconnected = _onConnected;

    if (ssl) {
      client.secure = true;
      client.onBadCertificate = (dynamic certificate) {
        _badCertificate = true;
        return false;
      };
      _securityContext = SecurityContext.defaultContext;
      if (pemFilePath != null) {
        try {
          // set trusted certificate if this is already set throw TlsException
          _securityContext.setTrustedCertificates(pemFilePath);
        } on TlsException {}
      }

      client.securityContext = _securityContext;
    }
    final connMess = MqttConnectMessage()
        .withClientIdentifier(siteId)
        .keepAliveFor(20)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;
    //TODO try not to lose Chunk
    bool isListening = false;
    if (audioStream != null) {
      _audioStreamSubscription = audioStream.listen((dataAudio) {
        // if you do not publish some data before start listening
        // rhasspy silence will not work properly
        if (_countChunk <= 2) {
          if (isListening && isSessionManaged) _asrToggleOff();
          isListening = false;
          _publishAudioFrame(dataAudio);
          _countChunk++;
        } else {
          if (!isListening) {
            _asrToggleOn();
            isListening = true;
          }
          if ((_currentSessionId == null && !isSessionManaged) &&
              !_streamActive) {
            _checkConnection();
            _streamActive = true;
            _currentSessionId = _generateId();
            _asrStartListening(sessionId: _currentSessionId);
            _publishAudioFrame(dataAudio);
            log.log("generate new data session", Level.debug);
          } else {
            _publishAudioFrame(dataAudio);
          }
        }
      });
    }
  }

  /// Before doing any operation, you must call the function.
  /// Its return codes are 0 connection successfully,
  /// 1 connection failed, 2 incorrect credentials and
  /// 3 bad certificate.
  Future<int> connect() async {
    try {
      await client.connect(username, password).timeout(Duration(seconds: 4));
    } on HandshakeException {
      client.disconnect();
      _completerConnected.complete(false);
      _completerConnected = Completer<bool>();
      return 3;
    } catch (e) {}
    if (client.connectionStatus.state == MqttConnectionState.connected) {
      log.log("Mosquitto client connected", Level.info);
      client.updates.listen((value) => _onReceivedMessages(value));
      _completerConnected.complete(true);
      _completerConnected = Completer<bool>();
      return 0;
    } else if (client.connectionStatus.returnCode ==
            MqttConnectReturnCode.badUsernameOrPassword ||
        client.connectionStatus.returnCode ==
            MqttConnectReturnCode.notAuthorized) {
      client.disconnect();
      _completerConnected.complete(false);
      _completerConnected = Completer<bool>();
      return 2;
    } else {
      _completerConnected.complete(false);
      _completerConnected = Completer<bool>();
      if (_badCertificate) {
        _badCertificate = false;
        return 3;
      }
      return 1;
    }
  }

  void _publishString(String topic, [String data]) {
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addUTF8String(data);
    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  void _publishBytes(String topic, Uint8List data) {
    var buffer = MqttByteBuffer.fromList(data);
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addBuffer(buffer.buffer);
    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  void _asrStartListening(
      {String sessionId,
      String wakewordId,
      bool stopInSilence = true,
      bool sendAudioCaptured = true,
      List<String> intentFilter}) {
    _publishString(
        "hermes/asr/startListening",
        json.encode({
          "siteId": "$siteId",
          "sessionId": "$sessionId",
          "lang": null,
          "stopOnSilence": stopInSilence,
          "sendAudioCaptured": sendAudioCaptured,
          "wakewordId": wakewordId,
          "intentFilter": intentFilter
        }));
  }

  void _publishAudioFrame(Uint8List dataAudio) {
    _publishBytes("hermes/audioServer/$siteId/audioFrame", dataAudio);
  }

  void _asrToggleOn({String reason = "playAudio"}) {
    _publishString("hermes/asr/toggleOn",
        json.encode({"siteId": "$siteId", "reason": "$reason"}));
  }

  void _asrToggleOff({String reason = "playAudio"}) {
    _publishString("hermes/asr/toggleOff",
        json.encode({"siteId": "$siteId", "reason": "$reason"}));
  }

  void _asrStopListening({String sessionId}) {
    _publishString("hermes/asr/stopListening",
        json.encode({"siteId": "$siteId", "sessionId": "$sessionId"}));
  }

  void _dialogueSessionStarted(String sessionId,
      {String customData, String lang}) {
    _publishString(
        "hermes/dialogueManager/sessionStarted",
        json.encode({
          "sessionId": sessionId,
          "siteId": siteId,
          "customData": customData,
          "lang": lang
        }));
  }

  /// the function prepares rhasspy to listen at voice command and
  /// then send [dataAudio] to hermes/audioServer/$siteId/audioFrame.
  /// the text can be received by the function [onReceivedText].
  /// if [cleanSession] is true after the command stopListening
  /// delete the sessionId.
  void speechTotext(Uint8List dataAudio, {bool cleanSession = true}) {
    _checkConnection();
    if (_currentSessionId == null) _currentSessionId = _generateId();
    _asrToggleOn();

    if (!isSessionManaged) _asrStartListening(sessionId: _currentSessionId);
    _publishAudioFrame(dataAudio);
    _asrStopListening(sessionId: _currentSessionId);
    if (cleanSession && !isSessionManaged) {
      log.log("cleaning session", Level.debug);
      _currentSessionId = null;
    }
  }

  String _getRandomString(int length) {
    Random rnd = Random();
    const chars = 'abcdef1234567890';
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  String _generateId() {
    String randomString = _getRandomString(36);
    randomString = randomString.replaceRange(8, 9, "-");
    randomString = randomString.replaceRange(13, 14, "-");
    randomString = randomString.replaceRange(18, 19, "-");
    randomString = randomString.replaceRange(23, 24, "-");
    return randomString;
  }

  void _ttsSay(String text, {String id, String sessionId = ""}) {
    if (id == null) id = _generateId();
    print("TTS say call text: $text, id: $id, sessionId: $sessionId");
    _publishString(
        "hermes/tts/say",
        json.encode({
          "text": "$text",
          "siteId": "$siteId",
          "lang": null, // override language for TTS system
          "id": "$id",
          "sessionId": "$sessionId"
        }));
  }

  void _playFinished(String requestId, {String sessionId}) {
    _publishString("hermes/audioServer/$siteId/playFinished",
        json.encode({"id": requestId, "sessionId": sessionId ?? ""}));
  }

  void _handleToggleOff() {
    print("Play finish");
    _publishString("rhasspy/handle/toggleOff", json.encode({"siteId": siteId}));
  }

  void _handleToggleOn() {
    print("Play finish");
    _publishString("rhasspy/handle/toggleOn", json.encode({"siteId": siteId}));
  }

  void _nluQuery(String input,
      {String id,
      List<String> intentFilter,
      String sessionId,
      String wakeWordId,
      String lang}) {
    _publishString(
        "hermes/nlu/query",
        json.encode({
          "input": "$input",
          "siteId": siteId,
          "id": id,
          "intentFilter": intentFilter,
          "sessionId": sessionId,
          "wakewordId": wakeWordId,
          "lang": lang
        }));
  }

  /// send [text] to the intent recognition and
  /// after can be received by the function [onReceivedIntent].
  /// if [handle] is equally true the intent can be handle
  void textToIntent(String text, {bool handle = true}) {
    _checkConnection();
    if (isSessionManaged) return;
    if (handle) {
      if (_currentSessionId == null) _currentSessionId = _generateId();
    } else {
      _handleToggleOff();
      _intentNeedHandle = false;
      _currentSessionId = null;
    }
    _nluQuery(text, sessionId: _currentSessionId);
  }

  /// send [text] to the text to speech system and
  /// the return audio can be received by the function [onReceivedAudio].
  /// if [generateSessionId] is equally true will be generated
  /// a new session id that will be sent in the request
  void textToSpeech(String text, {bool generateSessionId = false}) {
    _checkConnection();
    if (generateSessionId) {
      if (_currentSessionId == null) _currentSessionId = _generateId();
    }
    _ttsSay(text, sessionId: _currentSessionId);
  }

  void stopListening() {
    _asrStopListening(sessionId: _currentSessionId);
    if (audioStream != null) _streamActive = false;
  }

  void cleanSession() {
    _currentSessionId = null;
    _streamActive = false;
    _countChunk = 0;
    _isWaitForHandleIntent = false;
    _lastStartSession = null;
  }

  _onReceivedMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    var lastMessage = messages[0];
    log.log("received topic: ${lastMessage.topic}", Level.debug);
    if (lastMessage.topic.contains("hermes/audioServer/$siteId/playBytes/")) {
      log.log("received audio", Level.debug);
      if (_isWaitForHandleIntent) {
        Future.delayed(Duration(milliseconds: 500), () {
          if (!_intentHandled) {
            _intentHandled = true;
            cleanSession();
            stopRecording();
          }
        });
      }

      final MqttPublishMessage recMessPayload = lastMessage.payload;
      var buffer = recMessPayload.payload.message;
      onReceivedAudio(buffer.toList()).then((value) {
        if (value) {
          _playFinished(lastMessage.topic.split("/").last);
        }
      });
    } else if (lastMessage.topic == "hermes/asr/textCaptured") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      AsrTextCaptured textCaptured = AsrTextCaptured.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (textCaptured.siteId == siteId) {
        onReceivedText(textCaptured);
        if (!isSessionManaged) {
          _asrStopListening(sessionId: _currentSessionId);
        }
      }
    } else if (lastMessage.topic == "hermes/dialogueManager/endSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueEndSession endSession = DialogueEndSession.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));

      if (endSession.sessionId == _currentSessionId) {
        _intentHandled = true;
        stopRecording();
        if (!isSessionManaged) {
          _ttsSay(endSession.text, sessionId: _currentSessionId);
        }
        onReceivedEndSession(endSession);
        _currentSessionId = null;
        _streamActive = false;
        _countChunk = 0;
      }
    } else if (lastMessage.topic == "hermes/dialogueManager/continueSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueContinueSession continueSession =
          DialogueContinueSession.fromJson(json
              .decode(Utf8Decoder().convert(recMessPayload.payload.message)));

      if (continueSession.sessionId == _currentSessionId) {
        _isWaitForHandleIntent = false;
        _intentHandled = true;
        if (!isSessionManaged) {
          _asrStopListening();
          _asrToggleOff(reason: "ttsSay");
          _ttsSay(continueSession.text, sessionId: _currentSessionId);
        }
        onReceivedContinueSession(continueSession);
        startRecording().then((value) {
          if (value && (!isSessionManaged)) {
            _asrToggleOn(reason: "ttsSay");
            _asrStartListening(sessionId: _currentSessionId);
          }
        });
      }
    } else if (lastMessage.topic == "hermes/dialogueManager/startSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueStartSession startSession = DialogueStartSession.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (startSession.siteId == siteId) {
        _lastStartSession = startSession;
        if (startSession.init.type == "action") {
          isSessionManaged = true;
          startRecording();
        }
        if (onStartSession != null) onStartSession(startSession);
      }
    } else if (lastMessage.topic == "hermes/dialogueManager/sessionStarted") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueSessionStarted startedSession = DialogueSessionStarted.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (startedSession.siteId == siteId) {
        if (_lastStartSession != null) {
          if (_lastStartSession.init.type == "action") {
            _currentSessionId = startedSession.sessionId;
          }
        } else {
          // Wake Word detected
          _currentSessionId = startedSession.sessionId;
          log.log("SessionId is $_currentSessionId", Level.debug);
          isSessionManaged = true;
          startRecording();
        }
      }
    } else if (lastMessage.topic == "hermes/dialogueManager/sessionEnded") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueSessionEnded sessionEnded = DialogueSessionEnded.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (sessionEnded.siteId == siteId) {
        stopRecording();
        isSessionManaged = false;
      }
    } else if (lastMessage.topic == "hermes/nlu/intentParsed") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      NluIntentParsed intentParsed = NluIntentParsed.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (intentParsed.siteId == siteId) {
        onReceivedIntent(intentParsed);
        if (!_intentNeedHandle) {
          _handleToggleOn();
          _intentNeedHandle = true;
          stopRecording();
        }
        // if the intent is to be managed
        if (intentParsed.sessionId != null && _intentNeedHandle) {
          _isWaitForHandleIntent = true;
          log.log("Waiting for intent to be handle", Level.debug);
          Future.delayed(Duration(seconds: timeOutIntent), () {
            if (_intentHandled) {
              /// intent handled correctly
              _intentHandled = false;
              _isWaitForHandleIntent = false;
            } else {
              _currentSessionId = null;
              _streamActive = false;
              _countChunk = 0;
              stopRecording();
              onTimeoutIntentHandle(intentParsed);
            }
          });
        }
      }
    } else if (lastMessage.topic == "hermes/nlu/intentNotRecognized") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      NluIntentNotRecognized intentNotRecognized =
          NluIntentNotRecognized.fromJson(json
              .decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (intentNotRecognized.siteId == siteId) {
        onIntentNotRecognized(intentNotRecognized);
        stopRecording();
      }
    } else if (lastMessage.topic
        .contains(RegExp(r"^hermes/hotword/([^/]+)/detected$"))) {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HotwordDetected hotwordDetected = HotwordDetected.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (hotwordDetected.siteId == siteId) {
        _lastStartSession = null;
        onHotwordDetected(hotwordDetected);
      }
    } else if (lastMessage.topic == "hermes/hotword/toggleOn") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HotwordToggle hotwordToggleOn = HotwordToggle.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (hotwordToggleOn.siteId == siteId) {
        if (_wakeWord != null) {
          _wakeWord.isRunning.then((value) {
            if (value) _wakeWord.resume();
          });
        }
      }
    } else if (lastMessage.topic == "hermes/hotword/toggleOff") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HotwordToggle hotwordToggleOff = HotwordToggle.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (hotwordToggleOff.siteId == siteId) {
        if (_wakeWord != null) {
          _wakeWord.isRunning.then((value) {
            if (value) _wakeWord.pause();
          });
        }
      }
    } else if (lastMessage.topic == "rhasspy/audioServer/setVolume") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      AudioSetVolume audioVolume = AudioSetVolume.fromJson(
          json.decode(Utf8Decoder().convert(recMessPayload.payload.message)));
      if (audioVolume.siteId == siteId) {
        if (onSetVolume != null) onSetVolume(audioVolume.volume);
      }
    }
  }

  void wake(HotwordDetected hotWord, String wakeWordId) {
    if (hotWord.siteId == null) hotWord.siteId = siteId;

    _publishString(
        "hermes/hotword/$wakeWordId/detected", json.encode(hotWord.toJson()));
  }

  void enableWakeWord(WakeWordBase wakeWord) {
    _wakeWord = wakeWord;
  }

  /// disconnect form the broker and
  /// discards any resources used by the object.
  /// After this is called, the
  /// object is not in a usable state.
  void dispose() async {
    if (_audioStreamSubscription != null)
      await _audioStreamSubscription.cancel();
    if (ssl) _securityContext = null;
    client.disconnect();
    if (_keepAliveTimer != null) _keepAliveTimer.cancel();
    client = null;
  }

  void _pong() {
    _keepAlivePong = true;
    _lastPong = DateTime.now();
    log.log("keepAlive", Level.debug);
  }

  void _onConnected() {
    _lastPong = DateTime.now();
    if (!isConnected) return;
    log.log("connected", Level.debug);
    if (_keepAliveTimer != null && _keepAliveTimer.isActive)
      _keepAliveTimer.cancel();
    _keepAliveTimer =
        Timer.periodic(Duration(seconds: keepAlivePeriod + 1), (Timer t) {
      if (!_keepAlivePong) {
        log.log("connected", Level.debug);
        if (client.connectionStatus.state == MqttConnectionState.connecting) {
          return;
        }
        connect().then((value) {
          if (value != 0) {
            _keepAliveTimer.cancel();
          }
        });
      }
      _keepAlivePong = false;
    });
    client.subscribe(
        "hermes/audioServer/${siteId.trim()}/playBytes/#", MqttQos.atLeastOnce);
    client.subscribe("hermes/asr/textCaptured", MqttQos.atLeastOnce);
    client.subscribe("hermes/dialogueManager/endSession", MqttQos.atLeastOnce);
    client.subscribe("hermes/nlu/intentParsed", MqttQos.atLeastOnce);
    client.subscribe(
        "hermes/dialogueManager/continueSession", MqttQos.atLeastOnce);
    client.subscribe(
        "hermes/dialogueManager/startSession", MqttQos.atLeastOnce);
    client.subscribe(
        "hermes/dialogueManager/sessionStarted", MqttQos.atLeastOnce);
    client.subscribe(
        "hermes/dialogueManager/sessionEnded", MqttQos.atLeastOnce);
    client.subscribe("hermes/nlu/intentNotRecognized", MqttQos.atLeastOnce);
    client.subscribe("rhasspy/audioServer/setVolume", MqttQos.atLeastOnce);
    client.subscribe("hermes/hotword/#", MqttQos.atLeastOnce);
    onConnected();
  }

  void _onAutoReconnect() {
    _onDisconnected();
  }

  void _checkConnection() async {
    if (!isConnected) {
      if (client.connectionStatus.state == MqttConnectionState.connecting) {
        await Future.delayed(Duration(seconds: 1));
        if (isConnected) {
          return;
        }
      }
      if (autoReconnect) {
        client.doAutoReconnect();
        await Future.delayed(Duration(seconds: 1));
        if (!isConnected) {
          log.log(
              "not connected ${client.connectionStatus.state}", Level.error);
          throw NotConnected();
        }
      } else {
        if (await connect() != 0) {
          log.log(
              "not connected ${client.connectionStatus.state}", Level.error);
          throw NotConnected();
        }
      }
    }
  }

  void _onDisconnected() {
    log.log(
        "disconnected, state ${client.connectionStatus.state}", Level.warning);
    onDisconnected();
  }
}
