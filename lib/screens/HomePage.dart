import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_audio_recorder/flutter_audio_recorder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhasspy_mobile_app/screens/AppSettings.dart';
import 'package:rhasspy_mobile_app/utilits/RhasspyApi.dart';
import 'package:rhasspy_mobile_app/utilits/RhasspyMqttApi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  static const String routeName = "/";
  HomePage({Key key}) : super(key: key);
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  RecordingStatus statusRecording = RecordingStatus.Unset;
  FlutterAudioRecorder recorder;
  TextEditingController textEditingController = TextEditingController();
  Color micColor = Colors.black;
  bool handle = true;
  RhasspyApi rhasspy;
  RhasspyMqttApi rhasspyMqtt;
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  var _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    _setup();
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text("Rhasspy mobile app"),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, AppSettings.routeName)
                  .then((value) => _setupMqtt());
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Center(
              child: IconButton(
                color: micColor,
                icon: Icon(Icons.mic),
                onPressed: () async {
                  if (!await _checkRhasspyIsReady() &&
                      (!(await _prefs).getBool("MQTT"))) {
                    return;
                  }
                  if (await Permission.microphone.request().isGranted) {
                    setState(() {
                      micColor = Colors.red;
                    });
                    if (statusRecording == RecordingStatus.Unset ||
                        statusRecording == RecordingStatus.Stopped) {
                      _starRecording();
                    } else {
                      setState(() {
                        micColor = Colors.black;
                      });
                      Recording result = await recorder.stop();
                      statusRecording = result.status;
                      if (!(await _prefs).getBool("MQTTONLY")) {
                        String text =
                            await rhasspy.speechToText(File(result.path));
                        if (handle) {
                          rhasspy.textToIntent(text);
                        }
                        setState(() {
                          textEditingController.text = text;
                        });
                      } else {
                        rhasspyMqtt
                            .speechTotext(File(result.path).readAsBytesSync());
                      }
                    }
                  } else {}
                },
                iconSize: MediaQuery.of(context).size.width / 1.7,
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    maxLines: 3,
                    controller: textEditingController,
                    decoration: InputDecoration(
                      labelText: "Speech to text or text to speech",
                      hintText:
                          "If you click on the microphone here the spoken text will appear if you write the text and click send will be pronounced",
                      border: OutlineInputBorder(
                        borderSide: BorderSide(width: 1),
                        borderRadius: BorderRadius.all(
                          Radius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                    icon: Icon(Icons.send),
                    onPressed: () async {
                      if (!(await _prefs).getBool("MQTTONLY")) {
                        if (!await _checkRhasspyIsReady()) {
                          return;
                        }
                        Uint8List audioData = await rhasspy
                            .textToSpeech(textEditingController.text);
                        if (handle) {
                          rhasspy
                              .textToIntent(textEditingController.text)
                              .then((value) => print(value));
                        }
                        String filePath =
                            (await getApplicationDocumentsDirectory()).path +
                                "text_to_speech.wav";
                        File file = File(filePath);
                        file.writeAsBytesSync(audioData);
                        AudioPlayer audioPlayer = AudioPlayer();
                        audioPlayer.play(file.path, isLocal: true);
                      } else {
                        if (handle) {
                          rhasspyMqtt.textToIntent(textEditingController.text);
                        } else {
                          rhasspyMqtt.textToSpeech(textEditingController.text);
                        }
                      }
                    })
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                FlatButton(
                    onPressed: () async {
                      if (!await _checkRhasspyIsReady()) {
                        return;
                      }
                      if (await Permission.storage.request().isGranted) {
                        var file =
                            await FilePicker.getFile(type: FileType.audio);
                        if (file != null) {
                          rhasspy.speechToText(file).then(
                                (value) => setState(
                                  () {
                                    textEditingController.value =
                                        TextEditingValue(text: value);
                                    if (handle) {
                                      rhasspy.textToIntent(value);
                                    }
                                  },
                                ),
                              );
                        }
                      }
                    },
                    child: Text("Select an audio")),
                Row(
                  children: <Widget>[
                    Text("Handle? "),
                    Checkbox(
                        value: handle,
                        onChanged: (bool value) {
                          setState(() {
                            handle = value;
                          });
                        }),
                  ],
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  void _starRecording() async {
    Directory appDocDirectory = await getApplicationDocumentsDirectory();
    String pathFile = appDocDirectory.path + "/speech_to_text.wav";
    File audioFile = File(pathFile);
    if (audioFile.existsSync()) audioFile.deleteSync();
    recorder = FlutterAudioRecorder(pathFile, audioFormat: AudioFormat.WAV);
    await recorder.initialized;
    await recorder.start();
    Recording current = await recorder.current(channel: 0);
    statusRecording = current.status;
    Timer.periodic(Duration(milliseconds: 50), (Timer t) async {
      Recording current = await recorder.current(channel: 0);
      if (current.status == RecordingStatus.Stopped) {
        t.cancel();
      }
    });
  }

  Future<bool> _checkRhasspyIsReady() async {
    if (!(await _prefs).containsKey("Rhasspyip") ||
        (await _prefs).getString("Rhasspyip") == "") {
      _snowSnackBar(context, "please insert rhasspy server ip first");
      return false;
    }
    return true;
  }

  void _setup() {
    _prefs.then((SharedPreferences prefs) {
      if (prefs.containsKey("Rhasspyip") &&
          prefs.getString("Rhasspyip").isNotEmpty) {
        String ip = prefs.getString("Rhasspyip").split(":").first;
        int port = int.parse(prefs.getString("Rhasspyip").split(":").last);
        rhasspy = RhasspyApi(ip, port, prefs.getBool("SSL") ?? false,
            pemCertificate: prefs.getString("PEMCertificate"));
      }
    });
  }

  void _snowSnackBar(BuildContext context, String message) {
    SnackBar snackBar = SnackBar(
      content: Text(message),
      duration: Duration(seconds: 2),
    );
    _scaffoldKey.currentState.showSnackBar(snackBar);
  }

  @override
  void initState() {
    _setupMqtt();
    super.initState();
  }

  @override
  void dispose() {
    rhasspyMqtt.disconnect();
    rhasspyMqtt = null;
    super.dispose();
  }

  void _setupMqtt() async {
    _prefs.then((SharedPreferences prefs) {
      if (!prefs.containsKey("MQTTONLY")) {
        prefs.setBool("MQTTONLY", false);
      }
      if (prefs.getBool("MQTT") != null && prefs.getBool("MQTT")) {
        rhasspyMqtt = RhasspyMqttApi(
          prefs.getString("MQTTHOST"),
          prefs.getInt("MQTTPORT"),
          false,
          prefs.getString("MQTTUSERNAME"),
          prefs.getString("MQTTPASSWORD"),
          prefs.getString("SITEID"),
          onReceivedAudio: (value) async {
            String filePath = (await getApplicationDocumentsDirectory()).path +
                "text_to_speech_mqtt.wav";
            File file = File(filePath);
            file.writeAsBytes(value).then((value) {
              AudioPlayer audioPlayer = AudioPlayer();
              audioPlayer.play(filePath, isLocal: true);
            });
          },
          onReceivedText: (textCapture) {
            setState(() {
              textEditingController.text = textCapture.text;
            });
            if (handle) {
              rhasspyMqtt.textToIntent(textCapture.text);
            }
          },
          onReceivedIntent: (intentParsed) {
            print("Recognized intent: ${intentParsed.intent.intentName}");
          },
          onReceivedEndSession: (endSession) {
            print(endSession.text);
          },
          onReceivedContinueSession: (continueSession) {
            print(continueSession.text);
            _starRecording();
            setState(() {
              micColor = Colors.red;
            });
          },
        );
        rhasspyMqtt.connect();
      }
    });
  }
}
