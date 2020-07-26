import 'dart:io';
import 'dart:typed_data';

import 'package:dio/adapter.dart';
import 'package:dio/dio.dart';

class RhasspyApi {
  String ip;
  int port;
  bool ssl;
  String baseUrl;
  Dio dio;
  String pemCertificate;

  RhasspyApi(this.ip, this.port, this.ssl, {this.pemCertificate}) {
    if (ssl == false) {
      baseUrl = "http://" + ip + ":" + port.toString();
      dio = Dio(BaseOptions(baseUrl: baseUrl));
    } else {
      baseUrl = "https://" + ip + ":" + port.toString();
      dio = Dio(BaseOptions(baseUrl: baseUrl));
      (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
          (client) {
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          print("called");
          if (cert.pem == pemCertificate) {
            // Verify the certificate
            return true;
          }
          return false;
        };
      };
    }
  }

  /// check if it is possible to establish a connection with rhasspy.
  /// If it is not possible return false.
  Future<bool> checkConnection() async {
    Dio dio = Dio(
      BaseOptions(baseUrl: baseUrl, connectTimeout: 1000, receiveTimeout: 1000),
    );
    (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
        (client) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        if (cert.pem == pemCertificate) {
          // Verify the certificate
          return true;
        }
        return false;
      };
    };
    try {
      // Recreate the object to change the timeout parameters
      var response = await dio.get("/api/intents");
      if (response.statusCode == 200) {
        return true;
      }
    } on DioError catch (_) {
      return false;
    }
    return true;
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

  Future<String> textToIntent(String text) async {
    Response response = await dio.post("/api/text-to-intent", data: text);
    return response.data.toString();
  }

  Future<Uint8List> textToSpeech(String text) async {
    Response response = await dio.post("/api/text-to-speech",
        data: text, options: Options(responseType: ResponseType.bytes));
    return response.data;
  }
}
