import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_api.dart';

main() {
  group("test profile parsing", () {
    test("with mqtt enabled", () async {
      DioAdapterMockito dioAdapterMockito = DioAdapterMockito();

      RhasspyApi rhasspyApi = RhasspyApi("127.0.0.1", 12101, false);
      expect(rhasspyApi.baseUrl, "http://127.0.0.1:12101");
      rhasspyApi.dio.httpClientAdapter = dioAdapterMockito;
      final responsePayload = jsonEncode(
        {
          "mqtt": {
            "enabled": true,
            "host": "127.0.0.1",
            "password": "pass",
            "site_id": "default",
            "username": "username"
          },
        },
      );

      final responseBody = ResponseBody.fromString(
        responsePayload,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
      when(dioAdapterMockito.fetch(any, any, any))
          .thenAnswer((_) async => responseBody);
      var profile = RhasspyProfile.fromJson(
          await rhasspyApi.getProfile(ProfileLayers.defaults));
      expect(profile.isMqttEnable, true);
      expect(profile.mqttSettings.host, "127.0.0.1");
      expect(profile.mqttSettings.password, "pass");
      expect(profile.mqttSettings.username, "username");
      expect(profile.mqttSettings.siteIds, ["default"]);
      expect(profile.isDialogueRhasspy, false);
      expect(profile.containsSiteId("default"), true);
    });
  });
  group("test adding siteId to profile", () {
    test("1", () async {
      DioAdapterMockito dioAdapterMockito = DioAdapterMockito();
      RhasspyApi rhasspyApi = RhasspyApi("127.0.0.1", 12101, false);
      expect(rhasspyApi.baseUrl, "http://127.0.0.1:12101");
      rhasspyApi.dio.httpClientAdapter = dioAdapterMockito;
      final responsePayload = jsonEncode(
        {
          "dialogue": {"system": "rhasspy"},
          "mqtt": {
            "enabled": true,
            "host": "localhost",
            "password": "",
            "site_id": "",
            "username": ""
          },
        },
      );

      final responseBody = ResponseBody.fromString(
        responsePayload,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
      when(dioAdapterMockito.fetch(any, any, any))
          .thenAnswer((_) async => responseBody);
      var profile = RhasspyProfile.fromJson(
          await rhasspyApi.getProfile(ProfileLayers.defaults));
      expect(profile.isMqttEnable, true);
      expect(profile.mqttSettings.host, "localhost");
      expect(profile.mqttSettings.password, "");
      expect(profile.mqttSettings.username, "");
      expect(profile.mqttSettings.siteIds, []);
      expect(profile.isDialogueRhasspy, true);
      expect(profile.containsSiteId("default"), false);
      profile.addSiteId("testId");
      expect(profile.containsSiteId("testId"), true);
      expect(
        profile.toJson(),
        {
          "dialogue": {"system": "rhasspy"},
          "mqtt": {
            "enabled": true,
            "host": "localhost",
            "password": "",
            "site_id": "testId",
            "username": ""
          },
        },
      );
    });
  });
}
