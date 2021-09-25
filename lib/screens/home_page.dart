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
import 'package:rhasspy_mobile_app/main.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/parse_messages.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_api.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_mqtt_isolate.dart';
import 'package:rhasspy_mobile_app/screens/app_settings.dart';
import 'package:rhasspy_mobile_app/utils/audio_recorder_isolate.dart';
import 'package:rhasspy_mobile_app/utils/constants.dart';
import 'package:rhasspy_mobile_app/wake_word/wake_word_utils.dart';
import 'package:rhasspy_mobile_app/widget/Intent_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

class HomePage extends StatefulWidget {
  static const String routeName = "/";
  final bool startRecording;
  HomePage({Key key, this.startRecording = false}) : super(key: key);
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
  static const MethodChannel _androidAppRetain =
      MethodChannel("rhasspy_mobile_app");
  static const MethodChannel platform =
      MethodChannel('rhasspy_mobile_app/widget');
  StreamController<Uint8List> audioStreamcontroller =
      StreamController<Uint8List>();
  Timer timerForAudio;
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  AudioRecorderIsolate audioRecorderIsolate;
  NluIntentParsed intent;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  bool _hotwordDetected = false;
  double volume = 1;
  bool hasVibrator = false;

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
        appBar: AppBar(
          title: const Text("Rhasspy mobile app"),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.settings),
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
                  icon: const Icon(Icons.mic),
                  onPressed: () async {
                    _onPressedMic();
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
                      decoration: const InputDecoration(
                        labelText: "Speech to text or text to speech",
                        hintText:
                            "If you click on the microphone here the spoken text will appear if you write the text and click send will be pronounced",
                        border: const OutlineInputBorder(
                          borderSide: const BorderSide(width: 1),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () async {
                        log.d("Sending text: ${textEditingController.text}",
                            "APP");
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
                          audioPlayer.play(file.path,
                              isLocal: true, volume: volume);
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
                      child: const Text("Select an audio")),
                  Row(
                    children: <Widget>[
                      const Text("Handle? "),
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
                    audioPlayer.play(audioFile.path,
                        isLocal: true, volume: volume);
                  } else {
                    FlushbarHelper.createError(
                            message: "Record a message before playing it")
                        .show(context);
                    log.e("Record a message before playing it", "APP");
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text("Play last voice command"),
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
          await FlushbarHelper.createError(message: "not ready yet")
              .show(context);
          log.e("mqtt not ready yet", "MQTT");
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
          return true;
        } else {
          int result = await rhasspyMqtt.connect();
          if (result == 0) {
            return true;
          }
          log.e("mqtt not connected $result", "MQTT");
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
    log.i("Stop recording", "APP");
    if (await WakeWordUtils().isRunning) WakeWordUtils().resume();
    if (((await _prefs).getBool("MQTT") ?? false) &&
        ((await _prefs).getBool("SILENCE") ?? false)) {
      audioRecorderIsolate.stopRecording();
      rhasspyMqtt.stopListening();
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

    // This is here instead of the stopRecording
    // callback because it needs to trigger before
    // the STT response, but not before it the
    // microphone actually stops recording
    if (_hotwordDetected && hasVibrator) {
      Vibration.vibrate(duration: 250);
    }

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
        if (_hotwordDetected) {
          rhasspyMqtt.stopListening();
        }
        rhasspyMqtt.speechTotext(File(result.path).readAsBytesSync(),
            cleanSession: !handle);
      }
    }
  }

  void _startRecording() async {
    if (await WakeWordUtils().isRunning) WakeWordUtils().pause();
    if (await Permission.microphone.request().isGranted) {
      log.i("Start recording", "APP");
      if (recorder != null) statusRecording = (await recorder.current()).status;
      if (statusRecording == RecordingStatus.Recording) {
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
            return;
          }
          if (rhasspyMqtt == null) {
            // if isolate is not yet ready wait
            await mqttReady.future;
          }
          if (!(await _checkMqtt(context))) {
            log.w("mqtt not ready", "MQTT");
            return;
          }
          log.d("Send port: ${rhasspyMqtt.sendPort}", "MQTT");
          if (!_hotwordDetected) rhasspyMqtt.cleanSession();
          audioRecorderIsolate.setOtherIsolate(rhasspyMqtt.sendPort);
          audioRecorderIsolate.startRecording();
          setState(() {
            micColor = Colors.red;
          });
        } else {
          if (prefs.containsKey("MQTT") && prefs.getBool("MQTT")) {
            if (!(await _checkMqtt(context))) {
              log.w("Mqtt not ready", "MQTT");
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
      log.e("please insert rhasspy server ip first", "RHASSPY");
      return false;
    }
    int result = await rhasspy.checkConnection();
    if (result == 0) {
      return true;
    }
    if (result == 1) {
      FlushbarHelper.createError(message: "failed to connect").show(context);
      log.e("failed to connect", "RHASSPY");
      return false;
    }
    if (result == 2) {
      FlushbarHelper.createError(message: "bad certificate").show(context);
      log.e("bad certificate", "RHASSPY");
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
    super.initState();
    platform.setMethodCallHandler((call) async {
      if (call.method == "StartRecording") {
        // called when you press on the android widget
        if (rhasspyMqtt == null && !mqttReady.isCompleted) {
          await mqttReady.future;
          if (await rhasspyMqtt.connected) {
            log.d("StartRecording from android", appTag);
            _onPressedMic();
          }
        } else {
          log.d("StartRecording from android", appTag);
          _onPressedMic();
        }
        return true;
      }
      return null;
    });
    _setupMqtt();
    _setup();
    _setupNotification();

    mqttReady.future.then((_) {
      if (widget.startRecording) {
        rhasspyMqtt.connected.then((isConnected) {
          if (isConnected) _startRecording();
        });
      }
    });

    // Asynchronously check vibration cababilities
    // to minimize delay when the vibrate function is called.
    Vibration.hasVibrator().then((value) {
      setState(() {
        hasVibrator = value;
      });
    });
  }

  void _onPressedMic() async {
    HotwordDetected hotWord = HotwordDetected();
    hotWord.currentSensitivity = 1;
    hotWord.sendAudioCaptured = true;
    hotWord.modelType = "personal";
    if (((await _prefs).getBool("MQTT") ?? false) &&
        ((await _prefs).getBool("SILENCE") ?? false)) {
      if (await audioRecorderIsolate.isRecording) {
        _stopRecording();
        return;
      } else {
        if (((await _prefs).getBool("EDIALOGUEMANAGER") ?? false) &&
            !rhasspyMqtt.isSessionManaged) {
          rhasspyMqtt.wake(hotWord, "mobile-app");
          log.d("sending hotWord", "DIALOGUE");
          return;
        }
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
    if (recorder != null) statusRecording = (await recorder.current()).status;
    if (statusRecording == RecordingStatus.Unset ||
        statusRecording == RecordingStatus.Stopped) {
      if (((await _prefs).getBool("EDIALOGUEMANAGER") ?? false) &&
          !rhasspyMqtt.isSessionManaged) {
        log.d("sending hotWord", "DIALOGUE");
        rhasspyMqtt.wake(hotWord, "mobile-app");
        return;
      }
      _startRecording();
    } else {
      _stopRecording();
    }
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

  Future<void> _setupMqtt() async {
    SharedPreferences prefs = await _prefs;
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
  }

  void _subscribeMqtt(SharedPreferences prefs) async {
    if (rhasspyMqtt?.audioStream == audioStreamcontroller.stream) {
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
          log.d("Received audio to play", "DIALOGUE");
          String filePath = (await getApplicationDocumentsDirectory()).path +
              "text_to_speech_mqtt.wav";
          File file = File(filePath);
          file.writeAsBytesSync(value);
          if (audioPlayer.state == AudioPlayerState.PLAYING) {
            /// wait until the audio is played entirely before playing another audio
            audioPlayer.onPlayerCompletion.first.then((value) {
              audioPlayer.play(filePath, isLocal: true, volume: volume);
              return true;
            });
          } else {
            audioPlayer.play(filePath, isLocal: true, volume: volume);
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
          log.i("Recognized intent: ${intentParsed.intent.intentName}",
              "DIALOGUE");
          setState(() {
            intent = intentParsed;
          });
        },
        onReceivedEndSession: (endSession) {
          log.i("EndSession text: ${endSession.text}", "DIALOGUE");
          _hotwordDetected = false;
        },
        onReceivedContinueSession: (continueSession) {
          log.i("ContinueSession text: ${continueSession.text}", "DIALOGUE");
        },
        onTimeoutIntentHandle: (intentParsed) {
          FlushbarHelper.createError(
                  message:
                      "no one managed the intent: ${intentParsed.intent.intentName}")
              .show(context);
          log.e("no one managed the intent:: ${intentParsed.intent.intentName}",
              "DIALOGUE");
        },
        stopRecording: () async {
          log.d("StopRecording request", "DIALOGUE");
          await _stopRecording();
        },
        startRecording: () async {
          log.d("StartRecording request", "DIALOGUE");

          /// wait for the audio to be played after starting to listen
          if (!_hotwordDetected) await audioPlayer.onPlayerCompletion.first;
          _startRecording();
          return true;
        },
        onIntentNotRecognized: (intent) {
          FlushbarHelper.createError(message: "IntentNotRecognized")
              .show(context);
          log.w("IntentNotRecognized", "DIALOGUE");
        },
        onStartSession: (startSession) async {
          if (startSession.init.type == "notification" &&
              ((await _prefs).getBool("NOTIFICATION") ?? false)) {
            _showNotification("Notification", startSession.init.text);
          }
        },
        onHotwordDetected: (HotwordDetected hotwordDetected) async {
          log.d("HotWord Detected ${hotwordDetected.modelId}", "DIALOGUE");
          _hotwordDetected = true;
          if (hasVibrator) {
            Vibration.vibrate(duration: 250);
          }
        },
        onSetVolume: (volumeToSet) {
          volume = volumeToSet;
        });
  }
}
