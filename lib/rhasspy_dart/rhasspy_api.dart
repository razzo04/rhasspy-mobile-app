import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/adapter.dart';
import 'package:dio/dio.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/parse_messages.dart';

class RhasspyApi {
  String ip;
  int port;
  bool ssl;
  String baseUrl;
  Dio dio;
  SecurityContext securityContext;

  RhasspyApi(this.ip, this.port, this.ssl, {this.securityContext}) {
    if (ssl == false) {
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
      print(response);
      if (response.statusCode == 200) {
        return 0;
      }
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
        queryParameters: {"outputFormat": "hermes"},
        options: Options(responseType: ResponseType.json));
    return NluIntentParsed.fromJson(response.data["value"]);
  }

  Future<Uint8List> textToSpeech(String text) async {
    Response response = await dio.post("/api/text-to-speech",
        data: text, options: Options(responseType: ResponseType.bytes));
    return response.data;
  }
}
