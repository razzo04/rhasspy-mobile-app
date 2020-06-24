import 'dart:convert';
import 'dart:typed_data';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:rhasspy_mobile_app/utilits/HermesTextCaptured.dart';

class RhasspyMqttApi {
  int port;
  String host;
  bool ssl;
  String username;
  String password;
  String siteId;
  MqttServerClient client;
  bool isConnected = false;
  Function(String) onReceivedIntent;
  Function(HermesTextCaptured) onReceivedText;
  Function(List<int>) onReceivedAudio;

  RhasspyMqttApi(
      this.host, this.port, this.ssl, this.username, this.password, this.siteId,
      {this.onReceivedIntent, this.onReceivedText, this.onReceivedAudio}) {
    client = MqttServerClient.withPort(host, siteId, port);
    client.keepAlivePeriod = 20;
    // client.autoReconnect = true;
    client.onConnected = onConnected;
    client.onSubscribed = onSubscribed;
    client.onDisconnected = onDisconnected;
    client.pongCallback = pong;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(siteId)
        .keepAliveFor(20)
        .startClean() 
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;
  }

  /// Before doing any operation, you must call the service.
  /// Its return codes are 0 connection successfully made
  /// 1 connection failed and 2 incorrect credentials.
  Future<int> connect() async {
    try {
      await client.connect(username, password);

    }on Exception {
      isConnected = false;
      client.disconnect();
      return 1;
    }
    if (client.connectionStatus.state == MqttConnectionState.connected) {
      print('EXAMPLE::Mosquitto client connected');
      isConnected = true;
      client.updates.listen((value) => onReciviedMessages(value));
      client.subscribe("hermes/audioServer/${siteId.trim()}/playBytes/#",
          MqttQos.atLeastOnce);
      client.subscribe("hermes/asr/textCaptured", MqttQos.atLeastOnce);
      return 0;
    } else {
      /// Use status here rather than state if you also want the broker return code.
      client.disconnect();
      isConnected = false;
      return 1;
    }
  }

  void _publishString(String topic, [String data]) {
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addString(data);
    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  void _publishBytes(String topic, Uint8List data) {
    var buffer = MqttByteBuffer.fromList(data);
    final builder = MqttClientPayloadBuilder();
    if (data != null) builder.addBuffer(buffer.buffer);
    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  void hermesAsrStartListening(
      {String sessionId,
      String wakewordId,
      bool stopInSilence = true,
      bool sendAudioCaptured = false}) {
    _publishString(
        "hermes/asr/startListening",
        json.encode({
          "siteId": "$siteId",
          "sessionId": "$sessionId",
          "lang": null,
          "stopOnSilence": stopInSilence,
          "sendAudioCaptured": sendAudioCaptured,
          "wakewordId": "$wakewordId",
          "intentFilter": null
        }));
  }

  void publishAudioFrame(Uint8List dataAudio) {
    _publishBytes("hermes/audioServer/$siteId/audioFrame", dataAudio);
  }

  void hermesAsrToggleOn({String reason = "playAudio"}) {
    _publishString("hermes/asr/toggleOn",
        json.encode({"siteId": "$siteId", "reason": "$reason"}));
  }

  void hermesAsrStopListening({String sessionId}) {
    _publishString("hermes/asr/stopListening",
        json.encode({"siteId": "$siteId", "sessionId": "$sessionId"}));
  }

  speechTotext(Uint8List dataAudio) {
    hermesAsrToggleOn();
    hermesAsrStartListening();
    publishAudioFrame(dataAudio);
    hermesAsrStopListening();

    // complete
  }

  String generateId() {
    return "38ae51e7-a10c-4842-990b-7284527e0a8b";
  }

  void hermesTtsSay(String text, {String id, String sessionId = ""}) {
    if (id == null) id = generateId();
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

  textToSpeech(String text) {
    hermesTtsSay(text);
  }

  onReciviedMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    var lastMessage = messages[0];
    print("topic: ${lastMessage.topic}");
    if (lastMessage.topic.contains("hermes/audioServer/$siteId/playBytes/")) {
      print("recivied audio");
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      var buffer = recMessPayload.payload.message;
      onReceivedAudio(buffer.toList());
    }
    if (lastMessage.topic == "hermes/asr/textCaptured") {
      final MqttPublishMessage recMessPayload = lastMessage.payload;
      HermesTextCaptured textCaptured = HermesTextCaptured.fromJson(json.decode(
          MqttPublishPayload.bytesToStringAsString(
              recMessPayload.payload.message)));
      if(textCaptured.siteId == siteId) onReceivedText(textCaptured);
    }
  }

void onDisconnected() {
    print("Disconetted");
    isConnected = false;
  }

void onConnected() {
    print("Conneted");
    isConnected = true;
  }

void onSubscribed(String topic) {
    
  }

void pong() {
    print("pong");
  }
}
