import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../server.dart';
import 'websocket.dart' if (dart.library.js) 'websocket_web.dart';
import 'turn.dart' if (dart.library.js) 'turn_web.dart';
import '../device_info.dart';

/// 信令状态枚举，表示WebRTC信令连接的状态。
enum SignalingState {
  ConnectionOpen,  // 连接已打开
  ConnectionClosed, // 连接已关闭
  ConnectionError, // 连接错误
}

/// 通话状态枚举，表示WebRTC通话的状态。
enum CallState {
  CallStateNew, // 新通话
  CallStateRinging, // 通话响铃中
  CallStateInvite, // 通话邀请中
  CallStateConnected, // 通话已连接
  CallStateBye, // 通话结束
}

/// 视频源枚举，表示视频流的来源。
enum VideoSource {
  Camera, // 摄像头
}

/// 会话类，表示一个WebRTC会话。
class Session {
  Session({required this.sid, required this.pid});
  String pid; // 对端ID
  String sid; // 会话ID
  RTCPeerConnection? pc; // WebRTC对等连接
  RTCDataChannel? dc; // WebRTC数据通道
  List<RTCIceCandidate> remoteCandidates = []; // 远程ICE候选
}

class Signaling {
  Signaling(this._host, this._context);
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  SimpleWebSocket? _socket;
  BuildContext? _context;

  var _host = Server.host; // WebSocket服务器地址
  String _selfId =  Server.room; //房间号

  var _turnCredential; // TURN服务器凭证
  Map<String, Session> _sessions = {}; // 会话映射表
  MediaStream? _localStream; // 本地媒体流
  List<MediaStream> _remoteStreams = <MediaStream>[]; // 远程媒体流列表
  List<RTCRtpSender> _senders = <RTCRtpSender>[]; // RTP发送者列表
  VideoSource _videoSource = VideoSource.Camera; // 当前视频源

  Function(SignalingState state)? onSignalingStateChange; // 信令状态变化回调
  Function(Session session, CallState state)? onCallStateChange; // 通话状态变化回调
  Function(MediaStream stream)? onLocalStream; // 本地流变化回调
  Function(Session session, MediaStream stream)? onAddRemoteStream; // 添加远程流回调
  Function(Session session, MediaStream stream)? onRemoveRemoteStream; // 移除远程流回调
  Function(dynamic event)? onPeersUpdate; // 对端更新回调
  Function(Session session, RTCDataChannel dc, RTCDataChannelMessage data)?
  onDataChannelMessage; // 数据通道消息回调
  Function(Session session, RTCDataChannel dc)? onDataChannel; // 数据通道回调

  String get sdpSemantics => 'unified-plan'; // SDP语义，默认为Unified Plan

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:'+Server.stunurl},
      /*
       * turn server configuration example.
      {
        'url': 'turn:123.45.67.89:3478',
        'username': 'change_to_real_user',
        'credential': 'change_to_real_secret'
      },
      */
    ],
    // 添加H264相关参数
    'iceTransportPolicy': 'relay',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require'
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true}, // 启用DTLS-SRTP密钥协商
      // 添加H264编解码器优先级配置
      {'googCpuOveruseDetection': true},
      {'googCpuOveruseEncodeUsage': true}
    ],
    // 指定视频编解码器
    'codecs': {
      'video': [
        'H264',
        'VP8',  // 保留备选方案
      ]
    }
  };

  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true, // 接收音频
      'OfferToReceiveVideo': true, // 接收视频
    },
    'optional': [],
  };

  Function(String reason)? onConnectionFailed; // 连接失败回调


  /// 关闭信令连接并清理会话。
  close() async {
    await _cleanSessions();
    _socket?.close();
  }

  /// 通知对端切换摄像头。
  void switchCamera() {
    _send('switchCamera', {
      'swid': Server.formid,
    });
  }


  /// 静音麦克风
  void muteMic() {
    if (_localStream != null) {
      bool enabled = _localStream!.getAudioTracks()[0].enabled;
      _localStream!.getAudioTracks()[0].enabled = !enabled;
    }
  }

  /// 通知视频发送端对我进行视频邀请。
  /// [_selfId] 本机ID
  void invite(String peerId) async {
    //将本机id通过websocket发送给对端
    _send('callme', {
      'toid': _selfId,
      'tzid': peerId,
    });
  }


  /// 结束通话。
  /// [sessionId] 会话ID
  void bye(String sessionId) {
    _send('bye', {
      'session_id': sessionId,
      'from': _selfId,
    });
    var sess = _sessions[sessionId];
    if (sess != null) {
      _closeSession(sess);
    }
  }

  /// 接受通话邀请。
  /// [sessionId] 会话ID
  /// [media] 媒体类型
  void accept(String sessionId, String media) {
    var session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    _createAnswer(session, media);
  }

  /// 拒绝通话邀请。
  /// [sessionId] 会话ID
  void reject(String sessionId) {
    var session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    bye(session.sid);
  }

  /// 处理从WebSocket接收到的消息。
  /// [message] 接收到的消息
  void onMessage(message) async {
    Map<String, dynamic> mapData = message;
    var data = mapData['data'];

    switch (mapData['type']) {
      case 'peers':
        {
          List<dynamic> peers = data;
          if (onPeersUpdate != null) {
            Map<String, dynamic> event = Map<String, dynamic>();
            event['self'] = _selfId;
            event['peers'] = peers;
            onPeersUpdate?.call(event);
          }
        }
        break;
      case 'offer':
        {
          var peerId = data['from'];
          var description = data['description'];
          var media = data['media'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          var newSession = await _createSession(session,
            peerId: peerId,
            sessionId: sessionId,
            media: media,);
          _sessions[sessionId] = newSession;
          await newSession.pc?.setRemoteDescription(
              RTCSessionDescription(description['sdp'], description['type']));
          // await _createAnswer(newSession, media);

          if (newSession.remoteCandidates.length > 0) {
            newSession.remoteCandidates.forEach((candidate) async {
              await newSession.pc?.addCandidate(candidate);
            });
            newSession.remoteCandidates.clear();
          }
          onCallStateChange?.call(newSession, CallState.CallStateNew);
          onCallStateChange?.call(newSession, CallState.CallStateRinging);
        }
        break;
      case 'answer':
        {
          var description = data['description'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          session?.pc?.setRemoteDescription(
              RTCSessionDescription(description['sdp'], description['type']));
          onCallStateChange?.call(session!, CallState.CallStateConnected);
        }
        break;
      case 'candidate':
        {
          var peerId = data['from'];
          var candidateMap = data['candidate'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
              candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);

          if (session != null) {
            if (session.pc != null) {
              await session.pc?.addCandidate(candidate);
            } else {
              session.remoteCandidates.add(candidate);
            }
          } else {
            _sessions[sessionId] = Session(pid: peerId, sid: sessionId)
              ..remoteCandidates.add(candidate);
          }
        }
        break;
      case 'leave':
        {
          var peerId = data as String;
          _closeSessionByPeerId(peerId);
        }
        break;
      case 'bye':
        {
          var sessionId = data['session_id'];
          print('bye: ' + sessionId);
          var session = _sessions.remove(sessionId);
          if (session != null) {
            onCallStateChange?.call(session, CallState.CallStateBye);
            _closeSession(session);
          }
        }
        break;
      case 'keepalive':
        {
          print('keepalive response!');
        }
        break;
      default:
        break;
    }
  }

  /// 连接到信令服务器。
  Future<void> connect() async {
    var url = 'https://$_host/ws';
    _socket = SimpleWebSocket(url);

    print('connect to $url');

    if (_turnCredential == null) {
      try {
        _turnCredential = await getTurnCredential(_host);
        /*{
            "username": "1584195784:mbzrxpgjys",
            "password": "isyl6FF6nqMTB9/ig5MrMRUXqZg",
            "ttl": 86400,
            "uris": ["turn:127.0.0.1:19302?transport=udp"]
          }
        */
        _iceServers = {
          'iceServers': [
            {
              'urls': _turnCredential['uris'][0],
              'username': _turnCredential['username'],
              'credential': _turnCredential['password']
            },
          ]
        };
      } catch (e) {}
    }

    _socket?.onOpen = () {
      print('onOpen');
      onSignalingStateChange?.call(SignalingState.ConnectionOpen);
      _send('new', {
        'name': DeviceInfo.label,
        'id': _selfId,
        'user_agent': DeviceInfo.userAgent
      });

      //设备连接成功上线，
      // 连接完成，根据 formid 发起通话邀请通知
      invite(Server.formid);

    };

    _socket?.onMessage = (message) {
      print('Received data: ' + message);
      onMessage(_decoder.convert(message));
    };

    _socket?.onClose = (int? code, String? reason) {
      print('Closed by server [$code => $reason]!');
      if (code == 500) {
        onSignalingStateChange?.call(SignalingState.ConnectionError);
        // 添加一个回调来通知连接失败的原因
        onConnectionFailed?.call(reason!);
      } else {
        onSignalingStateChange?.call(SignalingState.ConnectionClosed);
      }
    };

    await _socket?.connect();
  }

  /// 创建媒体流。
  /// [media] 媒体类型
  Future<MediaStream> createStream(String media) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': false
      // 'video': {  //地视频生成
      //   'mandatory': {
      //     'minWidth': '1',
      //     'minHeight': '1',
      //     'minFrameRate': '1',
      //     // 强制使用H264
      //     'googVideoH264Enabled': true,
      //     'googVideoH264ProfileLevelId': '42e01f'
      //   },
      //   'optional': [
      //     {'profile-level-id': '42e01f'},
      //     {'level-asymmetry-allowed': 1},
      //     {'packetization-mode': 1}
      //   ]
      // }
    };

    MediaStream stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    return stream;
  }


  /// 创建或更新一个用于WebRTC通信的会话。
  ///
  /// 该函数通过创建或重用[Session]对象、设置本地媒体流并配置RTCPeerConnection来初始化WebRTC会话。
  ///
  /// [session]: 要重用的现有会话。如果为null，将创建一个新会话。
  /// [peerId]: 要连接的对等方的ID。
  /// [sessionId]: 会话的唯一ID。
  /// [media]: 会话中使用的媒体类型（例如，'audio'、'video'、'data'）。
  ///
  /// 返回一个表示创建或更新的会话的[Future<Session>]。
  Future<Session> _createSession(Session? session, {
    required String peerId,
    required String sessionId,
    required String media,
  }) async {
    var newSession = session ?? Session(sid: sessionId, pid: peerId);

    // 如果会话不是仅用于数据传输，则创建本地媒体流。
    if (media != 'data') {
      _localStream = await createStream(media);
    }

    print(_iceServers);

    // 使用提供的ICE服务器和配置创建新的RTCPeerConnection。
    RTCPeerConnection pc = await createPeerConnection({
      ..._iceServers,
      ...{'sdpSemantics': sdpSemantics}
    }, _config);

    // 根据媒体类型和SDP语义配置RTCPeerConnection。
    if (media != 'data') {
      switch (sdpSemantics) {
        case 'plan-b':
          pc.onAddStream = (MediaStream stream) {
            onAddRemoteStream?.call(newSession, stream);
            _remoteStreams.add(stream);
          };
          await pc.addStream(_localStream!);
          break;
        case 'unified-plan':
          pc.onTrack = (event) {
            if (event.track.kind == 'video') {
              onAddRemoteStream?.call(newSession, event.streams[0]);
            }
          };
          // _localStream!.getTracks().forEach((track) async {
          //   _senders.add(await pc.addTrack(track, _localStream!));
          ///仅添加音频轨道
          _localStream!.getAudioTracks().forEach((track) async {
            _senders.add(await pc.addTrack(track, _localStream!));
          });
          break;
      }
    }

    // 处理ICE候选事件。
    pc.onIceCandidate = (candidate) async {
      if (candidate == null) {
        print('onIceCandidate: complete!');
        return;
      }
      await Future.delayed(
          const Duration(seconds: 1),
              () =>
              _send('candidate', {
                'to': peerId,
                'from': _selfId,
                'candidate': {
                  'sdpMLineIndex': candidate.sdpMLineIndex,
                  'sdpMid': candidate.sdpMid,
                  'candidate': candidate.candidate,
                },
                'session_id': sessionId,
              }));
    };

    // 处理远程流移除。
    pc.onRemoveStream = (stream) {
      onRemoveRemoteStream?.call(newSession, stream);
      _remoteStreams.removeWhere((it) {
        return (it.id == stream.id);
      });
    };

    // 处理数据通道创建。
    pc.onDataChannel = (channel) {
      _addDataChannel(newSession, channel);
    };

    newSession.pc = pc;
    return newSession;
  }



  /// 向会话添加数据通道并设置事件处理程序。
  ///
  /// [session]: 要添加数据通道的会话。
  /// [channel]: 要添加的数据通道。
  void _addDataChannel(Session session, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (RTCDataChannelMessage data) {
      onDataChannelMessage?.call(session, channel, data);
    };
    session.dc = channel;
    onDataChannel?.call(session, channel);
  }

  /// 为会话创建数据通道。
  ///
  /// [session]: 要创建数据通道的会话。
  /// [label]: 数据通道的标签（默认为'fileTransfer'）。
  Future<void> _createDataChannel(Session session,
      {label = 'fileTransfer'}) async {
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..maxRetransmits = 30;
    RTCDataChannel channel =
    await session.pc!.createDataChannel(label, dataChannelDict);
    _addDataChannel(session, channel);
  }

  /// 为会话创建offer并发送给对等方。
  ///
  /// [session]: 要创建offer的会话。
  /// [media]: 用于offer的媒体类型。
  Future<void> _createOffer(Session session, String media) async {
    try {
      RTCSessionDescription s =
      await session.pc!.createOffer(media == 'data' ? _dcConstraints : {});
      await session.pc!.setLocalDescription(_fixSdp(s));
      _send('offer', {
        'to': session.pid,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': session.sid,
        'media': media,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  /// 通过修改profile-level-id来修复SDP描述。
  ///
  /// [s]: 原始的SDP描述。
  ///
  /// 返回修改后的SDP描述。
  RTCSessionDescription _fixSdp(RTCSessionDescription s) {
    var sdp = s.sdp;

    // 强制使用H264编码
    sdp = sdp!.replaceAll('profile-level-id=640c1f', 'profile-level-id=42e01f'); // Baseline profile

    // 调整编解码器优先级
    sdp = sdp.replaceAll(
        'a=rtpmap:100 VP8/90000',
        'a=rtpmap:100 H264/90000\r\na=fmtp:100 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f'
    );

    // H264是首选编码
    sdp = sdp.replaceAllMapped(RegExp(r'm=video.*'), (match) {
      return match.group(0)!
          .replaceAll('VP8', 'H264')
          .replaceAll('VP9', 'H264');
    });

    return RTCSessionDescription(sdp, s.type);
  }


  /// 为会话创建answer并发送给对等方。
  ///
  /// [session]: 要创建answer的会话。
  /// [media]: 用于answer的媒体类型。
  Future<void> _createAnswer(Session session, String media) async {
    try {
      RTCSessionDescription s =
      await session.pc!.createAnswer(media == 'data' ? _dcConstraints : {});
      await session.pc!.setLocalDescription(_fixSdp(s));
      _send('answer', {
        'to': session.pid,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': session.sid,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  /// 发送带有指定事件和数据的WebSocket消息。
  ///
  /// [event]: 要发送的事件类型。
  /// [data]: 要随事件发送的数据。
  _send(event, data) {
    var request = Map();
    request["type"] = event;
    request["data"] = data;
    _socket?.send(_encoder.convert(request));
  }

  /// 通过停止和释放本地流以及关闭对等连接来清理所有会话。
  Future<void> _cleanSessions() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream!.dispose();
      _localStream = null;
    }
    _sessions.forEach((key, sess) async {
      await sess.pc?.close();
      await sess.dc?.close();
    });
    _sessions.clear();
  }

  /// 关闭与指定对等方ID关联的会话。
  ///
  /// [peerId]: 要关闭会话的对等方ID。
  void _closeSessionByPeerId(String peerId) {
    var session;
    _sessions.removeWhere((String key, Session sess) {
      var ids = key.split('-');
      session = sess;
      return peerId == ids[0] || peerId == ids[1];
    });
    if (session != null) {
      _closeSession(session);
      onCallStateChange?.call(session, CallState.CallStateBye);
    }
  }

  /// 关闭指定的会话，停止并释放本地流，关闭对等连接和数据通道。
  Future<void> _closeSession(Session session) async {
    _localStream?.getTracks().forEach((element) async {
      await element.stop();
    });
    await _localStream?.dispose();
    _localStream = null;

    await session.pc?.close();
    await session.dc?.close();
    _senders.clear();
    _videoSource = VideoSource.Camera;
  }
}
