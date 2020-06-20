import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';


 import 'package:http/http.dart';

class RhasspyApi {
  String ip;
  int port;
  bool ssl;
  String baseUrl;

  RhasspyApi(this.ip, this.port, this.ssl) {
    if (ssl == false) {
      baseUrl = "http://" + ip + ":" + port.toString();
    } else {
      baseUrl = "https://" + ip + ":" + port.toString();
    }
  }

  Future<String> getIntent() async {
    var response = await get("/api/intents");
    return response.body;
  }
  Future<String> speechToIntent(File file) async {
    Uint8List dataFile =  file.readAsBytesSync();
    Response response = await post(baseUrl+ "/api/speech-to-intent", body: dataFile);
    return response.body;
  }

  Future<String> speechToText(File file) async {
    // var file = File(pathToFile).readAsStringSync(encoding: Encoding.getByName("ISO_8859-1:1987"));
    Uint8List dataFile =  file.readAsBytesSync();
    Response response = await post(baseUrl+ "/api/speech-to-text", body: dataFile);
    return response.body; 
  }
    Future<String> textToIntent(String text) async {
    Response response = await post(baseUrl+ "/api/text-to-intent", body: text);
    return response.body;
  }
  
  Future<Uint8List> textToSpeech(String text) async {
    Response response = await post(baseUrl+ "/api/text-to-speech", body: text);
    return response.bodyBytes;
  }
}
