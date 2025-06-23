import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:rccar/gameController/game_android.dart';
import 'package:rccar/gameController/game_windows.dart';
import 'server.dart';
import 'dart:core';
import 'server/signaling.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';
import 'server/mqttserver.dart';
import 'package:flutter_joystick/flutter_joystick.dart';

//定义接口
abstract class GameController {
  void init();
  void dispose();
}

/// CallSample类，继承自StatefulWidget
class CallSample extends StatefulWidget {
  final String host; // WebSocket服务器地址
  CallSample({required this.host}); // 构造函数，初始化服务器地址

  @override
  _CallSampleState createState() => _CallSampleState(); // 创建状态管理对象
}

/// _CallSampleState类，管理CallSample界面的状态
class _CallSampleState extends State<CallSample> {
  late MqttServer mqttServer;

  late GameController _gameController;
  double _sliderValue = 0; // 默认值设为 0
  double _sliderValue2 = 0;

  Signaling? _signaling; // 信令对象，用于处理WebSocket通信
  List<dynamic> _peers = []; // 对等方列表
  String? _selfId; // 当前用户的ID
  RTCVideoRenderer _localRenderer = RTCVideoRenderer(); // 本地视频渲染器
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer(); // 远程视频渲染器
  bool _inCalling = false; // 是否正在通话中
  Session? _session; // 当前通话会话
  bool _waitAccept = false; // 是否等待对方接受通话
  bool _isHangingUp = false; // 状态变量，用于标记是否已经挂断
  bool _isMuteMic = false; // 状态变量，用于标记是否已经挂断

  _CallSampleState(); // 构造函数

  @override
  initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      //横屏
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    // 隐藏状态栏和导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    initRenderers().then((_) {
      // 初始化视频渲染器
      // 等待初始化完成在连接
      _connect(context); // 连接到信令服务器
      mqttServer = MqttServer(); // 创建局部实例
      mqttServer.connect(); // 启动连接
    });
    // 根据平台选择对应控制器
    if (Platform.isAndroid) {
      _gameController = GameAndroid();
    } else if (Platform.isWindows) {
      _gameController = GameWindows(context);
    }
    _gameController.init(); // 初始化手柄
  }


  /// 初始化视频渲染器
  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  deactivate() {
    super.deactivate();
    mqttServer.disconnect(); //关闭mqtt
    _signaling?.close(); // 关闭信令连接
    _localRenderer.dispose(); // 释放本地视频渲染器
    _remoteRenderer.dispose(); // 释放远程视频渲染器
    _gameController.dispose(); // 释放手柄资
    // 恢复默认的系统 UI 模式
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    // 页面关闭时恢复默认屏幕方向
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  /// 连接到信令服务器
  void _connect(BuildContext context) async {
    _signaling ??= Signaling(widget.host, context)..connect();
    _signaling?.onSignalingStateChange = (SignalingState state) {
      switch (state) {
        case SignalingState.ConnectionClosed:
        case SignalingState.ConnectionError:
        case SignalingState.ConnectionOpen:
          break;
      }
    };

    _signaling?.onConnectionFailed = (String reason) {
      // 连接失败显示错误信息
      _showConnectionFailedDialog(reason);
    };

    _signaling?.onCallStateChange = (Session session, CallState state) async {
      switch (state) {
        case CallState.CallStateNew:
          setState(() {
            _session = session;
          });
          break;
        case CallState.CallStateRinging:
          // 自动接听来电
          _accept();
          setState(() {
            _inCalling = true;
          });
          break;
        case CallState.CallStateBye:
          if (_waitAccept) {
            print('peer reject');
            _waitAccept = false;
            Navigator.of(context).pop(false);
          }
          setState(() {
            _localRenderer.srcObject = null;
            _remoteRenderer.srcObject = null;
            _inCalling = false;
            _session = null;
          });
          break;
        case CallState.CallStateInvite:
          _waitAccept = true;
          break;
        case CallState.CallStateConnected:
          if (_waitAccept) {
            _waitAccept = false;
            Navigator.of(context).pop(false);
          }
          setState(() {
            _inCalling = true;
          });
          break;
        case CallState.CallStateRinging:
          break;
      }
    };

    _signaling?.onPeersUpdate = ((event) {
      setState(() {
        _selfId = event['self'];
        _peers = event['peers'];
      });
    });

    _signaling?.onLocalStream = ((stream) {
      _localRenderer.srcObject = stream;
      setState(() {});
    });

    _signaling?.onAddRemoteStream = ((_, stream) {
      _remoteRenderer.srcObject = stream;
      setState(() {});
    });

    _signaling?.onRemoveRemoteStream = ((_, stream) {
      _remoteRenderer.srcObject = null;
    });
  }

  /// 显示连接失败的对话框
  Future<void> _showConnectionFailedDialog(String reason) async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("webrtc连接失败"),
          content: Text(reason),
          actions: <Widget>[
            TextButton(
              child: Text("确定"),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  // /// 修改为只通过websocket传递通知视频发送端发起通话邀请
  // /// 因为生产视频的只有视频发送端，所以只能由他建立通话连接
  // _invitePeer(BuildContext context, String peerId) async {
  //   if (_signaling != null && peerId != _selfId && peerId.isNotEmpty) {
  //     _signaling?.invite(peerId);
  //   }
  // }
  ////切到signaling中连接成功发起

  /// 接受通话邀请
  _accept() {
    if (_session != null) {
      _signaling?.accept(_session!.sid, 'video');
    }
  }

  /// 挂断or进行通话邀请通知
  _hangUp() {
    if (_session != null) {
      _signaling?.bye(_session!.sid);
      setState(() {
        _isHangingUp = true; // 设置为正在挂断状态
      });
    } else if (_isHangingUp) {
      _signaling?.invite(Server.formid);
      setState(() {
        _isHangingUp = false; // 重置状态
      });
    }
  }

  /// 切换摄像头
  _switchCamera() {
    _signaling?.switchCamera();
  }

  /// 静音麦克风
  _muteMic() {
    _signaling?.muteMic();
    setState(() {
      if (!_isMuteMic) {
        _isMuteMic = true; // 设置为正在静音
      } else {
        _isMuteMic = false; // 恢复为非静音状态
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null, // 隐藏 AppBar
      body: Container(
        // 视频流全屏显示
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          color: Colors.black, // 设置背景色为黑色
        ),
        child: Stack(
          children: <Widget>[
            // 远程视频流
            Positioned.fill(
              child: RTCVideoView(
                _remoteRenderer,
                objectFit:
                    RTCVideoViewObjectFit
                        .RTCVideoViewObjectFitCover, // 设置视频流填充方式为覆盖
              ),
            ),
            // 左侧中间滑杆
            _buildLeftCenterSlider(),
            // 左侧垂直摇杆
            Positioned(
              left: 20,
              bottom: 20,
              // width: MediaQuery.of(context).size.width * 0.1,
              child: _buildLeftJoystick(),
            ),

            // 右侧水平摇杆
            Positioned(
              right: 20,
              bottom: 30,
              // width: MediaQuery.of(context).size.width * 0.3,
              child: _buildRightJoystick(),
            ),
            // 右侧滑杆
            _buildRightBottomSlider(),
            // 返回按钮
            Positioned(
              top: 20.0,
              left: 10.0,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  Navigator.pop(context); // 返回上一页
                },
              ),
            ),

            // 悬浮按钮
            Positioned(
              right: 5.0,
              top: 0.0,
              bottom: 0.0,
              child: Center(
                child: SizedBox(
                  height: 100.0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      SizedBox(
                        width: 30.0,
                        height: 30.0,
                        child: FloatingActionButton(
                          heroTag: 'fab_switch_camera',
                          // 唯一 tag
                          child: const Icon(
                            Icons.flip_camera_ios_outlined,
                            color: Colors.white24,
                          ),
                          tooltip: '切换对方摄像头',
                          onPressed: _switchCamera,
                          backgroundColor: Colors.transparent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      SizedBox(
                        width: 30.0,
                        height: 30.0,
                        child: FloatingActionButton(
                          heroTag: 'fab_hang_up',
                          // 唯一 tag
                          onPressed: _hangUp,
                          tooltip: _isHangingUp ? '发起通话' : '挂断',
                          child: Icon(
                            _isHangingUp ? Icons.call : Icons.call_end,
                            color: _isHangingUp ? Colors.white24 : Colors.pink,
                          ),
                          backgroundColor: Colors.transparent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      SizedBox(
                        width: 30.0,
                        height: 30.0,
                        child: FloatingActionButton(
                          heroTag: 'fab_mute_mic',
                          // 唯一 tag
                          onPressed: _muteMic,
                          tooltip: _isMuteMic ? '取消静音' : '静音',
                          child: Icon(
                            _isMuteMic ? Icons.mic_off : Icons.mic_none,
                            color: _isMuteMic ? Colors.white24 : Colors.white24,
                          ),
                          backgroundColor: Colors.transparent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //左滑杆
  Widget _buildLeftCenterSlider() {
    return Positioned(
      left: -50,
      top: MediaQuery.of(context).size.height / 2 - 100,
      child: Container(
        width: 150,
        height: 100,
        padding: EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 8),
            Transform.rotate(
              angle: -1.5708, // 垂直方向
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbColor: Colors.grey.withOpacity(0.5), // ← 设置滑块头部颜色为红色
                  overlayColor: Colors.grey.withOpacity(0.8), // 滑动时的高亮颜色
                  activeTrackColor: Colors.white.withOpacity(1), // 滑动条已选部分颜色
                  inactiveTrackColor: Colors.white.withOpacity(0.5), // 未选部分颜色
                ),
                child: Slider(
                  min: 0,
                  max: 90,
                  divisions: 10,
                  label: '${_sliderValue.toInt()}',
                  value: _sliderValue,
                  onChanged: (double value) {
                    setState(() {
                      _sliderValue = value.round().toDouble();
                      Server.speed = _sliderValue.toInt();
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 右侧滑杆
  Widget _buildRightBottomSlider() {
    return Positioned(
      right: 20,
      bottom: -10,
      child: Container(
        width: 160,
        height: 80,
        padding: EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbColor: Colors.grey.withOpacity(0.5),
            overlayColor: Colors.grey.withOpacity(0.8),
            activeTrackColor: Colors.white.withOpacity(1),
            inactiveTrackColor: Colors.white.withOpacity(0.5),
          ),
          child: Slider(
            min: 0,
            max: 90,
            divisions: 10,
            label: '${_sliderValue2.toInt()}',
            value: _sliderValue2,
            onChanged: (double value) {
              setState(() {
                _sliderValue2 = value.round().toDouble();
                Server.zxjd = _sliderValue2.toInt();
              });
            },
          ),
        ),
      ),
    );
  }

  ///摇杆
  Widget _buildLeftJoystick() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Joystick(
        mode: JoystickMode.vertical,
        base: Container(
          width: 80,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(40),
          ),
        ),
        // 将stick移动到正确位置 ↓
        stick: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.4),
            shape: BoxShape.circle,
          ),
        ),
        listener: (details) {
          final value = details.y.clamp(-1.0, 1.0);
          switch (value) {
            case == 0:
              Server.joyaqh = 'P';
              break;
            case > 0:
              Server.joyaqh = 'R';
              break;
            case < 0:
              Server.joyaqh = 'D';
              break;
            default:
              Server.joyaqh = 'P';
          }
        },
      ),
    );
  }

  Widget _buildRightJoystick() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Joystick(
        mode: JoystickMode.horizontal,
        base: Container(
          width: 150,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(40),
          ),
        ),
        stick: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.4),
            shape: BoxShape.circle,
          ),
        ),
        listener: (details) {
          // 处理水平方向控制
          final value = details.x.clamp(-1.0, 1.0);
          String command = '';
          switch (value) {
            case == 0:
              Server.joybzy = 'FXP';
              break;
            case > 0:
              Server.joybzy = 'FXY';
              break;
            case < 0:
              Server.joybzy = 'FXZ';
              break;
            default:
              Server.joybzy = 'FXP';
          }
        },
      ),
    );
  }
}
