# Rhasspy mobile app

This is a simple mobile app that interfaces with rhasspy. 

<img src="https://user-images.githubusercontent.com/53791253/103412557-f6466f00-4b75-11eb-8bb2-313d4ddbed61.png" width="240" style="display: block;
  margin-left: auto;
  margin-right: auto;"/>
  <img src="https://user-images.githubusercontent.com/53791253/103412110-ea59ad80-4b73-11eb-83d6-d909e7d631ec.gif" width="240" style="display: block;
  margin-left: auto;
  margin-right: auto;"/>
# Features
  - Text to speak
  - Speech to text
  - ability to transcribe audio
  - Ssl connection and possibility to set self-signed certificates
  - Support Hermes protocol
  - Wake word over UDP
  - Android widget for listen to a command

# Getting Started
For android you can install the app by downloading the file with extension .apk present in each new [release](https://github.com/razzo04/rhasspy-mobile-app/releases) and then open it in your phone after accepting the installation from unknown sources. It is not yet available for ios. 

Once the app has been installed, it needs to be configured from version 1.7.0, the configuration of the app has been greatly simplified it is sufficient to insert in the text field called "Rhasspy ip" the ip and the port where rhasspy is running. If you are using the default port it will only be necessary to enter the ip. Once the entry is confirmed, a message should appear indicating whether a connection to rhasspy has occurred. If not, check the SSL settings and the logs which may contain useful information to understand the nature of the problem. Once you have made a connection to rhasspy you can click the auto setup button this will take care of generating a siteId if not specified and taking the MQTT credentials and adding the siteId to the various services so that the app can work. If the procedure does not work, check the logs and open an issue if necessary. If rhasspy does not have MQTT credentials, the app will check if it has them and if so it will send them and complete the setup procedure.

# Building From Source
To get started you need to install [flutter](https://flutter.dev/docs/get-started/install) and then you can download the repository.  
```bash
git clone https://github.com/razzo04/rhasspy-mobile-app.git
cd rhasspy-mobile-app
```
For build android.
```bash
flutter build apk
```
For build ios you need macOS and Xcode.
```bash
flutter build ios
```
