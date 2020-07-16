import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flushbar/flushbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  AudioPlayer audioPlayer = AudioPlayer();
  MethodChannel platform = MethodChannel('rhasspy_mobile_app/widget');
  StreamController<Uint8List> audioStreamcontroller =
      StreamController<Uint8List>();
  Timer timerForAudio;
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
                    if (recorder != null)
                      statusRecording = (await recorder.current()).status;
                    if (statusRecording == RecordingStatus.Unset ||
                        statusRecording == RecordingStatus.Stopped) {
                      _startRecording();
                    } else {
                      if ((await _prefs).containsKey("MQTT") &&
                          (await _prefs).getBool("MQTT") &&
                          !rhasspyMqtt.isConnected) {
                        FlushbarHelper.createError(
                                message: "Connect before use")
                            .show(context);
                      }
                      _stopRecording();
                    }
                  }
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
                      if (!((await _prefs).getBool("MQTT") ?? false)) {
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
                        audioPlayer.play(file.path, isLocal: true);
                      } else {
                        if (!rhasspyMqtt.isConnected) {
                          FlushbarHelper.createError(
                                  message: "Connect before use")
                              .show(context);
                          return;
                        }
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
                          if (!((await _prefs).getBool("MQTT") ?? false)) {
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
                          } else {
                            if (!rhasspyMqtt.isConnected) {
                              FlushbarHelper.createError(
                                      message: "Connect before use")
                                  .show(context);
                              return;
                            }
                            rhasspyMqtt.speechTotext(file.readAsBytesSync());
                          }
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
            ),
            FlatButton.icon(
              onPressed: () async {
                Directory appDocDirectory =
                    await getApplicationDocumentsDirectory();
                String pathFile = appDocDirectory.path + "/speech_to_text.wav";
                File audioFile = File(pathFile);
                if (audioFile.existsSync()) {
                  audioPlayer.play(audioFile.path, isLocal: true);
                } else {
                  FlushbarHelper.createError(
                          message: "record a message before playing it")
                      .show(context);
                }
              },
              icon: Icon(Icons.play_arrow),
              label: Text("Play last voice command"),
            )
          ],
        ),
      ),
    );
  }

  Future _stopRecording() async {
    if (timerForAudio != null && timerForAudio.isActive) {
      timerForAudio.cancel();
      rhasspyMqtt.stoplistening();
    }
    setState(() {
      micColor = Colors.black;
    });
    Recording result = await recorder.stop();
    statusRecording = result.status;

    if (!((await _prefs).getBool("MQTT") ?? false)) {
      String text = await rhasspy.speechToText(File(result.path));
      if (handle) {
        rhasspy.textToIntent(text);
      }
      setState(() {
        textEditingController.text = text;
      });
    } else {
      if (!((await _prefs).getBool("SILENCE") ?? false)) {
        rhasspyMqtt.speechTotext(File(result.path).readAsBytesSync(),
            cleanSession: !handle);
      }
    }
  }

  Uint8List waveHeader(int totalAudioLen, int totalDataLen, int sampleRate,
      int channels, int byteRate) {
    Uint8List header = Uint8List(44);
    header[0] = ascii.encode("R").first;
    header[1] = ascii.encode("I").first;
    header[2] = ascii.encode("F").first;
    header[3] = ascii.encode("F").first;
    header[4] = (totalDataLen & 0xff);
    header[5] = ((totalDataLen >> 8) & 0xff);
    header[6] = ((totalDataLen >> 16) & 0xff);
    header[7] = ((totalDataLen >> 24) & 0xff);
    header[8] = ascii.encode("W").first;
    header[9] = ascii.encode("A").first;
    header[10] = ascii.encode("V").first;
    header[11] = ascii.encode("E").first;
    header[12] = ascii.encode("f").first;
    header[13] = ascii.encode("m").first;
    header[14] = ascii.encode("t").first;
    header[15] = ascii.encode(" ").first;
    header[16] = 16;
    header[17] = 0;
    header[18] = 0;
    header[19] = 0;
    header[20] = 1;
    header[21] = 0;
    header[22] = channels;
    header[23] = 0;
    header[24] = (sampleRate & 0xff);
    header[25] = ((sampleRate >> 8) & 0xff);
    header[26] = ((sampleRate >> 16) & 0xff);
    header[27] = ((sampleRate >> 24) & 0xff);
    header[28] = (byteRate & 0xff);
    header[29] = ((byteRate >> 8) & 0xff);
    header[30] = ((byteRate >> 16) & 0xff);
    header[31] = ((byteRate >> 24) & 0xff);
    header[32] = 1;
    header[33] = 0;
    header[34] = 16;
    header[35] = 0;
    header[36] = ascii.encode("d").first;
    header[37] = ascii.encode("a").first;
    header[38] = ascii.encode("t").first;
    header[39] = ascii.encode("a").first;
    header[40] = (totalAudioLen & 0xff);
    header[41] = ((totalAudioLen >> 8) & 0xff);
    header[42] = ((totalAudioLen >> 16) & 0xff);
    header[43] = ((totalAudioLen >> 24) & 0xff);
    return header;
  }

  void _startRecording() async {
    if (await Permission.microphone.request().isGranted) {
      if (recorder != null) statusRecording = (await recorder.current()).status;
      if (statusRecording == RecordingStatus.Recording) {
        print("we are already recording");
        return;
      }
      _prefs.then((prefs) async {
        if (prefs.containsKey("MQTT") &&
            prefs.containsKey("SILENCE") &&
            prefs.getBool("MQTT") &&
            prefs.getBool("SILENCE")) {
          if (!rhasspyMqtt.isConnected) {
            FlushbarHelper.createError(message: "Connect before use")
                .show(context);
            return;
          }
          int previosLenght = 0;
          Directory appDocDirectory = await getApplicationDocumentsDirectory();
          String pathFile = appDocDirectory.path + "/speech_to_text.wav";
          if (File(pathFile).existsSync()) File(pathFile).deleteSync();
          recorder =
              FlutterAudioRecorder(pathFile, audioFormat: AudioFormat.WAV);
          await recorder.initialized;
          await recorder.start();
          setState(() {
            micColor = Colors.red;
          });
          File audioFile = File(pathFile + ".temp");
          int chunkSize = 2048;
          int byteRate = (16000 * 16 * 1 ~/ 8);
          bool active = false;
          timerForAudio =
              Timer.periodic(Duration(microseconds: 10), (Timer t) async {
            int fileLenght = audioFile.lengthSync();
            if ((fileLenght - previosLenght) >= chunkSize) {
              if (active) {
                return;
              }
              active = true;
              Stream<List<int>> dataStream =
                  audioFile.openRead(previosLenght, previosLenght + chunkSize);
              List<int> dataFile = [];
              dataStream.listen(
                (data) {
                  dataFile += data;
                },
                onDone: () {
                  if (dataFile.isNotEmpty) {
                    print("previos lenght: $previosLenght");
                    print("Lenght: $fileLenght");
                    previosLenght += chunkSize;
                    Uint8List header = waveHeader(
                        chunkSize, chunkSize + 36, 16000, 1, byteRate);
                    dataFile.insertAll(0, header);
                    audioStreamcontroller.add(Uint8List.fromList(dataFile));
                    active = false;
                  }
                },
              );
            }
          });
        } else {
          Directory appDocDirectory = await getApplicationDocumentsDirectory();
          String pathFile = appDocDirectory.path + "/speech_to_text.wav";
          File audioFile = File(pathFile);
          if (audioFile.existsSync()) audioFile.deleteSync();
          recorder =
              FlutterAudioRecorder(pathFile, audioFormat: AudioFormat.WAV);
          await recorder.initialized;
          await recorder.start();
          setState(() {
            micColor = Colors.red;
          });
          Recording current = await recorder.current(channel: 0);
          statusRecording = current.status;
          Timer.periodic(Duration(milliseconds: 50), (Timer t) async {
            Recording current = await recorder.current(channel: 0);
            if (current.status == RecordingStatus.Stopped) {
              t.cancel();
            }
          });
        }
      });
    }
  }

  Future<bool> _checkRhasspyIsReady() async {
    if (!(await _prefs).containsKey("Rhasspyip") ||
        (await _prefs).getString("Rhasspyip") == "") {
      FlushbarHelper.createInformation(
              message: "please insert rhasspy server ip first")
          .show(context);
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

  @override
  void initState() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "StartRecording") {
        _startRecording();
        return true;
      }
      return null;
    });
    _setupMqtt();
    super.initState();
  }

  @override
  void dispose() {
    rhasspyMqtt.disconnect();
    textEditingController.dispose();
    audioStreamcontroller.close();
    audioPlayer.dispose();
    super.dispose();
  }

  void _setupMqtt() async {
    if (rhasspyMqtt != null && rhasspyMqtt.isConnected) {
      return;
    }
    _prefs.then((SharedPreferences prefs) async {
      String certificatePath;
      if (prefs.getBool("MQTT") != null && prefs.getBool("MQTT")) {
        if (audioStreamcontroller.hasListener) {
          audioStreamcontroller.close();
          audioStreamcontroller = StreamController<Uint8List>();
        }
        if (prefs.getBool("MQTTSSL") ?? false) {
          Directory appDocDirectory = await getApplicationDocumentsDirectory();
          certificatePath = appDocDirectory.path + "/mqttCertificate.pem";
          if (!File(certificatePath).existsSync()) {
            certificatePath = null;
          }
        }
        rhasspyMqtt = RhasspyMqttApi(
          prefs.getString("MQTTHOST"),
          prefs.getInt("MQTTPORT"),
          prefs.getBool("MQTTSSL") ?? false,
          prefs.getString("MQTTUSERNAME"),
          prefs.getString("MQTTPASSWORD"),
          prefs.getString("SITEID"),
          pemFilePath: certificatePath,
          audioStream: prefs.getBool("SILENCE") ?? false
              ? audioStreamcontroller.stream
              : null,
          onReceivedAudio: (value) async {
            //TODO move to cache directory
            String filePath = (await getApplicationDocumentsDirectory()).path +
                "text_to_speech_mqtt.wav";
            File file = File(filePath);
            file.writeAsBytesSync(value);
            if (audioPlayer.state == AudioPlayerState.PLAYING) {
              /// wait until the audio is played entirely before playing another audio
              audioPlayer.onPlayerCompletion.first.then((value) {
                audioPlayer.play(filePath, isLocal: true);
                return true;
              });
            } else {
              audioPlayer.play(filePath, isLocal: true);
              await audioPlayer.onPlayerCompletion.first;
              return true;
            }
            return false;
          },
          onReceivedText: (textCapture) {
            setState(() {
              textEditingController.text = textCapture.text;
            });
            if (handle && !rhasspyMqtt.isSessionStarted) {
              rhasspyMqtt.textToIntent(textCapture.text, handle: handle);
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
          },
          onTimeoutIntentHandle: (intentParsed) {
            FlushbarHelper.createError(
                    message:
                        "no one managed the intent: ${intentParsed.intent.intentName}")
                .show(context);
            print(
                "Impossible hadling intent: ${intentParsed.intent.intentName}");
          },
          stopRecording: () async {
            await _stopRecording();
          },
          startRecording: () {
            /// wait for the audio to be played after starting to listen
            audioPlayer.onPlayerCompletion.first.then((value) {
              _startRecording();
            });
          },
        );
        rhasspyMqtt.connect().then((result) {
          if (result == 1) {
            FlushbarHelper.createError(message: "failed to connect")
                .show(context);
          }
          if (result == 2) {
            FlushbarHelper.createError(message: "incorrect credentials")
                .show(context);
          }
          if (result == 3) {
            FlushbarHelper.createError(message: "untrusted certificate")
                .show(context);
          }
        });
      }
    });
  }
}
