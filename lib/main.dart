import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rhasspy_mobile_app/utils/logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:rhasspy_mobile_app/screens/app_settings.dart';
import 'package:rhasspy_mobile_app/screens/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rhasspy_mobile_app/utils/constants.dart';
import 'rhasspy_dart/rhasspy_mqtt_isolate.dart';
import 'utils/utils.dart';

RhasspyMqttIsolate rhasspyMqttIsolate;
Logger log;
void setupLogger() async {
  MemoryLogOutput memoryOutput = MemoryLogOutput();
  WidgetsFlutterBinding.ensureInitialized();
  File logFile;
  if (Platform.isAndroid) {
    logFile = File((await getExternalStorageDirectory()).path + "/logs.txt");
  } else {
    logFile =
        File((await getApplicationDocumentsDirectory()).path + "/logs.txt");
  }
  log = Logger(
      logOutput: MultiOutput([
    memoryOutput,
    ConsoleOutput(printer: const SimplePrinter(includeStackTrace: false)),
    FileOutput(
      overrideExisting: true,
      file: logFile,
    )
  ]));
  FlutterError.onError = (FlutterErrorDetails details) {
    if (!kReleaseMode) FlutterError.dumpErrorToConsole(details);
    log.log(Level.error, details.toString(),
        stackTrace: details.stack,
        tag: details.exceptionAsString(),
        includeTime: true);
  };
}

Future<RhasspyMqttIsolate> setupMqtt() async {
  if (rhasspyMqttIsolate != null) return rhasspyMqttIsolate;
  String certificatePath;
  WidgetsFlutterBinding.ensureInitialized();
  Directory appDocDirectory = await getApplicationDocumentsDirectory();
  certificatePath = appDocDirectory.path + "/mqttCertificate.pem";
  if (!File(certificatePath).existsSync()) {
    certificatePath = null;
  }
  SharedPreferences prefs = await SharedPreferences.getInstance();
  log.d("Starting mqtt...", mqttTag);
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
    log.d("Connecting to mqtt...", mqttTag);
    rhasspyMqttIsolate.connect();
  }
  return rhasspyMqttIsolate;
}

void main() {
  setupLogger();
  runZonedGuarded<Future<void>>(() async {
    runApp(MyApp());
  }, (Object error, StackTrace stackTrace) {
    log.log(Level.error, error.toString(),
        stackTrace: stackTrace, includeTime: true);
  }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, message) {
    parent.print(zone, message);
  }));
}

class MyApp extends StatelessWidget {
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
            primarySwatch: createMaterialColor(Color.fromARGB(255, 52, 58, 64)),
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: HomePage()),
      lazy: false,
    );
  }
}
