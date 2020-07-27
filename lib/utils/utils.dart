import 'dart:convert';

import 'dart:typed_data';

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
