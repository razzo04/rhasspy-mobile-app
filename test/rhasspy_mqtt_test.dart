import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_mqtt_api.dart';

class MockClient extends Mock implements MqttServerClient {}

main() {
  MockClient mockClient = MockClient();
  group("test connection", () {
    test("code 0", () async {
      RhasspyMqttApi rhasspyMqttApi = RhasspyMqttApi(
          "host", 1883, false, "username", "password", "siteId",
          client: mockClient);
      MqttClientConnectionStatus connectionStatus =
          MqttClientConnectionStatus();
      connectionStatus.state = MqttConnectionState.connected;
      connectionStatus.disconnectionOrigin = MqttDisconnectionOrigin.none;
      connectionStatus.returnCode = MqttConnectReturnCode.connectionAccepted;
      StreamController<List<MqttReceivedMessage<MqttMessage>>>
          messagesController = StreamController();
      when(mockClient.updates).thenAnswer((_) => messagesController.stream);
      rhasspyMqttApi.connected.then((value) {
        expect(value, true);
      });
      when(mockClient.connect(any, any))
          .thenAnswer((_) => Future.value(connectionStatus));
      when(mockClient.connectionStatus).thenReturn(connectionStatus);
      expect(await rhasspyMqttApi.connect(), 0);
      expect(rhasspyMqttApi.isConnected, true);
      reset(mockClient);
      messagesController.close();
    });
    test("code 1", () async {
      RhasspyMqttApi rhasspyMqttApi =
          RhasspyMqttApi("host", 1883, false, "username", "password", "siteId");
      rhasspyMqttApi.client = mockClient;
      MqttClientConnectionStatus connectionStatus =
          MqttClientConnectionStatus();
      connectionStatus.state = MqttConnectionState.disconnected;
      connectionStatus.disconnectionOrigin = MqttDisconnectionOrigin.solicited;
      connectionStatus.returnCode = MqttConnectReturnCode.noneSpecified;
      when(mockClient.connect())
          .thenAnswer((_) => Future.value(connectionStatus));
      when(mockClient.connectionStatus).thenReturn(connectionStatus);
      rhasspyMqttApi.connected.then((value) {
        expect(value, false);
      });
      expect(await rhasspyMqttApi.connect(), 1);
      expect(rhasspyMqttApi.isConnected, false);
      verifyNever(mockClient.subscribe(any, any));
      reset(mockClient);
    });
    test("code 2", () async {
      RhasspyMqttApi rhasspyMqttApi =
          RhasspyMqttApi("host", 1883, false, "username", "password", "siteId");
      rhasspyMqttApi.client = mockClient;
      MqttClientConnectionStatus connectionStatus =
          MqttClientConnectionStatus();
      connectionStatus.state = MqttConnectionState.disconnected;
      connectionStatus.disconnectionOrigin =
          MqttDisconnectionOrigin.unsolicited;
      connectionStatus.returnCode = MqttConnectReturnCode.badUsernameOrPassword;
      when(mockClient.connect())
          .thenAnswer((_) => Future.value(connectionStatus));

      when(mockClient.connectionStatus).thenReturn(connectionStatus);
      rhasspyMqttApi.connected.then((value) {
        expect(value, false);
      });
      expect(await rhasspyMqttApi.connect(), 2);
      expect(rhasspyMqttApi.isConnected, false);
      verifyNever(mockClient.subscribe(any, any));
      reset(mockClient);
    });
    test("code 3", () async {
      RhasspyMqttApi rhasspyMqttApi =
          RhasspyMqttApi("host", 1883, false, "username", "password", "siteId");
      rhasspyMqttApi.client = mockClient;
      MqttClientConnectionStatus connectionStatus =
          MqttClientConnectionStatus();
      connectionStatus.state = MqttConnectionState.disconnected;
      connectionStatus.disconnectionOrigin = MqttDisconnectionOrigin.solicited;
      connectionStatus.returnCode = MqttConnectReturnCode.noneSpecified;
      when(mockClient.connect(any, any)).thenThrow(HandshakeException());
      when(mockClient.connectionStatus).thenReturn(connectionStatus);
      when(mockClient.connectionStatus).thenReturn(connectionStatus);
      rhasspyMqttApi.connected.then((value) {
        expect(value, false);
      });
      expect(await rhasspyMqttApi.connect(), 3);
      expect(rhasspyMqttApi.isConnected, false);
      verify(mockClient.disconnect()).called(1);
      verifyNever(mockClient.subscribe(any, any));
      reset(mockClient);
    });
  });
}
