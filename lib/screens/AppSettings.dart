import 'package:flutter/material.dart';
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
            Text("Rhasspy ip: ${rhasspyIp == null || rhasspyIp == "" ? "Enter the value" : rhasspyIp}"),
            TextField(
              controller: textEditingControllerRhasspyip,
              readOnly: false,
              onSubmitted: (String value) {
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
            )
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
