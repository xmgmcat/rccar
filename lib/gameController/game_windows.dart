import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sdl_gamepad/sdl_gamepad.dart';
import '../call_sample.dart';
import '../server.dart';


class GameWindows implements GameController {
  SdlGamepad? _gamepad;
  Timer? _pollingTimer;
  Timer? _connectionCheckTimer;
  bool _lastConnectedState = false;

  final BuildContext context;

  GameWindows(this.context);

  /// 初始化手柄连接
  @override
  void init() {
    try {
      if (!SdlLibrary.init(
        eventLoopInterval: const Duration(milliseconds: 16),
      )) {
        _showErrorDialog('SDL初始化失败: ${SdlLibrary.getError()}');
        return;
      }
      // 启动连接状态轮询检测
      _startConnectionChecker();
      // 启动状态轮询
      _startPolling();
    } catch (e) {
      dispose();
      _showErrorDialog('手柄初始化异常: $e');
    }
  }

  /// 启动连接状态检测轮询
  void _startConnectionChecker() {
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final connected = SdlGamepad.getConnectedGamepadIds().isNotEmpty;

      if (connected != _lastConnectedState) {
        _lastConnectedState = connected;
        if (connected) {
          _handleGamepadConnected(); // 显示连接对话框
        } else {
          _handleGamepadDisconnected(); // 显示断开提示
        }
      }
    });
  }


  /// 处理手柄连接
  void _handleGamepadConnected() {
    final connectedIds = SdlGamepad.getConnectedGamepadIds();
    if (connectedIds.isEmpty) return;

    _gamepad?.close();
    _gamepad = SdlGamepad.fromGamepadIndex(connectedIds.first);
    _showGamepadConnectedDialog();
  }

  /// 处理手柄断开
  void _handleGamepadDisconnected() {
    _gamepad?.close();
    _gamepad = null;
    _showErrorDialog("手柄已断开");
  }

  /// 显示连接对话框
  void _showGamepadConnectedDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              title: const Text("手柄已连接"),
              content: Text("设备名称: ${_gamepad?.getInfo().name ?? '未知设备'}"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("确定"),
                ),
              ],
            ),
      );
    });
  }

  /// 显示错误对话框
  void _showErrorDialog(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text("手柄连接发生错误"),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("确定"),
                ),
              ],
            ),
      );
    });
  }

  /// 启动状态轮询
  void _startPolling() {
    _pollingTimer?.cancel();
    //间隔100毫秒更新server数据
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_gamepad == null || !_gamepad!.isConnected) return;

      final state = _gamepad!.getState();
      _printState(state);
    });
  }

  /// 打印手柄状态
  void _printState(GamepadState state) {
//     debugPrint('''
// ==== 手柄状态更新 ====
// 按钮: A=${state.buttonA} B=${state.buttonB}
// 前后摇杆: =${state.leftJoystickY.toInt()}
// 方向摇杆: =${state.rightJoystickX.toInt()}
// 扳机: LT=${(state.normalLeftTrigger * 100).toInt()}%
//     ''');

    _handlLeftJoystickY(state.leftJoystickY.toInt()); //前后摇杆
    _handlRightJoystickY(state.rightJoystickX.toInt()); //方向摇杆
    _handlLt((state.normalLeftTrigger * 100).toInt()); //LT扳机
    _handlRt((state.normalRightTrigger * 100).toInt()); //RT扳机

    // 按钮事件映射表
    final buttons = <String, bool>{
      'A': state.buttonA,
      'B': state.buttonB,
      'X': state.buttonX,
      'Y': state.buttonY,
      'UP': state.dpadUp,
      'DOWN': state.dpadDown,
      'LEFT': state.dpadLeft,
      'RIGHT': state.dpadRight
    };

    // 默认值
    Server.btnabxy = '';
    Server.udlr = '';

    // 遍历所有按钮状态
    buttons.forEach((name, isPressed) {
      if (isPressed) {
        switch (name) {
          case 'A':
          case 'B':
          case 'X':
          case 'Y':
            Server.btnabxy = name;
            break;
          case 'UP':
          case 'DOWN':
          case 'LEFT':
          case 'RIGHT':
            Server.udlr = name;
            break;
        }
      }
    });
  }

  //处理前后摇杆逻辑
  //中位-1，添加死区，超过死区范围2000才触发
  void _handlLeftJoystickY(int leftemu) {
    switch(leftemu){
      case < -2000:
        Server.joyaqh = 'D';
        break;
      case > 2000:
        Server.joyaqh = 'R';
        break;
      default:
        Server.joyaqh = 'P';
    }
  }

  //处理方向摇杆逻辑
  //中位0，添加死区，超过死区范围2000才触发
  void _handlRightJoystickY(int rightemu) {
    switch(rightemu){
      case < -2000:
        Server.joybzy = 'FXZ';
        break;
      case > 2000:
        Server.joybzy = 'FXY';
        break;
      default:
        Server.joybzy = 'FXP';
    }
  }

  //LT扳机
  // LT扳机
  void _handlLt(int lt) {
    if (lt > 90) {
      Server.lt = 90;
    } else if (lt > 0) {
      Server.lt = lt;
    } else {
      Server.lt = 0;
    }
  }

  //RT扳机
  void _handlRt(int rt) {
    if(rt > 90){
      Server.rt = 90;
    }  else if(rt > 0){
      Server.rt = rt;
    } else {
      Server.rt = 0;
    }
  }

  /// 释放资源
  @override
  void dispose() {
    _pollingTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _gamepad?.close();
    SdlLibrary.dispose();
    debugPrint('资源已释放');
  }
}
