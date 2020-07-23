import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:rhasspy_mobile_app/utilits/JsonHelperClass.dart';

class RhasspyMqttApi {
  int port;
  String host;
  bool ssl;
  String username;
  String password;
  String siteId;
  MqttServerClient _client;
  bool get isConnected {
    MqttConnectionState state = _client.connectionStatus.state;
    if (state == MqttConnectionState.disconnected ||
        state == MqttConnectionState.disconnecting) {
      return false;
    } else {
      return true;
    }
  }

  bool _intentHandled = false;
  bool _streamActive = false;
  bool isSessionStarted = false;
  DialogueStartSession _lastStartSession;
  Stream<Uint8List> audioStream;
  String pemFilePath;
  SecurityContext _securityContext;
  int _countChunk = 0;
  StreamSubscription _audioStreamSubscription;
  Completer<bool> _completerConnected = Completer();
  Future<bool> get connected => _completerConnected.future;

  /// the time to wait before calling onTimeoutIntentHandle
  /// if endSession or continueSession is not received
  int timeOutIntent;
  String _currentSessionId;
  void Function(HermesNluIntentParsed) onReceivedIntent;
  void Function(HermesTextCaptured) onReceivedText;

  /// call when audio data are available to play.
  /// if the function returns true send playFinished
  Future<bool> Function(List<int>) onReceivedAudio;
  void Function(HermesEndSession) onReceivedEndSession;
  void Function(HermesContinueSession) onReceivedContinueSession;
  void Function(HermesNluIntentParsed) onTimeoutIntentHandle;
  void Function() stopRecording;
  Future<bool> Function() startRecording;
  void Function(DialogueStartSession) onStartSession;
  void Function() onConnected;
  void Function() onDisconnected;

  RhasspyMqttApi(
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
    _client =
        MqttServerClient.withPort(host, siteId, port, maxConnectionAttempts: 1);
    _client.keepAlivePeriod = 20;
    _client.onConnected = onConnected;
    _client.onDisconnected = onDisconnected;
    _client.pongCallback = _pong;
    if (ssl) {
      _client.secure = true;
      _client.onBadCertificate = (dynamic certificate) {
        print("Bad certificate");
        return false;
      };
      _securityContext = SecurityContext.defaultContext;
      if (pemFilePath != null) {
        try {
          _securityContext.setTrustedCertificates(pemFilePath);
        } on TlsException {}
      }

      _client.securityContext = _securityContext;
    }
    final connMess = MqttConnectMessage()
        .withClientIdentifier(siteId)
        .keepAliveFor(20)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client.connectionMessage = connMess;
    //TODO try not to lose Chunk
    bool isListening = false;
    if (audioStream != null) {
      _audioStreamSubscription = audioStream.listen((dataAudio) {
        print("Recivied");
        // if you do not publish some data before start listening
        // rhasspy silence will not work properly
        if (_countChunk <= 2) {
          if (isListening && isSessionStarted) _hermesAsrToggleOff();
          isListening = false;
          _publishAudioFrame(dataAudio);
          _countChunk++;
        } else {
          if (!isListening) {
            _hermesAsrToggleOn();
            isListening = true;
          }
          if ((_currentSessionId == null && !isSessionStarted) &&
              !_streamActive) {
            _streamActive = true;
            _currentSessionId = _generateId();
            _hermesAsrStartListening(sessionId: _currentSessionId);
            _publishAudioFrame(dataAudio);
            print("generate new data session");
          } else {
            _publishAudioFrame(dataAudio);
          }
        }
      });
    }
  }

  /// Before doing any operation, you must call the function.
  /// Its return codes are 0 connection successfully made
  /// 1 connection failed, 2 incorrect credentials and
  /// 3 bad certificate.
  Future<int> connect() async {
    try {
      await _client.connect(username, password).timeout(Duration(seconds: 4));
    } on HandshakeException {
      _client.disconnect();
      _completerConnected.complete(false);
      return 3;
    } catch (e) {}
    if (_client.connectionStatus.state == MqttConnectionState.connected) {
      print('Mosquitto client connected');
      _completerConnected.complete(true);
      _client.updates.listen((value) => _onReciviedMessages(value));
      _client.subscribe("hermes/audioServer/${siteId.trim()}/playBytes/#",
          MqttQos.atLeastOnce);
      _client.subscribe("hermes/asr/textCaptured", MqttQos.atLeastOnce);
      _client.subscribe(
          "hermes/dialogueManager/endSession", MqttQos.atLeastOnce);
      _client.subscribe("hermes/nlu/intentParsed", MqttQos.atLeastOnce);
      _client.subscribe(
          "hermes/dialogueManager/continueSession", MqttQos.atLeastOnce);
      _client.subscribe(
          "hermes/dialogueManager/startSession", MqttQos.atLeastOnce);
      _client.subscribe(
          "hermes/dialogueManager/sessionStarted", MqttQos.atLeastOnce);
      _client.subscribe(
          "hermes/dialogueManager/sessionEnded", MqttQos.atLeastOnce);
      return 0;
    } else if (_client.connectionStatus.returnCode ==
            MqttConnectReturnCode.badUsernameOrPassword ||
        _client.connectionStatus.returnCode ==
            MqttConnectReturnCode.notAuthorized) {
      _client.disconnect();
      _completerConnected.complete(false);
      return 2;
    } else {
      _client.disconnect();
      _completerConnected.complete(false);
      return 1;
    }
  }

  void _publishString(String topic, [String data]) {
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addUTF8String(data);
    _client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  void _publishBytes(String topic, Uint8List data) {
    var buffer = MqttByteBuffer.fromList(data);
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addBuffer(buffer.buffer);
    _client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  void _hermesAsrStartListening(
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

  void _hermesAsrToggleOn({String reason = "playAudio"}) {
    _publishString("hermes/asr/toggleOn",
        json.encode({"siteId": "$siteId", "reason": "$reason"}));
  }

  void _hermesAsrToggleOff({String reason = "playAudio"}) {
    _publishString("hermes/asr/toggleOff",
        json.encode({"siteId": "$siteId", "reason": "$reason"}));
  }

  void _hermesAsrStopListening({String sessionId}) {
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

  /// the function prepare rhasspy to listen at voice command and
  /// then send [dataAudio] to hermes/audioServer/$siteId/audioFrame.
  /// if [cleanSession] is true after the command stopListening
  /// delete the sessionId.
  void speechTotext(Uint8List dataAudio, {bool cleanSession = true}) {
    if (_currentSessionId == null) _currentSessionId = _generateId();
    _hermesAsrToggleOn();
    _hermesAsrStartListening(sessionId: _currentSessionId);
    _publishAudioFrame(dataAudio);
    _hermesAsrStopListening(sessionId: _currentSessionId);
    if (cleanSession) {
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
    debugPrint("generate id");
    String randomString = _getRandomString(36);
    randomString = randomString.replaceRange(8, 9, "-");
    randomString = randomString.replaceRange(13, 14, "-");
    randomString = randomString.replaceRange(18, 19, "-");
    randomString = randomString.replaceRange(23, 24, "-");
    return randomString;
  }

  void _hermesTtsSay(String text, {String id, String sessionId = ""}) {
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

  void _hermesPlayFinished(String requestId, {String sessionId}) {
    print("Play finish");
    _publishString("hermes/audioServer/$siteId/playFinished",
        json.encode({"id": requestId, "sessionId": sessionId ?? ""}));
  }

  void _hermesNluQuery(String input,
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

  void textToIntent(String text, {bool handle = true}) {
    if (handle) {
      if (_currentSessionId == null) _currentSessionId = _generateId();
    } else {
      _currentSessionId = null;
    }
    _hermesNluQuery(text, sessionId: _currentSessionId);
  }

  void textToSpeech(String text, {bool generateSessionId = false}) {
    if (generateSessionId) {
      if (_currentSessionId == null) _currentSessionId = _generateId();
    }
    _hermesTtsSay(text, sessionId: _currentSessionId);
  }

  void stoplistening() {
    _hermesAsrStopListening(sessionId: _currentSessionId);
    if (audioStream != null) _streamActive = false;
  }

  _onReciviedMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    var lastMessage = messages[0];
    print("topic: ${lastMessage.topic}");
    if (lastMessage.topic.contains("hermes/audioServer/$siteId/playBytes/")) {
      print("recivied audio");
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      var buffer = recMessPayload.payload.message;
      onReceivedAudio(buffer.toList()).then((value) {
        if (value) {
          _hermesPlayFinished(lastMessage.topic.split("/").last);
        }
      });
    }
    if (lastMessage.topic == "hermes/asr/textCaptured") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesTextCaptured textCaptured = HermesTextCaptured.fromJson(json.decode(
          MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (textCaptured.siteId == siteId) {
        onReceivedText(textCaptured);
        // if (_streamActive && !isSessionStarted) {
        //   stopRecording();
        // }
      }
    }
    if (lastMessage.topic == "hermes/dialogueManager/endSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesEndSession endSession = HermesEndSession.fromJson(json.decode(
          MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));

      if (endSession.siteId == siteId) {
        _intentHandled = true;

        if (!isSessionStarted) {
          _hermesTtsSay(endSession.text, sessionId: _currentSessionId);
          stopRecording();
        }
        onReceivedEndSession(endSession);
        _currentSessionId = null;
        _streamActive = false;
        _countChunk = 0;
      }
    }
    if (lastMessage.topic == "hermes/dialogueManager/continueSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesContinueSession continueSession = HermesContinueSession.fromJson(
          json.decode(MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));

      if (continueSession.siteId == siteId) {
        _intentHandled = true;
        if (!isSessionStarted) {
          _hermesTtsSay(continueSession.text, sessionId: _currentSessionId);
          _hermesAsrToggleOff();
        }
        onReceivedContinueSession(continueSession);
        startRecording().then((value) {
          if (value && (!isSessionStarted)) {
            _hermesAsrToggleOn();
            _hermesAsrStartListening(sessionId: _currentSessionId);
          }
        });
      }
    }
    if (lastMessage.topic == "hermes/dialogueManager/startSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueStartSession startSession = DialogueStartSession.fromJson(
          json.decode(MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (startSession.siteId == siteId) {
        _lastStartSession = startSession;
        if (startSession.init.type == "action") {
          isSessionStarted = true;
          startRecording();
        }
        if (onStartSession != null) onStartSession(startSession);
      }
    }
    if (lastMessage.topic == "hermes/dialogueManager/sessionStarted") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueSessionStarted startedSession = DialogueSessionStarted.fromJson(
          json.decode(MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (startedSession.siteId == siteId) {
        if (_lastStartSession.init.type == "action") {
          _currentSessionId = startedSession.sessionId;
        }
      }
    }
    if (lastMessage.topic == "hermes/dialogueManager/sessionEnded") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueSessionEnded sessionEnded = DialogueSessionEnded.fromJson(
          json.decode(MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (sessionEnded.siteId == siteId) {
        isSessionStarted = false;
        stopRecording();
      }
    }
    if (lastMessage.topic == "hermes/nlu/intentParsed") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesNluIntentParsed intentParsed = HermesNluIntentParsed.fromJson(
          json.decode(MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (intentParsed.siteId == siteId) {
        onReceivedIntent(intentParsed);

        /// if the intent is to be managed
        if (intentParsed.sessionId != null) {
          Future.delayed(Duration(seconds: timeOutIntent), () {
            if (_intentHandled) {
              /// intent handled correctly
              _intentHandled = false;
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
    }
  }

  void dispose() async {
    if (_audioStreamSubscription != null)
      await _audioStreamSubscription.cancel();
    if (ssl) _securityContext = null;
    _client.disconnect();
  }

  void _pong() {
    print("pong");
  }
}
