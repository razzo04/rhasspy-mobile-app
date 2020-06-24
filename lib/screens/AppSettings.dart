import 'dart:io';
import 'package:provider/provider.dart';
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
  TextEditingController textEditingControllerRhasspyip;
  SharedPreferences prefs;
  String rhasspyIp;
  RhasspyMqttApi rhasspyMqtt;

  @override
  Widget build(BuildContext context) {
    _fillData();
    return Scaffold(
      appBar: AppBar(
        title: Text("App Settings"),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            SizedBox(
              width: 10,
              height: 10,
            ),
            Text(
                "Rhasspy ip: ${rhasspyIp == null || rhasspyIp == "" ? "Enter the value" : rhasspyIp}"),
            TextField(
              controller: textEditingControllerRhasspyip,
              readOnly: false,
              onSubmitted: (String value) async {
                String ip = value.split(":").first;
                int port = int.parse(value.split(":").last);
                RhasspyApi rhasspy = RhasspyApi(ip, port, prefs.getBool("SSL"),
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
                    borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
            ),
            Divider(
              thickness: 2,
            ),
            SwitchListTile.adaptive(
              value: prefs != null ? prefs.getBool("SSL") ?? false : false,
              onChanged: (bool value) {
                prefs.setBool("SSL", value);
              },
              title: Text("Enable SSL"),
              subtitle:
                  Text("enable ssl to connect only in secure connections"),
            ),
            FlatButton(
              onPressed: () async {
                if (await Permission.storage.request().isGranted) {
                  File certificate = await FilePicker.getFile();
                  if (certificate != null) {
                    prefs.setString(
                        "PEMCertificate", certificate.readAsStringSync());
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
            _buildMqttWidget(),
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
      ),
    );
  }

  _fillData() async {
    prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey("Rhasspyip")) {
      setState(() {
        rhasspyIp = "Enter the value";
      });
    } else {
      setState(() {
        rhasspyIp = prefs.getString("Rhasspyip");
      });
    }
  }

  Widget _buildMqttWidget() {
    if (prefs != null) {
      if (prefs.getBool("MQTT") != null && prefs.getBool("MQTT")) {
        return Column(
          children: <Widget>[
            SwitchListTile.adaptive(
              value: prefs != null ? prefs.getBool("MQTT") ?? false : false,
              onChanged: (bool value) {
                setState(() {
                  prefs.setBool("MQTT", value);
                });
              },
              title: Text("Enable MQTT"),
              subtitle: Text("enable mqtt to get all features"),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextFormField(
                initialValue: prefs.getString("MQTTHOST"),
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
                initialValue: prefs.getString("MQTTPASSWORD"),
                obscureText: true,
                onFieldSubmitted: (value) {
                  print(value);
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
              subtitle: Text("Use only mqtt"),
            ),
            FlatButton.icon(
              onPressed: () async {
                print("Check conessione");
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
              },
              icon: Icon(Icons.check),
              label: Text("Check connection"),
            ),
          ],
        );
      }
      return SwitchListTile.adaptive(
        value: prefs != null ? prefs.getBool("MQTT") ?? false : false,
        onChanged: (bool value) {
          setState(() {
            prefs.setBool("MQTT", value);
          });
        },
        title: Text("Enable MQTT"),
        subtitle: Text("enable mqtt to get all features"),
      );
    }
  }
  @override
  void dispose() {
    rhasspyMqtt = null;
    super.dispose();
  }
}
