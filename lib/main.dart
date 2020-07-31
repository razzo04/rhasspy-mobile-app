import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:rhasspy_mobile_app/screens/app_settings.dart';
import 'package:rhasspy_mobile_app/screens/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rhasspy_dart/rhasspy_mqtt_isolate.dart';

RhasspyMqttIsolate rhasspyMqttIsolate;
Future<RhasspyMqttIsolate> setupMqtt() async {
  print("setup mqtt..");
  if (rhasspyMqttIsolate != null) return rhasspyMqttIsolate;
  String certificatePath;
  WidgetsFlutterBinding.ensureInitialized();
  Directory appDocDirectory = await getApplicationDocumentsDirectory();
  certificatePath = appDocDirectory.path + "/mqttCertificate.pem";
  if (!File(certificatePath).existsSync()) {
    certificatePath = null;
  }
  SharedPreferences prefs = await SharedPreferences.getInstance();
  rhasspyMqttIsolate = RhasspyMqttIsolate(
    prefs.getString("MQTTHOST") ?? "",
    prefs.getInt("MQTTPORT") ?? 1883,
    prefs.getBool("MQTTSSL") ?? false,
    prefs.getString("MQTTUSERNAME") ?? "",
    prefs.getString("MQTTPASSWORD") ?? "",
    prefs.getString("SITEID") ?? "",
    pemFilePath: certificatePath,
  );
  if (prefs.containsKey("MQTT") && prefs.getBool("MQTT")) {
    rhasspyMqttIsolate.connect();
  }
  return rhasspyMqttIsolate;
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return FutureProvider<RhasspyMqttIsolate>(
      create: (_) => setupMqtt(),
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Rhasspy mobile app',
          onGenerateRoute: (RouteSettings settings) {
            var screen;
            switch (settings.name) {
              case HomePage.routeName:
                screen = HomePage();
                break;
              case AppSettings.routeName:
                screen = AppSettings();
                break;
            }
            return MaterialPageRoute(
                builder: (context) => screen, settings: settings);
          },
          theme: ThemeData(
            primarySwatch: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: HomePage()),
      lazy: false,
    );
  }
}
