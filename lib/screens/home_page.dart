import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flushbar/flushbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_recorder/flutter_audio_recorder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/parse_messages.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_api.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_mqtt_isolate.dart';
import 'package:rhasspy_mobile_app/screens/app_settings.dart';
import 'package:rhasspy_mobile_app/utils/audio_recorder_isolate.dart';
import 'package:rhasspy_mobile_app/wake_word/wake_word_utils.dart';
import 'package:rhasspy_mobile_app/widget/Intent_viewer.dart';
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
  RhasspyMqttIsolate rhasspyMqtt;
  Completer<void> mqttReady = Completer();
  AudioPlayer audioPlayer = AudioPlayer();
  MethodChannel _androidAppRetain = MethodChannel("rhasspy_mobile_app");
  MethodChannel platform = MethodChannel('rhasspy_mobile_app/widget');
  StreamController<Uint8List> audioStreamcontroller =
      StreamController<Uint8List>();
  Timer timerForAudio;
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  var _scaffoldKey = GlobalKey<ScaffoldState>();
  AudioRecorderIsolate audioRecorderIsolate;
  NluIntentParsed intent;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  bool _hotwordDetected = false;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (Platform.isAndroid) {
          if (Navigator.of(context).canPop()) {
            return true;
          } else {
            _androidAppRetain.invokeMethod("sendToBackground");
            return false;
          }
        } else {
          return true;
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text("Rhasspy mobile app"),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.settings),
              onPressed: () {
                Navigator.pushNamed(context, AppSettings.routeName)
                    .then((value) {
                  _setupMqtt();
                  _setup();
                });
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
                    if (((await _prefs).getBool("MQTT") ?? false) &&
                        ((await _prefs).getBool("SILENCE") ?? false)) {
                      if (await audioRecorderIsolate.isRecording) {
                        _stopRecording();
                        return;
                      } else {
                        _startRecording();
                        return;
                      }
                    }
                    if (!((await _prefs).getBool("MQTT") ?? false) &&
                        !(await _checkRhasspyIsReady())) {
                      // if we have not set mqtt and we cannot
                      // make a connection to rhasspy don't start recording
                      return;
                    }
                    if (recorder != null)
                      statusRecording = (await recorder.current()).status;
                    if (statusRecording == RecordingStatus.Unset ||
                        statusRecording == RecordingStatus.Stopped) {
                      _startRecording();
                    } else {
                      _stopRecording();
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
                            // if we have not set mqtt and we cannot
                            // make a connection to rhasspy do not send text
                            return;
                          }
                          Uint8List audioData = await rhasspy
                              .textToSpeech(textEditingController.text);
                          if (handle) {
                            rhasspy
                                .textToIntent(textEditingController.text)
                                .then((value) {
                              setState(() {
                                intent = value;
                              });
                            });
                          }
                          String filePath =
                              (await getApplicationDocumentsDirectory()).path +
                                  "text_to_speech.wav";
                          File file = File(filePath);
                          file.writeAsBytesSync(audioData);
                          audioPlayer.play(file.path, isLocal: true);
                        } else {
                          if (!(await _checkMqtt(context))) {
                            return;
                          }
                          if (handle) {
                            rhasspyMqtt
                                .textToIntent(textEditingController.text);
                          } else {
                            rhasspyMqtt
                                .textToSpeech(textEditingController.text);
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
                        if (await Permission.storage.request().isGranted) {
                          var result = await FilePicker.platform
                              .pickFiles(type: FileType.audio);
                          if (result?.files != null &&
                              result.files.isNotEmpty) {
                            if (!((await _prefs).getBool("MQTT") ?? false)) {
                              if (!await _checkRhasspyIsReady()) {
                                return;
                              }
                              rhasspy
                                  .speechToText(File(result.files.first.path))
                                  .then((value) {
                                setState(
                                  () {
                                    textEditingController.value =
                                        TextEditingValue(text: value);
                                  },
                                );
                                if (handle) {
                                  rhasspy.textToIntent(value).then((value) {
                                    setState(() {
                                      intent = value;
                                    });
                                  });
                                }
                              });
                            } else {
                              if (!(await _checkMqtt(context))) {
                                return;
                              }
                              rhasspyMqtt.speechTotext(
                                  File(result.files.first.path)
                                      .readAsBytesSync());
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
                  String pathFile =
                      appDocDirectory.path + "/speech_to_text.wav";
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
              ),
              IntentViewer(intent),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _checkMqtt(BuildContext context) async {
    if ((await _prefs).containsKey("MQTT") && (await _prefs).getBool("MQTT")) {
      if (rhasspyMqtt == null) {
        rhasspyMqtt = context.read<RhasspyMqttIsolate>();
        if (rhasspyMqtt == null) {
          print("get reference");
          await FlushbarHelper.createError(message: "not ready yet")
              .show(context);
          return false;
        } else {
          if (!(await rhasspyMqtt.isConnected)) {
            return await rhasspyMqtt.connect() == 0 ? true : false;
          } else {
            return true;
          }
        }
      } else {
        if (await rhasspyMqtt.isConnected) {
          print("is connected");
          return true;
        } else {
          int result = await rhasspyMqtt.connect();
          if (result == 0) {
            return true;
          }
          print("mqtt not connected $result");
          if (result == 1) {
            await FlushbarHelper.createError(message: "failed to connect")
                .show(context);
          }
          if (result == 2) {
            await FlushbarHelper.createError(message: "incorrect credentials")
                .show(context);
          }
          if (result == 3) {
            await FlushbarHelper.createError(message: "bad certificate")
                .show(context);
          }
          return false;
        }
      }
    } else {
      return false;
    }
  }

  Future<void> _stopRecording() async {
    if (await WakeWordUtils().isRunning) WakeWordUtils().resume();
    if (((await _prefs).getBool("MQTT") ?? false) &&
        ((await _prefs).getBool("SILENCE") ?? false)) {
      audioRecorderIsolate.stopRecording();
      rhasspyMqtt.stoplistening();
      setState(() {
        micColor = Colors.black;
      });
      return;
    }

    if (recorder == null) return;
    statusRecording = (await recorder.current()).status;
    if (statusRecording != RecordingStatus.Recording) {
      return;
    }
    Recording result = await recorder.stop();
    setState(() {
      micColor = Colors.black;
    });
    statusRecording = result.status;

    if (!((await _prefs).getBool("MQTT") ?? false)) {
      String text = await rhasspy.speechToText(File(result.path));
      if (handle) {
        rhasspy.textToIntent(text).then((value) {
          setState(() {
            intent = value;
          });
        });
      }
      setState(() {
        textEditingController.text = text;
      });
    } else {
      if (!((await _prefs).getBool("SILENCE") ?? false)) {
        if (!(await _checkMqtt(context))) {
          // if we have sent the audio chunk we do not
          // need to send the audio or if we are not
          // connected with mqtt we cannot send the audio
          return;
        }
        rhasspyMqtt.speechTotext(File(result.path).readAsBytesSync(),
            cleanSession: !handle);
      }
    }
  }

  void _startRecording() async {
    if (await WakeWordUtils().isRunning) WakeWordUtils().pause();
    if (await Permission.microphone.request().isGranted) {
      if (recorder != null) statusRecording = (await recorder.current()).status;
      if (statusRecording == RecordingStatus.Recording) {
        print("already recording");
        return;
      }
      _prefs.then((prefs) async {
        if (prefs.containsKey("MQTT") &&
            prefs.containsKey("SILENCE") &&
            prefs.getBool("MQTT") &&
            prefs.getBool("SILENCE")) {
          if (audioRecorderIsolate == null) {
            audioRecorderIsolate = AudioRecorderIsolate();
            await audioRecorderIsolate.isReady;
          }
          if (await audioRecorderIsolate?.isRecording) {
            print("already recording");
            return;
          }
          if (rhasspyMqtt == null) {
            // if isolate is not yet ready wait
            await mqttReady.future;
          }
          if (!(await _checkMqtt(context))) {
            print("mqtt not ready");
            return;
          }
          print("Send port: ${rhasspyMqtt.sendPort}");
          rhasspyMqtt.cleanSession();
          audioRecorderIsolate.setOtherIsolate(rhasspyMqtt.sendPort);
          audioRecorderIsolate.startRecording();
          setState(() {
            micColor = Colors.red;
          });
        } else {
          if (prefs.containsKey("MQTT") && prefs.getBool("MQTT")) {
            if (!(await _checkMqtt(context))) {
              print("mqtt not ready");
              return;
            }
          } else {
            if (!(await _checkRhasspyIsReady())) {
              return;
            }
          }
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
    int result = await rhasspy.checkConnection();
    if (result == 0) {
      return true;
    }
    if (result == 1) {
      FlushbarHelper.createError(message: "failed to connect").show(context);
      return false;
    }
    if (result == 2) {
      FlushbarHelper.createError(message: "bad certificate").show(context);
      return false;
    }
  }

  void _setup() {
    _prefs.then((SharedPreferences prefs) async {
      if (prefs.containsKey("Rhasspyip") &&
          prefs.getString("Rhasspyip").isNotEmpty) {
        SecurityContext securityContext = SecurityContext.defaultContext;
        Directory appDocDirectory = await getApplicationDocumentsDirectory();
        String certificatePath = appDocDirectory.path + "/SslCertificate.pem";
        try {
          if (File(certificatePath).existsSync())
            securityContext.setTrustedCertificates(certificatePath);
        } on TlsException {}

        String ip = prefs.getString("Rhasspyip").split(":").first;
        int port = int.parse(prefs.getString("Rhasspyip").split(":").last);
        rhasspy = RhasspyApi(ip, port, prefs.getBool("SSL") ?? false,
            securityContext: securityContext);
      }
    });
  }

  @override
  void initState() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "StartRecording") {
        // called when you press on android widget
        _startRecording();
        return true;
      }
      return null;
    });
    _setupMqtt();
    _setup();
    _setupNotification();
    super.initState();
  }

  void _setupNotification() {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    var initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    var initializationSettingsIOS = IOSInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    var initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _showNotification(String title, String body,
      {String channelId = "1",
      String channelName = "Notification",
      String channelDescription = "Notification",
      String payload}) async {
    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
        channelId, channelName, channelDescription,
        importance: Importance.max, priority: Priority.high);
    var iOSPlatformChannelSpecifics = IOSNotificationDetails();
    var platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
        Random().nextInt(1000), title, body, platformChannelSpecifics);
  }

  @override
  void dispose() {
    textEditingController.dispose();
    audioStreamcontroller.close();
    audioPlayer.dispose();
    super.dispose();
  }

  void _setupMqtt() async {
    _prefs.then((SharedPreferences prefs) async {
      if (prefs.getBool("MQTT") != null && prefs.getBool("MQTT")) {
        if (audioStreamcontroller.hasListener) {
          audioStreamcontroller.close();
          audioStreamcontroller = StreamController<Uint8List>();
        }
      }
      //TODO try to optimize
      rhasspyMqtt = context.read<RhasspyMqttIsolate>();
      if (rhasspyMqtt == null) {
        Timer.periodic(Duration(milliseconds: 1), (timer) {
          rhasspyMqtt = context.read<RhasspyMqttIsolate>();
          if (rhasspyMqtt != null) {
            _subscribeMqtt(prefs);
            mqttReady.complete();
            mqttReady = Completer();
            timer.cancel();
          }
        });
      } else {
        _subscribeMqtt(prefs);
        mqttReady.complete();
        mqttReady = Completer();
      }
    });
  }

  void _subscribeMqtt(SharedPreferences prefs) async {
    if (rhasspyMqtt?.audioStream == audioStreamcontroller.stream) {
      print("already subscribe");
      return;
    }
    if (prefs.getBool("SILENCE") ?? false) {
      if (audioRecorderIsolate == null) {
        audioRecorderIsolate = AudioRecorderIsolate();
        rhasspyMqtt.connected.then((value) {
          if (value) {
            audioRecorderIsolate.setOtherIsolate(rhasspyMqtt.sendPort);
          }
        });
      }
    }
    rhasspyMqtt.subscribeCallback(
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
        rhasspyMqtt.textToIntent(textCapture.text, handle: handle);
      },
      onReceivedIntent: (intentParsed) {
        print("Recognized intent: ${intentParsed.intent.intentName}");
        setState(() {
          intent = intentParsed;
        });
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
        print("Impossible handling intent: ${intentParsed.intent.intentName}");
      },
      stopRecording: () async {
        await _stopRecording();
      },
      startRecording: () async {
        /// wait for the audio to be played after starting to listen
        if (!_hotwordDetected) await audioPlayer.onPlayerCompletion.first;
        _startRecording();
        return true;
      },
      onIntentNotRecognized: (intent) {
        FlushbarHelper.createError(message: "IntentNotRecognized")
            .show(context);
      },
      onStartSession: (startSession) async {
        if (startSession.init.type == "notification" &&
            ((await _prefs).getBool("NOTIFICATION") ?? false)) {
          _showNotification("Notification", startSession.init.text);
        }
      },
      onHotwordDetected: (HotwordDetected hotwordDetected) {
        _hotwordDetected = true;
      },
    );
  }
}
