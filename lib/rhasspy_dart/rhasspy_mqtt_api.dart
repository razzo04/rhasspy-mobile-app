import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

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
    MqttConnectionState state = client.connectionStatus.state;
    if (state == MqttConnectionState.disconnected ||
        state == MqttConnectionState.disconnecting) {
      return false;
    } else {
      return true;
    }
  }

  bool _intentHandled = false;
  bool _streamActive = false;

  /// becomes true when there is an active session.
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
  void Function(NluIntentParsed) onReceivedIntent;
  void Function(AsrTextCaptured) onReceivedText;

  /// call when audio data are available to play.
  /// if the function returns true send playFinished
  Future<bool> Function(List<int>) onReceivedAudio;
  void Function(DialogueEndSession) onReceivedEndSession;
  void Function(DialogueContinueSession) onReceivedContinueSession;
  void Function(NluIntentParsed) onTimeoutIntentHandle;
  void Function() stopRecording;

  /// call when there is a need to record audio.
  /// if the function returns true enable asr system.
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
    client =
        MqttServerClient.withPort(host, siteId, port, maxConnectionAttempts: 1);
    client.keepAlivePeriod = 20;
    client.onConnected = _onConnected;
    client.onDisconnected = onDisconnected;
    client.pongCallback = _pong;
    client.autoReconnect = true;
    if (ssl) {
      client.secure = true;
      client.onBadCertificate = (dynamic certificate) {
        print("Bad certificate");
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
        print("Received");
        // if you do not publish some data before start listening
        // rhasspy silence will not work properly
        if (_countChunk <= 2) {
          if (isListening && isSessionStarted) _asrToggleOff();
          isListening = false;
          _publishAudioFrame(dataAudio);
          _countChunk++;
        } else {
          if (!isListening) {
            _asrToggleOn();
            isListening = true;
          }
          if ((_currentSessionId == null && !isSessionStarted) &&
              !_streamActive) {
            _streamActive = true;
            _currentSessionId = _generateId();
            _asrStartListening(sessionId: _currentSessionId);
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
      await client.connect(username, password).timeout(Duration(seconds: 4));
    } on HandshakeException {
      client.disconnect();
      _completerConnected.complete(false);
      return 3;
    } catch (e) {}
    if (client.connectionStatus.state == MqttConnectionState.connected) {
      print('Mosquitto client connected');
      _completerConnected.complete(true);
      return 0;
    } else if (client.connectionStatus.returnCode ==
            MqttConnectReturnCode.badUsernameOrPassword ||
        client.connectionStatus.returnCode ==
            MqttConnectReturnCode.notAuthorized) {
      client.disconnect();
      _completerConnected.complete(false);
      return 2;
    } else {
      client.disconnect();
      _completerConnected.complete(false);
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
    if (_currentSessionId == null) _currentSessionId = _generateId();
    _asrToggleOn();
    _asrStartListening(sessionId: _currentSessionId);
    _publishAudioFrame(dataAudio);
    _asrStopListening(sessionId: _currentSessionId);
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
    print("Play finish");
    _publishString("hermes/audioServer/$siteId/playFinished",
        json.encode({"id": requestId, "sessionId": sessionId ?? ""}));
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
    if (handle) {
      if (_currentSessionId == null) _currentSessionId = _generateId();
    } else {
      _currentSessionId = null;
    }
    _nluQuery(text, sessionId: _currentSessionId);
  }

  /// send [text] to the text to speech system and
  /// the return audio can be received by the function [onReceivedAudio].
  /// if [generateSessionId] is equally true will be generated
  /// a new session id that will be sent in the request
  void textToSpeech(String text, {bool generateSessionId = false}) {
    if (generateSessionId) {
      if (_currentSessionId == null) _currentSessionId = _generateId();
    }
    _ttsSay(text, sessionId: _currentSessionId);
  }

  void stoplistening() {
    _asrStopListening(sessionId: _currentSessionId);
    if (audioStream != null) _streamActive = false;
  }

  _onReceivedMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    var lastMessage = messages[0];
    print("topic: ${lastMessage.topic}");
    if (lastMessage.topic.contains("hermes/audioServer/$siteId/playBytes/")) {
      print("recivied audio");
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      var buffer = recMessPayload.payload.message;
      onReceivedAudio(buffer.toList()).then((value) {
        if (value) {
          _playFinished(lastMessage.topic.split("/").last);
        }
      });
    }
    if (lastMessage.topic == "hermes/asr/textCaptured") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      AsrTextCaptured textCaptured = AsrTextCaptured.fromJson(json.decode(
          MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (textCaptured.siteId == siteId) {
        onReceivedText(textCaptured);
        if (!isSessionStarted) {
          // stopRecording();
          _asrStopListening(sessionId: _currentSessionId);
        }
      }
    }
    if (lastMessage.topic == "hermes/dialogueManager/endSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueEndSession endSession = DialogueEndSession.fromJson(json.decode(
          MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));

      if (endSession.siteId == siteId) {
        _intentHandled = true;
        stopRecording();
        if (!isSessionStarted) {
          _ttsSay(endSession.text, sessionId: _currentSessionId);
        }
        onReceivedEndSession(endSession);
        _currentSessionId = null;
        _streamActive = false;
        _countChunk = 0;
      }
    }
    if (lastMessage.topic == "hermes/dialogueManager/continueSession") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      DialogueContinueSession continueSession =
          DialogueContinueSession.fromJson(json.decode(
              MqttPublishPayload.bytesToStringAsString(
                  recMessPayload.payload.message)));

      if (continueSession.siteId == siteId) {
        _intentHandled = true;
        if (!isSessionStarted) {
          _asrStopListening();
          _ttsSay(continueSession.text, sessionId: _currentSessionId);
        }
        onReceivedContinueSession(continueSession);
        startRecording().then((value) {
          if (value && (!isSessionStarted)) {
            _asrToggleOn();
            _asrStartListening(sessionId: _currentSessionId);
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
        stopRecording();
        isSessionStarted = false;
      }
    }
    if (lastMessage.topic == "hermes/nlu/intentParsed") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      NluIntentParsed intentParsed = NluIntentParsed.fromJson(json.decode(
          MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if (intentParsed.siteId == siteId) {
        onReceivedIntent(intentParsed);

        // if the intent is to be managed
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

  /// disconnect form the broker and
  /// discards any resources used by the object.
  /// After this is called, the
  /// object is not in a usable state.
  void dispose() async {
    if (_audioStreamSubscription != null)
      await _audioStreamSubscription.cancel();
    if (ssl) _securityContext = null;
    client.disconnect();
    client = null;
  }

  void _pong() {
    print("pong");
  }

  void _onConnected() {
    client.updates.listen((value) => _onReceivedMessages(value));
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
    onConnected();
  }
}
