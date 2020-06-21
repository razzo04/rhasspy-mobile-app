import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class RhasspyApi {
  String ip;
  int port;
  bool ssl;
  String baseUrl;
  Dio dio;

  RhasspyApi(this.ip, this.port, this.ssl) {
    if (ssl == false) {
      baseUrl = "http://" + ip + ":" + port.toString();
    } else {
      baseUrl = "https://" + ip + ":" + port.toString();
    }
    dio = Dio(BaseOptions(baseUrl: baseUrl));
  }

  Future<String> getIntent() async {
    Response response = await dio.get("/api/intents");
    return response.data.toString();
  }
  Future<String> speechToIntent(File file) async {
    Response response = await dio.post("/api/speech-to-intent", data: file.openRead());
    return response.data.toString();
  }

  Future<String> speechToText(File file) async {
    Response response = await dio.post("/api/speech-to-text", data: file.openRead());
    return response.data;
  }
    Future<String> textToIntent(String text) async {
    Response response = await dio.post("/api/text-to-intent", data: text);
    return response.data.toString();
  }
  
  Future<Uint8List> textToSpeech(String text) async {
    Response response = await dio.post("/api/text-to-speech", data: text, options: Options(responseType: ResponseType.bytes));
    return response.data;
  }
}
