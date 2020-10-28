# Rhasspy mobile app

This is a simple mobile app that interfaces with rhasspy. 

<img src="Screenshot_homepage.jpg" width="200" style="display: block;
  margin-left: auto;
  margin-right: auto;
  width: 50%;"/>
# Features
  - Text to speak
  - Speech to text
  - ability to transcribe audio
  - Ssl connection and possibility to set self-signed certificates
  - Support Hermes protocol
  - Wake work over UDP
  - Android widget for listen to a command

# Getting Started

For android you can install the app by downloading the file with extension .apk and then open it in your phone after accepting the installation from unknown sources. It is not yet available for ios. 
## Configuration 
For the app to function it needs to be configured, you can choose to use HTTP or MQTT. To use HTTP you have to enter in the text field called "Rhasspy ip" in the settings page the IP address and the port where rhasspy is running and if necessary you can enable the ssl and add the self-signed certificate. In this way, you can recognize an intent from the spoken audio but the big limitation is that you can't hear the response send by rhasspy so this should be only used for tests. To hear the answer you need to configure MQTT by entering the host and port where the MQTT broker runs, credentials, and finally the siteId. [Like you would have done for a satellite](https://rhasspy.readthedocs.io/en/latest/tutorials/#shared-mqtt-broker). To check that the connection to the broker has been made correctly, click the check connection button. In this way, the app will make requests through MQTT so you can listen to the spoken text inside endSession or continueSession messages.


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
