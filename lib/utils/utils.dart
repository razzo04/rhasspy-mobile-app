import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:flushbar/flushbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhasspy_mobile_app/main.dart';
import 'package:rhasspy_mobile_app/rhasspy_dart/rhasspy_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List waveHeader(
    int totalAudioLen, int sampleRate, int channels, int byteRate) {
  int totalDataLen = totalAudioLen + 36;
  Uint8List header = Uint8List(44);
  header[0] = ascii.encode("R").first;
  header[1] = ascii.encode("I").first;
  header[2] = ascii.encode("F").first;
  header[3] = ascii.encode("F").first;
  header[4] = (totalDataLen & 0xff);
  header[5] = ((totalDataLen >> 8) & 0xff);
  header[6] = ((totalDataLen >> 16) & 0xff);
  header[7] = ((totalDataLen >> 24) & 0xff);
  header[8] = ascii.encode("W").first;
  header[9] = ascii.encode("A").first;
  header[10] = ascii.encode("V").first;
  header[11] = ascii.encode("E").first;
  header[12] = ascii.encode("f").first;
  header[13] = ascii.encode("m").first;
  header[14] = ascii.encode("t").first;
  header[15] = ascii.encode(" ").first;
  header[16] = 16;
  header[17] = 0;
  header[18] = 0;
  header[19] = 0;
  header[20] = 1;
  header[21] = 0;
  header[22] = channels;
  header[23] = 0;
  header[24] = (sampleRate & 0xff);
  header[25] = ((sampleRate >> 8) & 0xff);
  header[26] = ((sampleRate >> 16) & 0xff);
  header[27] = ((sampleRate >> 24) & 0xff);
  header[28] = (byteRate & 0xff);
  header[29] = ((byteRate >> 8) & 0xff);
  header[30] = ((byteRate >> 16) & 0xff);
  header[31] = ((byteRate >> 24) & 0xff);
  header[32] = 1;
  header[33] = 0;
  header[34] = 16;
  header[35] = 0;
  header[36] = ascii.encode("d").first;
  header[37] = ascii.encode("a").first;
  header[38] = ascii.encode("t").first;
  header[39] = ascii.encode("a").first;
  header[40] = (totalAudioLen & 0xff);
  header[41] = ((totalAudioLen >> 8) & 0xff);
  header[42] = ((totalAudioLen >> 16) & 0xff);
  header[43] = ((totalAudioLen >> 24) & 0xff);
  return header;
}

Future<bool> applySettings(RhasspyApi rhasspy, RhasspyProfile profile) async {
  if (!profile.isDialogueRhasspy) {
    log.w("rhasspy Dialogue Management is not enable.");
    profile.setDialogueSystem("rhasspy");
  }
  log.d("sending new profile config", "APP");
  try {
    if (await rhasspy.setProfile(ProfileLayers.defaults, profile)) {
      log.i("Restarting rhasspy...", "RHASSPY");
      if (await rhasspy.restart()) {
        log.i("restarted", "RHASSPY");
        return true;
      } else {
        log.e("failed to restarted rhasspy", "RHASSPY");
        return false;
      }
    } else {
      log.e("failed to send new profile", "RHASSPY");
      return false;
    }
  } catch (e) {
    log.e("failed to send new profile ${e.toString()}");
    return false;
  }
}

Future<RhasspyApi> getRhasspyInstance(SharedPreferences prefs,
    [BuildContext context]) async {
  SecurityContext securityContext = SecurityContext.defaultContext;
  Directory appDocDirectory = await getApplicationDocumentsDirectory();
  String certificatePath = appDocDirectory.path + "/SslCertificate.pem";
  try {
    if (File(certificatePath).existsSync())
      securityContext.setTrustedCertificates(certificatePath);
  } on TlsException {}
  String value = prefs.getString("Rhasspyip");
  if (value == null) {
    if (context != null)
      FlushbarHelper.createError(
              message: "please insert rhasspy server ip first")
          .show(context);
    log.e("please insert rhasspy server ip first", "RHASSPY");
    return null;
  }
  String ip = value.split(":").first;
  int port = int.parse(value.split(":").last);
  return RhasspyApi(ip, port, prefs.getBool("SSL") ?? false,
      securityContext: securityContext);
}

MaterialColor createMaterialColor(Color color) {
  List strengths = <double>[.05];
  final swatch = <int, Color>{};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  strengths.forEach((strength) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  });
  return MaterialColor(color.value, swatch);
}
