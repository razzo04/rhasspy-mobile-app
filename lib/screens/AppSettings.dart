import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flushbar/flushbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rhasspy_mobile_app/utilits/RhasspyApi.dart';
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
}
