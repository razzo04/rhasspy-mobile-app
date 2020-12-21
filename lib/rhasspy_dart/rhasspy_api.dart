import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/adapter.dart';
import 'package:dio/dio.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/parse_messages.dart';

enum ProfileLayers {
  all,
  defaults,
  profile,
}

class MqttSettings {
  bool enabled = false;
  String host = "";
  String password = "";
  List<String> siteIds = [];
  String username = "";
  int port;

  MqttSettings(
      {this.enabled, this.host, this.password, this.siteIds, this.username});
  MqttSettings.empty() : enabled = false;
  MqttSettings.fromJson(Map<String, dynamic> json) {
    enabled = json.containsKey("enabled")
        ? json['enabled'] == "true" || json['enabled'] == true
            ? true
            : false
        : false;
    host = json['host'];
    password = json['password'];
    if (json.containsKey("site_id")) {
      siteIds = (json["site_id"] as String).split(",");
    } else {
      siteIds = [];
    }

    siteIds = json["site_id"] != null && json["site_id"] != ""
        ? (json['site_id'] as String).split(",")
        : [];
    username = json['username'];
    port = json.containsKey("port") ? int.parse(json["port"]) : 1883;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['enabled'] = this.enabled;
    data['host'] = this.host;
    data['password'] = this.password;
    data['site_id'] =
        this.siteIds.length != 1 ? this.siteIds.join(",") : this.siteIds[0];
    data['username'] = this.username;
    return data;
  }
}

class RhasspyProfile {
  Map<String, dynamic> _profile;
  MqttSettings mqttSettings;
  List<String> get siteIds => mqttSettings.siteIds;
  bool get isMqttEnable => mqttSettings.enabled;
  set siteIds(siteId) {
    if (siteId is String) {
      mqttSettings.siteIds.add(siteId);
    } else {
      mqttSettings.siteIds.addAll(siteId);
    }
  }

  bool get isDialogueRhasspy {
    if (_profile.containsKey("dialogue") &&
        _profile["dialogue"]["system"] == "rhasspy") {
      return true;
    } else {
      return false;
    }
  }

  void setDialogueSystem(String system) {
    if (!_profile.containsKey("dialogue")) {
      _profile["dialogue"] = Map<String, dynamic>();
    }
    _profile["dialogue"]["system"] = system;
  }

  bool containsSiteId(String siteId) {
    for (String item in mqttSettings.siteIds) {
      if (siteId == item) return true;
    }
    return false;
  }

  bool isNewInstallation() {
    if (_profile.containsKey("language")) {
      return true;
    } else {
      return false;
    }
  }

  bool compareMqttSettings(
      String host, String username, String password, int port) {
    if (mqttSettings.host == host &&
        mqttSettings.username == username &&
        mqttSettings.password == password &&
        mqttSettings.port == port) {
      return true;
    } else {
      return false;
    }
  }

  void addSiteId(String siteId) {
    if (containsSiteId(siteId)) return;
    mqttSettings.siteIds.add(siteId);
  }

  RhasspyProfile.fromJson(Map<String, dynamic> json) {
    _profile = json;
    mqttSettings = _profile.containsKey("mqtt")
        ? MqttSettings.fromJson(_profile["mqtt"])
        : MqttSettings.empty();
  }
  Map<String, dynamic> toJson() {
    _profile["mqtt"] = mqttSettings.toJson();
    return _profile;
  }
}

class RhasspyApi {
  String ip;
  int port;
  bool ssl;
  String baseUrl;
  Dio dio;
  SecurityContext securityContext;

  static const Map<ProfileLayers, String> profileString = {
    ProfileLayers.all: "all",
    ProfileLayers.defaults: "defaults",
    ProfileLayers.profile: "profile"
  };

  RhasspyApi(this.ip, this.port, this.ssl, {this.securityContext}) {
    if (!ssl) {
      baseUrl = "http://" + ip + ":" + port.toString();
      dio = Dio(BaseOptions(baseUrl: baseUrl));
    } else {
      baseUrl = "https://" + ip + ":" + port.toString();
      dio = Dio(BaseOptions(baseUrl: baseUrl));
      (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
          (client) {
        return HttpClient(context: securityContext);
      };
    }
  }

  /// check if it is possible to establish a connection with rhasspy.
  /// Its return codes are 0 connection successfully,
  /// 1 connection failed, 2 bad certificate.
  Future<int> checkConnection() async {
    // Recreate the object to change the timeout parameters
    Dio dio = Dio(
      BaseOptions(baseUrl: baseUrl, connectTimeout: 1000, receiveTimeout: 1000),
    );
    (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
        (client) {
      return HttpClient(context: securityContext);
    };
    try {
      var response = await dio.get("/api/intents");
      if (response.statusCode == 200) return 0;
    } on DioError catch (e) {
      if (e.error is HandshakeException) {
        return 2;
      }
      return 1;
    }
    return 0;
  }

  Future<String> getIntent() async {
    Response response = await dio.get("/api/intents");
    return response.data.toString();
  }

  Future<Map<String, dynamic>> getProfile(ProfileLayers layers) async {
    Response response = await dio.get("/api/profile",
        queryParameters: {"layers": profileString[layers]},
        options: Options(responseType: ResponseType.json));
    return response.data as Map<String, dynamic>;
  }

  Future<bool> setProfile(ProfileLayers layers, RhasspyProfile profile) async {
    Response response = await dio.post("/api/profile",
        queryParameters: {"layers": profileString[layers]},
        data: profile.toJson(),
        options: Options(contentType: "application/json"));
    return response.statusCode == 200;
  }

  Future<bool> restart() async {
    Response response = await dio.post(
      "/api/restart",
    );
    return response.statusCode == 200;
  }

  Future<String> speechToIntent(File file) async {
    Response response =
        await dio.post("/api/speech-to-intent", data: file.openRead());
    return response.data.toString();
  }

  Future<String> speechToText(File file) async {
    Response response =
        await dio.post("/api/speech-to-text", data: file.openRead());
    return response.data;
  }

  Future<NluIntentParsed> textToIntent(String text) async {
    Response response = await dio.post("/api/text-to-intent",
        data: text,
        queryParameters: {"outputFormat": "hermes", "nohass": false},
        options: Options(responseType: ResponseType.json));
    return NluIntentParsed.fromJson(response.data["value"]);
  }

  Future<Uint8List> textToSpeech(String text) async {
    Response response = await dio.post("/api/text-to-speech",
        data: text, options: Options(responseType: ResponseType.bytes));
    return response.data;
  }
}
