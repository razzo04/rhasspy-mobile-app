import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_api.dart';

main() {
  test("test adding siteId with mqtt enabled", () async {
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
    profile.addSiteId("testSiteId");
    expect(profile.siteIds, ["default", "testSiteId"]);
    expect(profile.containsSiteId("testSiteId"), true);
    expect(
      profile.toJson(),
      {
        "mqtt": {
          "enabled": true,
          "host": "127.0.0.1",
          "password": "pass",
          "site_id": "default,testSiteId",
          "username": "username"
        },
      },
    );
  });
  test("test adding siteId with mqtt enabled and a empty siteId", () async {
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
  test("test adding siteId and mqtt credentials", () async {
    DioAdapterMockito dioAdapterMockito = DioAdapterMockito();
    RhasspyApi rhasspyApi = RhasspyApi("127.0.0.1", 12101, false);
    expect(rhasspyApi.baseUrl, "http://127.0.0.1:12101");
    rhasspyApi.dio.httpClientAdapter = dioAdapterMockito;
    final responsePayload = jsonEncode(
      {
        "dialogue": {"system": "rhasspy"},
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
    expect(profile.isMqttEnable, false);
    expect(profile.mqttSettings.host, "");
    expect(profile.mqttSettings.password, "");
    expect(profile.mqttSettings.username, "");
    expect(profile.mqttSettings.siteIds, []);
    expect(profile.isDialogueRhasspy, true);
    expect(profile.containsSiteId("default"), false);
    profile.addSiteId("testId");
    expect(profile.containsSiteId("testId"), true);
    profile.mqttSettings.password = "password";
    profile.mqttSettings.port = 1883;
    profile.mqttSettings.username = "username";
    profile.mqttSettings.host = "localhost";
    profile.mqttSettings.enabled = true;
    expect(
      profile.toJson(),
      {
        "dialogue": {"system": "rhasspy"},
        "mqtt": {
          "enabled": true,
          "host": "localhost",
          "password": "password",
          "site_id": "testId",
          "username": "username"
        },
      },
    );
  });
  test("test adding siteId and mqtt credentials with a empty profile",
      () async {
    DioAdapterMockito dioAdapterMockito = DioAdapterMockito();
    RhasspyApi rhasspyApi = RhasspyApi("127.0.0.1", 12101, false);
    expect(rhasspyApi.baseUrl, "http://127.0.0.1:12101");
    rhasspyApi.dio.httpClientAdapter = dioAdapterMockito;
    final responsePayload = jsonEncode(
      {},
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
    expect(profile.isMqttEnable, false);
    expect(profile.mqttSettings.host, "");
    expect(profile.mqttSettings.password, "");
    expect(profile.mqttSettings.username, "");
    expect(profile.mqttSettings.siteIds, []);
    expect(profile.isDialogueRhasspy, false);
    expect(profile.containsSiteId("default"), false);
    profile.addSiteId("testId");
    expect(profile.containsSiteId("testId"), true);
    profile.mqttSettings.password = "password";
    profile.mqttSettings.port = 1883;
    profile.mqttSettings.username = "username";
    profile.mqttSettings.host = "localhost";
    profile.mqttSettings.enabled = true;
    profile.setDialogueSystem("rhasspy");
    expect(
      profile.toJson(),
      {
        "dialogue": {"system": "rhasspy"},
        "mqtt": {
          "enabled": true,
          "host": "localhost",
          "password": "password",
          "site_id": "testId",
          "username": "username"
        },
      },
    );
  });
}
