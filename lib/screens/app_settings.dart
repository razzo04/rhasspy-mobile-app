import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flushbar/flushbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_api.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_mqtt_isolate.dart';
import 'package:rhasspy_mobile_app/utils/logger/log_page.dart';
import 'package:rhasspy_mobile_app/utils/utils.dart';
import 'package:rhasspy_mobile_app/wake_word/udp_wake_word.dart';
import 'package:rhasspy_mobile_app/wake_word/wake_word_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:rhasspy_mobile_app/main.dart' show log;
import 'package:rhasspy_mobile_app/utils/constants.dart';

class AppSettings extends StatefulWidget {
  static const String routeName = "/settings";
  AppSettings({Key key}) : super(key: key);

  @override
  _AppSettingsState createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  TextEditingController rhasspyIpController;
  RhasspyMqttIsolate rhasspyMqtt;
  final _formKey = GlobalKey<FormState>();
  final _formWakeWordKey = GlobalKey<FormState>();
  bool _passwordVisible = false;
  bool _isListening = false;
  List<DropdownMenuItem<String>> availableWakeWordDetector = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("App Settings"),
        actions: [
          IconButton(
              icon: Icon(MdiIcons.mathLog),
              onPressed: () {
                openLogPage(context, log);
              })
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: FutureBuilder(
          future: _prefs,
          builder: (BuildContext context,
              AsyncSnapshot<SharedPreferences> snapshot) {
            if (snapshot.hasData) {
              SharedPreferences prefs = snapshot.data;
              rhasspyIpController = TextEditingController(
                  text: prefs.getString("Rhasspyip") ?? "");
              return SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    const SizedBox(
                      width: 10,
                      height: 10,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextFormField(
                        readOnly: false,
                        controller: rhasspyIpController,
                        onFieldSubmitted: (String value) async {
                          if (!value.contains(":")) {
                            value += ":12101";
                            setState(() {
                              rhasspyIpController.text = value;
                            });
                          }
                          setState(() {
                            prefs.setString("Rhasspyip", value.trim());
                          });
                          RhasspyApi rhasspy =
                              await getRhasspyInstance(prefs, context);
                          if (rhasspy == null) return;
                          int result = await rhasspy.checkConnection();
                          if (result == 1) {
                            FlushbarHelper.createError(
                                    message: "cannot connect with rhasspy")
                                .show(context);
                            log.e("cannot connect with rhasspy", "RHASSPY");
                          }
                          if (result == 2) {
                            FlushbarHelper.createError(
                                    message: "bad certificate")
                                .show(context);
                            log.e("bad certificate", "RHASSPY");
                          }
                          if (result == 0) {
                            FlushbarHelper.createSuccess(
                                    message:
                                        "successful connection with rhasspy")
                                .show(context);
                            log.i("successful connection with rhasspy",
                                "RHASSPY");
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: "192.168.1.1:12101",
                          labelText: "Rhasspy IP",
                        ),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: prefs.getBool("SSL") ?? false,
                      onChanged: (bool value) {
                        setState(() {
                          prefs.setBool("SSL", value);
                        });
                      },
                      title: const Text("Enable SSL"),
                      subtitle: const Text(
                        "Enable SSL connections",
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: prefs.getBool("show_intent") ?? false,
                      onChanged: (bool value) {
                        setState(() {
                          prefs.setBool("show_intent", value);
                        });
                      },
                      title: const Text("Show Intent"),
                      subtitle: const Text(
                        "Show voice command intent information",
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: prefs.getBool("show_tts") ?? false,
                      onChanged: (bool value) {
                        setState(() {
                          prefs.setBool("show_tts", value);
                        });
                      },
                      title: const Text("Show TTS"),
                      subtitle: const Text(
                        "Show Text to Speech option",
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: _addSslCertificate,
                          child: const Tooltip(
                            height: 40,
                            child: const Text("Add Self-signed Certificate"),
                            message:
                                "You must add the certificate only if it has not been signed by a trusted CA",
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            await _autoSetup(prefs);
                          },
                          child: const Text("Auto-setup"),
                        ),
                      ],
                    ),
                    const Divider(
                      thickness: 2,
                    ),
                    _buildMqttWidget(prefs),
                    const Divider(
                      thickness: 2,
                    ),
                    _buildWakeWordWidget(prefs),
                    TextButton.icon(
                      onPressed: () {
                        showAboutDialog(
                            applicationVersion: applicationVersion,
                            context: context,
                            applicationLegalese:
                                "A simple mobile app for rhasspy.");
                      },
                      icon: const Icon(Icons.info_outline),
                      label: const Text("Information"),
                    ),
                  ],
                ),
              );
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          }),
    );
  }

  Future<void> _addSslCertificate() async {
    if (await Permission.storage.request().isGranted) {
      var result =
          (await FilePicker.platform.pickFiles(allowMultiple: false))?.files;
      if (result != null && result.isNotEmpty) {
        File certificate = File(result.first.path);
        if (certificate != null) {
          Directory appDocDirectory = await getApplicationDocumentsDirectory();
          String pathFile = appDocDirectory.path + "/SslCertificate.pem";
          try {
            certificate.copySync(pathFile);
          } catch (e) {
            FlushbarHelper.createError(message: "cannot save the certificate")
                .show(context);
            log.e("cannot save the certificate", "APP");
            return;
          }
          FlushbarHelper.createSuccess(message: "certificate added correctly")
              .show(context);
          log.i("certificate added correctly", "APP");
        }
      }
    }
  }

  Future<void> _autoSetup(SharedPreferences prefs) async {
    RhasspyApi rhasspy = await getRhasspyInstance(prefs, context);
    if (rhasspy == null) return;
    RhasspyProfile profile;
    try {
      profile = RhasspyProfile.fromJson(
          await rhasspy.getProfile(ProfileLayers.profile));
    } catch (e, stackTrace) {
      if (e is DioError) {
        if (e.error is HandshakeException || e.error is TlsException) {
          log.e(
              "TLS Exception try to check the certificate or ssl settings. Exception: ${e.toString()} ",
              "RHASSPY",
              stackTrace);
          FlushbarHelper.createError(
                  message: "cannot connect with rhasspy TLS Exception")
              .show(context);
          return;
        }
      }
      log.e("cannot connect with rhasspy. ${e.toString()}", "RHASSPY",
          stackTrace);
      FlushbarHelper.createError(message: "cannot connect with rhasspy")
          .show(context);
    }
    if (profile == null) return;
    if (profile.isNewInstallation()) {
      log.w("Detected a new rhasspy installation this auto-setup may fail");
    }
    if ((prefs.getString("SITEID") ?? "").isEmpty) {
      log.i("Generating random siteId", "APP");
      setState(() {
        prefs.setString(
            "SITEID", "mobile-app" + Random().nextInt(9).toString());
      });
    }
    if ((prefs.getBool("MQTT") ?? false) &&
        (prefs.getString("MQTTHOST") != null &&
            prefs.getString("MQTTHOST") != "")) {
      if (profile.isMqttEnable) {
        if (profile.compareMqttSettings(
            prefs.getString("MQTTHOST"),
            prefs.getString("MQTTUSERNAME"),
            prefs.getString("MQTTPASSWORD"),
            prefs.getInt("MQTTPORT"))) {
          if (profile.containsSiteId(prefs.getString("SITEID"))) {
            log.i("the siteId is already present in rhasspy", "RHASSPY");
          } else {
            profile.addSiteId(prefs.getString("SITEID"));
          }
          if (await applySettings(rhasspy, profile)) {
            log.i("setup finished");
            FlushbarHelper.createSuccess(message: "setup finished")
                .show(context);
            return;
          } else {
            FlushbarHelper.createError(message: "something went wrong")
                .show(context);
            log.e("something went wrong check the previous log");
            return;
          }
        } else {
          log.w(
              "mqtt settings in the app and in rhasspy are different please check if you entered them correctly",
              "MQTT");
          FlushbarHelper.createError(
                  message:
                      "mqtt settings in the app and in rhasspy are different please check if you entered them correctly")
              .show(context);
          return;
        }
      } else {
        log.i("no mqtt credentials on rhasspy");
        if (rhasspyMqtt == null) {
          rhasspyMqtt = context.read<RhasspyMqttIsolate>();
        }
        if (!(await rhasspyMqtt.isConnected)) {
          log.w(
              "mqtt is not connected and there are no mqtt credentials on rhasspy.",
              "RHASSPY");
          FlushbarHelper.createInformation(
                  message:
                      "mqtt is not connected and there are no mqtt credentials on rhasspy.")
              .show(context);
          return;
        }
        bool sendCredentials = false;
        await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) {
              return AlertDialog(
                title: const Text(
                    "Do you want to send mqtt credentials to rhasspy?"),
                content: const Text(
                    "it has been found that on rhasspy there are no mqtt credentials but the app has them do you want to share them with rhasspy?"),
                actions: [
                  TextButton(
                    child: const Text(
                      "yes",
                    ),
                    onPressed: () {
                      sendCredentials = true;
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: const Text(
                      "no",
                    ),
                    onPressed: () {
                      sendCredentials = false;
                      Navigator.of(context).pop();
                    },
                  )
                ],
              );
            });
        if (!sendCredentials) return;
        profile.mqttSettings.enabled = true;
        profile.mqttSettings.host = prefs.getString("MQTTHOST") ?? "";
        profile.mqttSettings.username = prefs.getString("MQTTUSERNAME") ?? "";
        profile.mqttSettings.password = prefs.getString("MQTTPASSWORD") ?? "";
        profile.mqttSettings.port = prefs.getInt("MQTTPORT") ?? 1883;
        profile.addSiteId(prefs.getString("SITEID"));
        if (await applySettings(rhasspy, profile)) {
          log.i("setup finished");
          FlushbarHelper.createSuccess(message: "setup finished").show(context);
          return;
        } else {
          FlushbarHelper.createError(message: "something went wrong")
              .show(context);
          log.e("something went wrong check the previous log");
          return;
        }
      }
    } else {
      if (profile.isMqttEnable) {
        log.i("getting mqtt credentials", "APP");
        setState(() {
          prefs.setString("MQTTHOST", profile.mqttSettings.host);
          prefs.setString("MQTTUSERNAME", profile.mqttSettings.username);
          prefs.setString("MQTTPASSWORD", profile.mqttSettings.password);
          prefs.setInt("MQTTPORT", profile.mqttSettings.port);
          prefs.setBool("MQTT", true);
        });
        log.d("check if is possible to make connection whit the new credential",
            "APP");
        if (await _checkConnection(prefs)) {
          log.i("new credentials correctly saved");
        } else {
          log.e("impossible establish a connection whit the new credential");
        }
        log.i("sending siteId", "RHASSPY");
        profile.addSiteId(prefs.getString("SITEID"));
        if (await applySettings(rhasspy, profile)) {
          log.i("setup finished");
          return;
        } else {
          log.e("something went wrong check the previous log");
          return;
        }
      }
    }
  }

  Widget _buildWakeWordWidget(SharedPreferences prefs) {
    if (prefs.getBool("WAKEWORD") != null && prefs.getBool("WAKEWORD")) {
      Widget wakeWorkWidget;
      switch (prefs.getString("WAKEWORDSELECT")) {
        case "UDP":
          wakeWorkWidget = Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: TextFormField(
                  initialValue: prefs.getString("UDPHOST"),
                  onSaved: (value) {
                    prefs.setString("UDPHOST", value);
                  },
                  onFieldSubmitted: (value) {
                    prefs.setString("UDPHOST", value);
                  },
                  decoration: const InputDecoration(
                      hintText: "192.168.1.15:20000", labelText: "Host"),
                  validator: (value) {
                    if (value.isEmpty) {
                      return "the field cannot be empty";
                    }
                    if (value.split(":").length == 1) {
                      return "specify the port";
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextButton(
                    onPressed: () async {
                      if (_formWakeWordKey.currentState.validate()) {
                        _formWakeWordKey.currentState.save();
                        String ip = prefs.getString("UDPHOST").split(":").first;
                        int port = int.parse(
                            prefs.getString("UDPHOST").split(":").last);
                        UdpWakeWord wakeWord = UdpWakeWord(ip, port);
                        if (rhasspyMqtt == null) {
                          rhasspyMqtt = context.read<RhasspyMqttIsolate>();
                        }
                        if (await rhasspyMqtt.isConnected) {
                          rhasspyMqtt.enableWakeWord(wakeWord);
                        }
                        if (!(await wakeWord.isRunning)) {
                          wakeWord.startListening();
                          setState(() {
                            _isListening = true;
                          });
                        } else {
                          wakeWord.stopListening();
                          setState(() {
                            _isListening = false;
                          });
                        }
                      }
                    },
                    child: _isListening
                        ? Text("Stop wake word")
                        : Text("Start wake word")),
              )
            ],
          );
          break;
        default:
          wakeWorkWidget = Container();
      }

      return Form(
        key: _formWakeWordKey,
        child: Column(
          children: <Widget>[
            SwitchListTile.adaptive(
              value: prefs.getBool("WAKEWORD") ?? false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("WAKEWORD", value);
                });
              },
              title: Text("Wake word"),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField(
                items: availableWakeWordDetector,
                onChanged: (value) {
                  setState(() {
                    prefs.setString("WAKEWORDSELECT", value);
                  });
                },
                value: prefs.getString("WAKEWORDSELECT"),
              ),
            ),
            wakeWorkWidget,
          ],
        ),
      );
    } else {
      return Form(
        key: _formWakeWordKey,
        child: Column(
          children: <Widget>[
            SwitchListTile.adaptive(
              value: prefs.getBool("WAKEWORD") ?? false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("WAKEWORD", value);
                });
              },
              title: const Text("Wake word"),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildMqttWidget(SharedPreferences prefs) {
    if (prefs.getBool("MQTT") != null && prefs.getBool("MQTT")) {
      return Form(
        key: _formKey,
        child: Column(
          children: <Widget>[
            SwitchListTile.adaptive(
              value: prefs != null ? prefs.getBool("MQTT") ?? false : false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("MQTT", value);
                });
              },
              title: const Text("Enable MQTT"),
              subtitle:
                  const Text("enable mqtt to get dialogue Manager support"),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextFormField(
                initialValue: prefs.getString("MQTTHOST"),
                onSaved: (value) {
                  prefs.setString("MQTTHOST", value);
                },
                onFieldSubmitted: (value) {
                  prefs.setString("MQTTHOST", value);
                },
                decoration: InputDecoration(
                  labelText: "Host",
                ),
                validator: (value) {
                  if (value.isEmpty) {
                    return "the field cannot be empty";
                  }

                  return null;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextFormField(
                keyboardType: const TextInputType.numberWithOptions(
                    signed: false, decimal: false),
                initialValue: prefs.getInt("MQTTPORT") != null
                    ? prefs.getInt("MQTTPORT").toString()
                    : "",
                onSaved: (value) {
                  prefs.setInt("MQTTPORT", int.parse(value));
                },
                validator: (value) {
                  if (value.contains(",") || value.contains(".")) {
                    return "Only number";
                  }
                  if (value.isEmpty) {
                    return "the field cannot be empty";
                  }

                  return null;
                },
                onFieldSubmitted: (value) {
                  prefs.setInt("MQTTPORT", int.parse(value));
                },
                decoration: const InputDecoration(
                  labelText: "Port",
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextFormField(
                onSaved: (value) {
                  prefs.setString("MQTTUSERNAME", value.trim());
                },
                initialValue: prefs.getString("MQTTUSERNAME"),
                onFieldSubmitted: (value) {
                  prefs.setString("MQTTUSERNAME", value.trim());
                },
                validator: (value) {
                  if (value.isEmpty) {
                    return "the field cannot be empty";
                  }

                  return null;
                },
                decoration: const InputDecoration(
                  labelText: "Username",
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      onSaved: (value) {
                        prefs.setString("MQTTPASSWORD", value.trim());
                      },
                      initialValue: prefs.getString("MQTTPASSWORD"),
                      obscureText: !_passwordVisible,
                      validator: (value) {
                        if (value.isEmpty) {
                          return "the field cannot be empty";
                        }

                        return null;
                      },
                      onFieldSubmitted: (value) {
                        prefs.setString("MQTTPASSWORD", value.trim());
                      },
                      decoration: InputDecoration(
                        labelText: "Password",
                      ),
                    ),
                  ),
                  IconButton(
                      icon: Icon(_passwordVisible
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () {
                        setState(() => _passwordVisible = !_passwordVisible);
                      })
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextFormField(
                onSaved: (value) {
                  prefs.setString("SITEID", value.trim());
                },
                initialValue: prefs.getString("SITEID"),
                validator: (value) {
                  if (value.isEmpty) {
                    return "the field cannot be empty";
                  }

                  return null;
                },
                onFieldSubmitted: (value) {
                  prefs.setString("SITEID", value.trim());
                },
                decoration: const InputDecoration(
                  labelText: "Site ID",
                ),
              ),
            ),
            SwitchListTile.adaptive(
              value: prefs.getBool("SILENCE") ?? false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("SILENCE", value);
                });
              },
              title: const Text("Silence Detection"),
              subtitle: const Text(
                  "Automatically stop listening when silence is detected"),
            ),
            SwitchListTile.adaptive(
              value: prefs.getBool("MQTTSSL") ?? false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("MQTTSSL", value);
                });
              },
              title: const Text("Enable SSL"),
              subtitle: const Text("Enable SSL/TLS connections for mqtt"),
            ),
            SwitchListTile.adaptive(
              value: prefs.getBool("NOTIFICATION") ?? false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("NOTIFICATION", value);
                });
              },
              title: const Text("Enable Notifications"),
              subtitle: const Text(
                  "When a notification start session arrives a notification will be sent"),
            ),
            SwitchListTile.adaptive(
              value: prefs.getBool("EDIALOGUEMANAGER") ?? false,
              onChanged: (value) {
                setState(() {
                  prefs.setBool("EDIALOGUEMANAGER", value);
                });
              },
              title: const Text("Use External Dialogue Manager"),
              subtitle: const Text(
                  "When a voice command is issued it will be managed by an External Dialogue Manager"),
            ),
            TextButton(
              onPressed: () async {
                if (await Permission.storage.request().isGranted) {
                  var result = (await FilePicker.platform
                          .pickFiles(allowMultiple: false))
                      ?.files;
                  if (result != null && result.isNotEmpty) {
                    File certificate = File(result.first.path);
                    if (certificate != null) {
                      Directory appDocDirectory =
                          await getApplicationDocumentsDirectory();
                      String pathFile =
                          appDocDirectory.path + "/mqttCertificate.pem";
                      try {
                        certificate.copySync(pathFile);
                      } catch (e) {
                        FlushbarHelper.createError(
                                message: "cannot save the certificate")
                            .show(context);
                        return;
                      }
                      FlushbarHelper.createSuccess(
                              message: "certificate added correctly")
                          .show(context);
                    }
                  }
                }
              },
              child: const Tooltip(
                height: 40,
                child: Text("Add Self-signed Certificate"),
                message:
                    "You must add the certificate only if it has not been signed by a trusted CA",
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                if (_formKey.currentState.validate()) {
                  _formKey.currentState.save();
                  rhasspyMqtt = context.read<RhasspyMqttIsolate>();
                  if (rhasspyMqtt == null) {
                    Timer.periodic(Duration(milliseconds: 5), (timer) {
                      rhasspyMqtt = context.read<RhasspyMqttIsolate>();
                      if (rhasspyMqtt != null) {
                        _checkConnection(prefs);
                        timer.cancel();
                      }
                    });
                  } else {
                    _checkConnection(prefs);
                  }
                }
              },
              icon: const Icon(Icons.check),
              label: const Text("Check connection"),
            ),
          ],
        ),
      );
    } else {
      return SwitchListTile.adaptive(
        value: prefs.getBool("MQTT") ?? false,
        onChanged: (bool value) {
          setState(() {
            prefs.setBool("MQTT", value);
          });
        },
        title: const Text("Enable MQTT"),
        subtitle: const Text("enable mqtt to get dialogue Manager support"),
      );
    }
  }

  Future<bool> _checkConnection(SharedPreferences prefs) async {
    String certificatePath;
    if (prefs.getBool("MQTTSSL") ?? false) {
      Directory appDocDirectory = await getApplicationDocumentsDirectory();
      certificatePath = appDocDirectory.path + "/mqttCertificate.pem";
      if (!File(certificatePath).existsSync()) {
        certificatePath = null;
      }
    }
    if (rhasspyMqtt == null) {
      rhasspyMqtt = context.read<RhasspyMqttIsolate>();
    }
    rhasspyMqtt.update(
        prefs.getString("MQTTHOST"),
        prefs.getInt("MQTTPORT"),
        prefs.getBool("MQTTSSL") ?? false,
        prefs.getString("MQTTUSERNAME"),
        prefs.getString("MQTTPASSWORD"),
        prefs.getString("SITEID"),
        certificatePath);
    log.d("Connecting to mqtt", mqttTag);
    int result = await rhasspyMqtt.connect();
    log.d("result code: $result", mqttTag);
    if (result == 0) {
      FlushbarHelper.createSuccess(
              message: "connection established with the broker")
          .show(context);
      log.i("connection established with the broker", mqttTag);
      return true;
    } else if (result == 1) {
      FlushbarHelper.createError(message: "failed to connect").show(context);
      log.e("failed to connect", mqttTag);
    } else if (result == 2) {
      FlushbarHelper.createError(message: "incorrect credentials")
          .show(context);
      log.e("incorrect credentials", mqttTag);
    } else if (result == 3) {
      FlushbarHelper.createError(message: "bad certificate").show(context);
      log.e("bad certificate", mqttTag);
    }
    return false;
  }

  @override
  void initState() {
    WakeWordUtils().isRunning.then((value) {
      setState(() {
        _isListening = value;
      });
    });
    WakeWordUtils().availableWakeWordDetector.then((value) {
      setState(() {
        for (String wakeWordDetector in value) {
          availableWakeWordDetector.add(DropdownMenuItem(
            child: Text(wakeWordDetector),
            value: wakeWordDetector,
          ));
        }
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
