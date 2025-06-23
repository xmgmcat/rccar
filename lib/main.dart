import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'call_sample.dart';
import 'server.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: 'home', // 设置初始路由设置主页为 home
      routes: {
        'home': (context) => HomeScreen(),
        'CallSample': (context) => CallSample(host: Server.host), // 定义 CallSample 路由
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initSharedPreferences().then((_) {
      setState(() {
        _isInitialized = true;
        requestPermissions(); // 申请摄像头，录音权限
      });
    });
  }

  /// 动态申请权限
  Future<void> requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  /// 初始化读取SharedPreferences数据，并设置到服务变量仓库
  Future<void> _initSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    Server.host = prefs.getString('host') ?? '';
    Server.stunurl = prefs.getString('stun') ?? 'stun:stun.l.google.com:19302';
    Server.room = prefs.getString('room') ?? '';
    Server.formid = prefs.getString('formid') ?? '';
    Server.mqtthost = prefs.getString('mqtthost') ?? '';
    Server.mqttusername = prefs.getString('mqttusername') ?? '';
    Server.mqttpassword = prefs.getString('mqttpassword') ?? '';
    Server.topicpub = prefs.getString('topicpub') ?? '';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // // 在build方法中检查数据是否为空
    // if (!_dataCheck()) {
    //   // 如果信令服务器地址为空，则弹出设置设置框
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     _showSettingsDialog(context);
    //   });
    // }
    // else {
    //   // 如果信令服务器地址不为空，自动跳转call
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     _callNva(); //跳转
    //   });
    // }

    return Scaffold(
      appBar: AppBar(
        title: Text('遥控端'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              _showSettingsDialog(context);
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(''),
            SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                if (_dataCheck()) {
                  _callNva(); // 如果数据都不为空，进入 call
                } else {
                  _showSettingsDialog(context); // 否则弹出设置对话框
                }
              },
              child: Text('进入房间'),
            ),
          ],
        ),
      ),
    );
  }

  /// 弹出设置对话框
  void _showSettingsDialog(BuildContext context) async {
    final TextEditingController controller1 = TextEditingController(text: Server.host);
    final TextEditingController controller2 = TextEditingController(text: Server.stunurl);
    final TextEditingController controller3 = TextEditingController(text: Server.room);
    final TextEditingController controller4 = TextEditingController(text: Server.formid);
    final TextEditingController controller5 = TextEditingController(text: Server.mqtthost);
    final TextEditingController controller6 = TextEditingController(text: Server.mqttusername);
    final TextEditingController controller7 = TextEditingController(text: Server.mqttpassword);
    final TextEditingController controller8 = TextEditingController(text: Server.topicpub);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('设置'),
          content: SingleChildScrollView( // 修改为可滚动布局
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller1,
                  decoration: InputDecoration(labelText: '信令服务器地址'),
                ),
                TextField(
                  controller: controller2,
                  decoration: InputDecoration(labelText: 'stun服务地址'),
                ),
                TextField(
                  controller: controller3,
                  decoration: InputDecoration(labelText: '本机房间号'),
                ),
                TextField(
                  controller: controller4,
                  decoration: InputDecoration(labelText: '摄像端房间号'),
                ),
                TextField(
                  controller: controller5,
                  decoration: InputDecoration(labelText: 'mqtt服务地址'),
                ),
                TextField(
                  controller: controller6,
                  decoration: InputDecoration(labelText: 'mqtt用户名'),
                ),
                TextField(
                  controller: controller7,
                  decoration: InputDecoration(labelText: 'mqtt密码'),
                ),
                TextField(
                  controller: controller8,
                  decoration: InputDecoration(labelText: '发布主题'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (controller1.text.isEmpty ||
                    controller2.text.isEmpty ||
                    controller3.text.isEmpty ||
                    controller4.text.isEmpty ||
                    controller5.text.isEmpty ||
                    controller6.text.isEmpty ||
                    controller7.text.isEmpty ||
                    controller8.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('缺少必要数据')),
                  );
                  return;
                }

                // 保存数据到本地
                await _saveData(
                  controller1.text,
                  controller2.text,
                  controller3.text,
                  controller4.text,
                  controller5.text,
                  controller6.text,
                  controller7.text,
                  controller8.text,
                );
                Navigator.of(context).pop();
                // 进入call
                _callNva();
              },
              child: Text('保存'),
            ),
          ],
        );
      },
    );
  }

  /// 保存数据到 SharedPreferences
  Future<void> _saveData(String value1, String value2, String value3, String value4, String value5,
      String value6, String value7, String value8) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', value1);
    await prefs.setString('stun', value2);
    await prefs.setString('room', value3);
    await prefs.setString('formid', value4);
    await prefs.setString('mqtthost', value5);
    await prefs.setString('mqttusername', value6);
    await prefs.setString('mqttpassword', value7);
    await prefs.setString('topicpub', value8);
    /// 更新全局变量
    _initSharedPreferences();
  }

  Future<void> _callNva() async {
    Navigator.pushNamed(context, 'CallSample');
  }

  /// 检查数据是否为空
  bool _dataCheck() {
    return Server.host.isNotEmpty && Server.stunurl.isNotEmpty && Server.room.isNotEmpty && Server.formid.isNotEmpty
        && Server.mqtthost.isNotEmpty && Server.mqttusername.isNotEmpty && Server.mqttpassword.isNotEmpty &&
        Server.topicpub.isNotEmpty;
  }

}


