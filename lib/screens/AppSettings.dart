import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flushbar/flushbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhasspy_mobile_app/utilits/RhasspyApi.dart';
import 'package:rhasspy_mobile_app/utilits/RhasspyMqttApi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends StatefulWidget {
  static const String routeName = "/settings";
  AppSettings({Key key}) : super(key: key);

  @override
  _AppSettingsState createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  TextEditingController rhasspyIpController;
  RhasspyMqttApi rhasspyMqtt;
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("App Settings"),
      ),
      body: FutureBuilder(
          future: _prefs,
          builder: (BuildContext context,
              AsyncSnapshot<SharedPreferences> snapshot) {
                
            if (snapshot.hasData) {
              SharedPreferences prefs = snapshot.data;
              rhasspyIpController = TextEditingController(text: prefs.getString("Rhasspyip") ?? "");
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
                        String ip = value.split(":").first;
                        int port = int.parse(value.split(":").last);
                        RhasspyApi rhasspy = RhasspyApi(
                            ip, port, prefs.getBool("SSL"),
                            pemCertificate: prefs.getString("PEMCertificate"));
                        if (!(await rhasspy.checkConnection())) {
                          FlushbarHelper.createError(
                                  message: "cannot connect with rhasspy")
                              .show(context);
                        } else {
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
                      value:
                          prefs.getBool("SSL") ?? false,
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
                            prefs.setString("PEMCertificate",
                                certificate.readAsStringSync());
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
                autovalidate: true,
                onSaved: (value) {
                  prefs.setInt("MQTTPORT", int.parse(value));
                },
                validator: (value) {
                  if (value.contains(",") || value.contains(".")) {
                    return "Only number";
                  }
                  return null;
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
                obscureText: true,
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
                onFieldSubmitted: (value) {
                  prefs.setString("SITEID", value.trim());
                },
                decoration: InputDecoration(
                  labelText: "Siteid",
                ),
              ),
            ),
            SwitchListTile.adaptive(
              value: prefs != null ? prefs.getBool("MQTTONLY") ?? false : false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("MQTTONLY", value);
                });
              },
              title: Text("Only MQTT"),
              subtitle: Text("use mqtt on the home page not using more rest api."),
            ),
            FlatButton.icon(
              onPressed: () async {
                _formKey.currentState.save();
                rhasspyMqtt = RhasspyMqttApi(
                  prefs.getString("MQTTHOST"),
                  prefs.getInt("MQTTPORT"),
                  false,
                  prefs.getString("MQTTUSERNAME"),
                  prefs.getString("MQTTPASSWORD"),
                  prefs.getString("SITEID"),
                );
                int result = await rhasspyMqtt.connect();
                if (result == 0) {
                  FlushbarHelper.createSuccess(
                          message: "connection established with the broker")
                      .show(context);
                }
                if (result == 1) {
                  FlushbarHelper.createError(message: "failed to connect")
                      .show(context);
                }
                if (result == 2) {
                  FlushbarHelper.createError(message: "incorrect credentials")
                      .show(context);
                }
                if(rhasspyMqtt != null) rhasspyMqtt.disconnect();
                rhasspyMqtt = null;
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
@override
  void initState() {
    super.initState();
  }
  @override
  void dispose() {
    super.dispose();
  }
}
