// import 'dart:io';
// import 'package:device_info_plus/device_info_plus.dart';
//
// class DeviceInfo {
//   static Future<String> get label async {
//     String deviceName = await _getDeviceName();
//     return '设备：($deviceName)';
//   }
//
//   static String get userAgent {
//     return '平台：' + Platform.operatingSystem;
//   }
//
//   static Future<String> _getDeviceName() async {
//     final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
//
//     try {
//       if (Platform.isAndroid) {
//         // Android 设备
//         final androidInfo = await deviceInfoPlugin.androidInfo;
//         return androidInfo.model; // 获取设备型号
//       } else if (Platform.isIOS) {
//         // iOS 设备
//         final iosInfo = await deviceInfoPlugin.iosInfo;
//         return iosInfo.name ?? 'Unknown iOS Device'; // 获取设备名称
//       } else if (Platform.isMacOS) {
//         // macOS 设备
//         final macOsInfo = await deviceInfoPlugin.macOsInfo;
//         return macOsInfo.computerName ?? 'Unknown Mac Device'; // 获取计算机名称
//       } else if (Platform.isLinux) {
//         // Linux 设备
//         final linuxInfo = await deviceInfoPlugin.linuxInfo;
//         return linuxInfo.name ?? 'Unknown Linux Device'; // 获取设备名称
//       } else if (Platform.isWindows) {
//         // Windows 设备
//         final windowsInfo = await deviceInfoPlugin.windowsInfo;
//         return windowsInfo.computerName ?? 'Unknown Windows Device'; // 获取计算机名称
//       }  else {
//         return Platform.localHostname ?? 'Unknown Device';
//       }
//     } catch (e) {
//       print('获取设备名称失败: $e');
//       return 'Unknown Device';
//     }
//   }
// }

import 'dart:io';

class DeviceInfo {
  static String get label {
    return '设备： ' +
        '(' +
        Platform.localHostname +
        ")";
  }

  static String get userAgent {
    return '平台：' + Platform.operatingSystem;
  }
}

