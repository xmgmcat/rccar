import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async';

class SimpleWebSocket {
  String _url; // WebSocket服务器的URL
  var _socket; // WebSocket连接对象
  Function()? onOpen; // WebSocket连接成功时的回调函数
  Function(dynamic msg)? onMessage; // 接收到消息时的回调函数
  Function(int? code, String? reaso)? onClose; // WebSocket关闭时的回调函数

  // 构造函数，初始化WebSocket的URL
  SimpleWebSocket(this._url);

  // 连接到WebSocket服务器
  connect() async {
    try {
      //_socket = await WebSocket.connect(_url);
      _socket = await _connectForSelfSignedCert(_url); // 使用自签名证书连接
      onOpen?.call(); // 调用连接成功回调
      _socket.listen((data) {
        onMessage?.call(data); // 调用接收到消息的回调
      }, onDone: () {
        onClose?.call(_socket.closeCode, _socket.closeReason); // 调用连接关闭的回调
      });
    } catch (e) {
      onClose?.call(500, e.toString()); // 调用连接失败的回调
    }
  }

  // 发送消息到WebSocket服务器
  send(data) {
    if (_socket != null) {
      _socket.add(data);
      print('send: $data');
    }
  }

  // 关闭WebSocket连接
  close() {
    if (_socket != null) _socket.close();
  }

  // 使用自签名证书连接到WebSocket服务器
  Future<WebSocket> _connectForSelfSignedCert(url) async {
    try {
      Random r = new Random();
      String key = base64.encode(List<int>.generate(8, (_) => r.nextInt(255)));
      HttpClient client = HttpClient(context: SecurityContext());
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        print(
            'SimpleWebSocket: Allow self-signed certificate => $host:$port. ');
        return true;
      };

      HttpClientRequest request =
      await client.getUrl(Uri.parse(url)); // 构建正确的URL
      request.headers.add('Connection', 'Upgrade');
      request.headers.add('Upgrade', 'websocket');
      request.headers.add(
          'Sec-WebSocket-Version', '13'); // 插入正确的WebSocket版本
      request.headers.add('Sec-WebSocket-Key', key.toLowerCase());

      HttpClientResponse response = await request.close();
      // ignore: close_sinks
      Socket socket = await response.detachSocket();
      var webSocket = WebSocket.fromUpgradedSocket(
        socket,
        protocol: 'signaling',
        serverSide: false,
      );

      return webSocket;
    } catch (e) {
      throw e;
    }
  }
}