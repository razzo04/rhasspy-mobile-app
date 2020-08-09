import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flushbar/flushbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_api.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_mqtt_isolate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("App Settings"),
        leading: new IconButton(
          icon: new Icon(Icons.arrow_back),
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
                    SizedBox(
                      width: 10,
                      height: 10,
                    ),
                    TextFormField(
                      readOnly: false,
                      controller: rhasspyIpController,
                      onFieldSubmitted: (String value) async {
                        if (!value.contains(":")) {
                          value += ":12101";
                          setState(() {
                            rhasspyIpController.text = value;
                          });
                        }
                        SecurityContext securityContext =
                            SecurityContext.defaultContext;
                        Directory appDocDirectory =
                            await getApplicationDocumentsDirectory();
                        String certificatePath =
                            appDocDirectory.path + "/SslCertificate.pem";
                        try {
                          if (File(certificatePath).existsSync())
                            securityContext
                                .setTrustedCertificates(certificatePath);
                        } on TlsException {}

                        String ip = value.split(":").first;
                        int port = int.parse(value.split(":").last);
                        RhasspyApi rhasspy = RhasspyApi(
                            ip, port, prefs.getBool("SSL"),
                            securityContext: securityContext);
                        int result = await rhasspy.checkConnection();
                        print(result);
                        if (result == 1) {
                          FlushbarHelper.createError(
                                  message: "cannot connect with rhasspy")
                              .show(context);
                        }
                        if (result == 2) {
                          FlushbarHelper.createError(message: "bad certificate")
                              .show(context);
                        }
                        if (result == 0) {
                          FlushbarHelper.createSuccess(
                                  message: "successful connection with rhasspy")
                              .show(context);
                        }
                        setState(() {
                          prefs.setString("Rhasspyip", value.trim());
                        });
                      },
                      decoration: InputDecoration(
                        hintText: "192.168.1.15:12101",
                        labelText: "Rhasspy ip",
                        border: OutlineInputBorder(
                            borderSide: BorderSide(width: 1),
                            borderRadius:
                                BorderRadius.all(Radius.circular(10))),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: prefs.getBool("SSL") ?? false,
                      onChanged: (bool value) {
                        setState(() {
                          prefs.setBool("SSL", value);
                        });
                      },
                      title: Text("Enable SSL"),
                      subtitle: Text(
                          "enable ssl to connect only in secure connections"),
                    ),
                    FlatButton(
                      onPressed: () async {
                        if (await Permission.storage.request().isGranted) {
                          File certificate = await FilePicker.getFile();
                          if (certificate != null) {
                            Directory appDocDirectory =
                                await getApplicationDocumentsDirectory();
                            String pathFile =
                                appDocDirectory.path + "/SslCertificate.pem";
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
                      },
                      child: Tooltip(
                        height: 40,
                        child: Text("Add Self-signed certificate"),
                        message:
                            "You must add the certificate only if it has not been signed by a trusted CA",
                      ),
                    ),
                    Divider(
                      thickness: 2,
                    ),
                    _buildMqttWidget(prefs),
                    Divider(
                      thickness: 2,
                    ),
                    FlatButton.icon(
                      onPressed: () {
                        showLicensePage(
                          context: context,
                        );
                      },
                      icon: Icon(Icons.info_outline),
                      label: Text("Information"),
                    ),
                  ],
                ),
              );
            } else {
              return CircularProgressIndicator();
            }
          }),
    );
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
              title: Text("Enable MQTT"),
              subtitle: Text("enable mqtt to get dialogue Manager support"),
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
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextFormField(
                keyboardType: TextInputType.numberWithOptions(
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
                },
                onFieldSubmitted: (value) {
                  prefs.setInt("MQTTPORT", int.parse(value));
                },
                decoration: InputDecoration(
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
                },
                decoration: InputDecoration(
                  labelText: "Username",
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextFormField(
                onSaved: (value) {
                  prefs.setString("MQTTPASSWORD", value.trim());
                },
                initialValue: prefs.getString("MQTTPASSWORD"),
                // TODO add the possibility to see the password
                obscureText: true,
                validator: (value) {
                  if (value.isEmpty) {
                    return "the field cannot be empty";
                  }
                },
                onFieldSubmitted: (value) {
                  prefs.setString("MQTTPASSWORD", value.trim());
                },
                decoration: InputDecoration(
                  labelText: "Password",
                ),
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
                },
                onFieldSubmitted: (value) {
                  prefs.setString("SITEID", value.trim());
                },
                decoration: InputDecoration(
                  labelText: "Siteid",
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
              title: Text("Silence Detection"),
              subtitle: Text("auto stop listening when silence is detected"),
            ),
            SwitchListTile.adaptive(
              value: prefs.getBool("MQTTSSL") ?? false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("MQTTSSL", value);
                });
              },
              title: Text("Enable SSL"),
              subtitle: Text("enable secure connections for mqtt"),
            ),
            FlatButton(
              onPressed: () async {
                if (await Permission.storage.request().isGranted) {
                  File certificate = await FilePicker.getFile();
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
              },
              child: Tooltip(
                height: 40,
                child: Text("Add Self-signed certificate"),
                message:
                    "You must add the certificate only if it has not been signed by a trusted CA",
              ),
            ),
            FlatButton.icon(
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
              icon: Icon(Icons.check),
              label: Text("Check connection"),
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
        title: Text("Enable MQTT"),
        subtitle: Text("enable mqtt to get dialogue Manager support"),
      );
    }
  }

  Future _checkConnection(SharedPreferences prefs) async {
    String certificatePath;
    if (prefs.getBool("MQTTSSL") ?? false) {
      Directory appDocDirectory = await getApplicationDocumentsDirectory();
      certificatePath = appDocDirectory.path + "/mqttCertificate.pem";
      if (!File(certificatePath).existsSync()) {
        certificatePath = null;
      }
    }
    rhasspyMqtt.update(
        prefs.getString("MQTTHOST"),
        prefs.getInt("MQTTPORT"),
        prefs.getBool("MQTTSSL") ?? false,
        prefs.getString("MQTTUSERNAME"),
        prefs.getString("MQTTPASSWORD"),
        prefs.getString("SITEID"),
        certificatePath);
    int result = await rhasspyMqtt.connect();
    if (result == 0) {
      FlushbarHelper.createSuccess(
              message: "connection established with the broker")
          .show(context);
    }
    if (result == 1) {
      FlushbarHelper.createError(message: "failed to connect").show(context);
    }
    if (result == 2) {
      FlushbarHelper.createError(message: "incorrect credentials")
          .show(context);
    }
    if (result == 3) {
      FlushbarHelper.createError(message: "bad certificate").show(context);
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
