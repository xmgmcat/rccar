import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../server.dart';

class MqttServer {
  Timer? _pubMseTimer;
  MqttServerClient? client;
  String server = Server.mqtthost; // MQTT服务器地址
  String clientId = 'Rccar_${DateTime.now().millisecondsSinceEpoch}'; // 唯一客户端ID
  String username = Server.mqttusername; // 替换为实际用户名
  String password = Server.mqttpassword; // 替换为实际密码
  List<String> topics = [Server.topicpub]; // 主题列表
  int reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5; // 最大重连次数
  bool _isscheduleReconnect = false;

  Future<void> connect() async {
    client = MqttServerClient(server, clientId);
    // 基础配置
    client!.port = 1883;
    client!.keepAlivePeriod = 60;
    client!.logging(on: true);

    // 账号密码认证
    client!.setProtocolV311(); // 使用MQTT 3.1.1协议
    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean() // 设置为false可保持会话（断线后保留订阅）
        .withWillQos(MqttQos.atLeastOnce)
        .authenticateAs(username, password); // 添加认证

    client!.connectionMessage = connMess;

    // 设置连接状态监听
    client!.onDisconnected = _onDisconnected;
    client!.onConnected = _onConnected;

    try {
      await client!.connect();
    } catch (e) {
      print('MQTT连接异常: $e');
      _scheduleReconnect();
    }
  }

  void _onConnected() {
    print('MQTT连接成功');
    reconnectAttempts = 0; // 重置重连计数器

    // 订阅多个主题（QoS2）
    for (final topic in topics) {
      client!.subscribe(topic, MqttQos.exactlyOnce);
      print('已订阅主题: $topic (QoS2)');
    }

    // 消息监听
    client!.updates!.listen((messages) {
      final recvMsg = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(recvMsg.payload.message);
      print('收到消息[${messages[0].topic}]: $payload');
    });
    pubTime(); //启动消息发布定时器
  }

  void _onDisconnected() {
    print('MQTT连接断开');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if(_isscheduleReconnect){
      if (reconnectAttempts < maxReconnectAttempts) {
        reconnectAttempts++;
        print('尝试重连 ($reconnectAttempts/$maxReconnectAttempts)...');
        Future.delayed(Duration(seconds: 5), () => connect());
      } else {
        print('达到最大重连次数，停止重试');
      }
    }
  }

  void publishMessage(String topic, String message) {
    if (client!.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      client!.publishMessage(
        topic,
        MqttQos.exactlyOnce, // QoS2
        builder.payload!,
        retain: false,
      );
      print('已发布消息到[$topic]: $message');
    }
  }

  void disconnect() {
    if (client != null && client!.connectionStatus?.state == MqttConnectionState.connected) {
      client!.disconnect();
    }
    _isscheduleReconnect = true;
  }

  //消息发布定时器
  void pubTime(){
    _pubMseTimer = Timer.periodic(Duration(milliseconds: 100), (_) {
        final data = {
          'joyaqh': Server.joyaqh,
          'joybzy': Server.joybzy,
          'btnabxy': Server.btnabxy,
          'udlr': Server.udlr,
          'lt': Server.lt,
          'rt': Server.rt,
          'speed': Server.speed,
          'zxjd': Server.zxjd,
        };
        final jsonData = jsonEncode(data);
        // 发布 JSON 数据到 MQTT 主题
        publishMessage(Server.topicpub, jsonData);
    });
  }


}
