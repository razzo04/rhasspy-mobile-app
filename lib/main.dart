import 'package:flutter/material.dart';
import 'package:rhasspy_mobile_app/screens/AppSettings.dart';
import 'package:rhasspy_mobile_app/screens/HomePage.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: HomePage(),
    );
  }
}
