import 'dart:convert';

import 'package:flutter/services.dart';
import '../call_sample.dart';
import '../server.dart';

class GameAndroid implements GameController {

  static const platform = MethodChannel('com.rccardt.rccar/usb_joystick');

  @override
  void init() {
    try {
      platform.invokeMethod('initializeUsbJoystick');
      _listenToJoystickData();
    } on PlatformException catch (e) {
      print("Failed to initialize USB Joystick: '${e.message}'.");
    }
  }

  void _listenToJoystickData() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "onJoystickData") {
        if (call.arguments is String) {
          try {
            final jsonString = call.arguments as String;
            final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

            final String joyaqh = jsonData['joyaqh'];
            final String joybzy = jsonData['joybzy'];
            final String btnabxy = jsonData['btnabxy'];
            final String udlr = jsonData['udlr'];
            final int lt = jsonData['lt'];
            final int rt = jsonData['rt'];
            Server.joyaqh = joyaqh;
            Server.joybzy = joybzy;
            Server.btnabxy = btnabxy;
            Server.udlr = udlr;
            Server.lt = lt;
            Server.rt = rt;
          } catch (e) {
            print("解析 JSON 失败: $e");
          }
        }
        // print('Android端手柄数据 ${call.arguments}');
      }
    });
  }

  @override
  void dispose() {
    // 取消监听器
    platform.setMethodCallHandler(null);
  }
}
