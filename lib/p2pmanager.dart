import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../utils/crypto_helper.dart';

class P2PManager {
  FlutterP2pHost? _host;
  FlutterP2pClient? _client;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _clientListSubscription;

  // TCP Sockets للاتصال المباشر
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final List<Socket> _connectedSockets = [];
  final Set<String> _activeConnectedIps = {};
  Timer? _pingTimer;

  Function(String)? onMessageReceived;
  Function(String)? onDeviceConnected;
  Function(String)? onDeviceDisconnected;
  Function(List<BleDiscoveredDevice>)? onPeersDiscovered;
  Function(String)? onGroupCreated;
  Function(List<dynamic>)? onClientsChanged;

  bool _isHost = false;
  String? _localIp;

  bool get isHost => _isHost;
  String? get localIp => _localIp;
  Set<String> get activeConnectedIps => Set.unmodifiable(_activeConnectedIps);

  static const int port = 8888;
  static const String delimiter = '\n<END_MSG>\n';

  // ─────────────────────────────────────────────────────────────
  // الرسائل التي لا تُشفَّر — بروتوكول تبادل المفاتيح والـ Ping/Pong
  // ─────────────────────────────────────────────────────────────
  static bool _isHandshakeMessage(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        final type = decoded['type']?.toString() ?? '';
        return type == 'handshake' || type == 'ping' || type == 'pong';
      }
    } catch (_) {}
    return false;
  }

  void startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        await sendMessage(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  void stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // ─────────────────────────────────────────────────────────────
  // معالجة رسالة واردة: فك التشفير إن كانت مشفرة
  // ─────────────────────────────────────────────────────────────
  Future<void> _dispatchMessage(String rawMsg) async {
    String msg = rawMsg;

    // محاولة فك التشفير
    try {
      final parsed = jsonDecode(rawMsg);
      if (parsed is Map && parsed.containsKey('enc')) {
        final encData = parsed['enc']?.toString();
        if (encData != null && CryptoHelper.hasSharedKey) {
          final decrypted = await CryptoHelper.decrypt(encData);
          if (decrypted != null) {
            msg = decrypted;
          }
        }
      }
    } catch (_) {}

    // معالجة الـ Ping تلقائياً بإرسال Pong
    try {
      final decoded = jsonDecode(msg);
      if (decoded is Map && decoded['type'] == 'ping') {
        sendMessage(jsonEncode({'type': 'pong'}));
        return;
      }
    } catch (_) {}

    onMessageReceived?.call(msg);
  }

  Future<String?> getLocalIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _localIp = addr.address;
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('خطأ في تحديد الـ IP: $e');
    }
    return null;
  }

  bool isConnected() {
    return _connectedSockets.isNotEmpty ||
        (_clientSocket != null);
  }

  // ── TCP Socket Server ─────────────────────────────────
  Future<void> startSocketServer() async {
    try {
      await _serverSocket?.close();
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      print('Socket Server يعمل | IP: $_localIp | Port: $port');

      startPingTimer();

      _serverSocket!.listen((Socket clientSock) {
        final ip = clientSock.remoteAddress.address;
        print('اتصال جديد من: $ip');
        _connectedSockets.add(clientSock);
        _activeConnectedIps.add(ip);
        onDeviceConnected?.call(ip);
        _notifyClientsChanged();

        final buf = StringBuffer();
        clientSock.listen(
          (List<int> data) {
            buf.write(utf8.decode(data, allowMalformed: true));
            _processBuffer(buf, (msg) async {
              await _dispatchMessage(msg);
              _forwardToOtherSockets(msg, clientSock);
            });
          },
          onError: (_) => _removeSocket(clientSock),
          onDone: () => _removeSocket(clientSock),
          cancelOnError: true,
        );
      });
    } catch (e) {
      print('خطأ في Socket Server: $e');
    }
  }

  void _removeSocket(Socket s) {
    final ip = s.remoteAddress.address;
    _connectedSockets.remove(s);
    _activeConnectedIps.remove(ip);
    try {
      s.destroy();
    } catch (_) {}
    onDeviceDisconnected?.call(ip);
    _notifyClientsChanged();

    final disconnectMsg = jsonEncode({
      'type': 'peer_disconnected',
      'ip': ip,
    });
    sendMessage(disconnectMsg);
  }

  // ── Client → Host Socket Connection ───────────────────
  Future<bool> connectToHostIp(String hostIp) async {
    try {
      _clientSocket?.destroy();
      _clientSocket = null;

      print('جاري الاتصال بـ $hostIp:$port ...');
      _clientSocket = await Socket.connect(
        hostIp,
        port,
        timeout: const Duration(seconds: 8),
      );
      print('تم الاتصال بـ Host!');
      _activeConnectedIps.add(hostIp);
      onDeviceConnected?.call(hostIp);
      startPingTimer();

      final buf = StringBuffer();
      _clientSocket!.listen(
        (List<int> data) {
          buf.write(utf8.decode(data, allowMalformed: true));
          _processBuffer(buf, (msg) => _dispatchMessage(msg));
        },
        onError: (_) {
          _activeConnectedIps.remove(hostIp);
          _clientSocket?.destroy();
          _clientSocket = null;
          onDeviceDisconnected?.call(hostIp);
        },
        onDone: () {
          _activeConnectedIps.remove(hostIp);
          _clientSocket?.destroy();
          _clientSocket = null;
          onDeviceDisconnected?.call(hostIp);
        },
        cancelOnError: true,
      );
      return true;
    } catch (e) {
      print('فشل الاتصال بـ $hostIp: $e');
      return false;
    }
  }

  // ── Message Framing ───────────────────────────────────
  void _processBuffer(StringBuffer buf, Function(String) onMsg) {
    String s = buf.toString();
    while (s.contains(delimiter)) {
      final idx = s.indexOf(delimiter);
      final msg = s.substring(0, idx);
      s = s.substring(idx + delimiter.length);
      buf..clear()..write(s);
      if (msg.isNotEmpty) onMsg(msg);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // الإرسال: يُشفَّر تلقائياً إلا رسائل المصافحة (handshake) والـ ping
  // ─────────────────────────────────────────────────────────────
  Future<void> sendMessage(String message) async {
    String outMsg = message;

    if (!_isHandshakeMessage(message) && CryptoHelper.hasSharedKey) {
      final encrypted = await CryptoHelper.encrypt(message);
      if (encrypted != null) {
        outMsg = jsonEncode({'enc': encrypted});
      }
    }

    final bytes = utf8.encode(
      outMsg.endsWith(delimiter) ? outMsg : '$outMsg$delimiter',
    );

    if (_isHost) {
      for (final s in List<Socket>.from(_connectedSockets)) {
        try {
          s.add(bytes);
        } catch (_) {}
      }
    } else {
      try {
        _clientSocket?.add(bytes);
      } catch (_) {}
    }
  }

  void _forwardToOtherSockets(String message, Socket sender) {
    if (_connectedSockets.length <= 1) return;
    final bytes = utf8.encode(
      message.endsWith(delimiter) ? message : '$message$delimiter',
    );
    for (final s in _connectedSockets) {
      if (s != sender) {
        try {
          s.add(bytes);
        } catch (_) {}
      }
    }
  }

  void _notifyClientsChanged() {
    final list = _connectedSockets
        .map((s) =>
            {'id': s.remoteAddress.address, 'name': s.remoteAddress.address})
        .toList();
    onClientsChanged?.call(list);
  }

  // ── P2P Discovery ─────────────────────────────────────
  Future<void> startDiscovery() async {
    try {
      _client ??= FlutterP2pClient();
      _scanSubscription = await _client!.startScan((devices) {
        onPeersDiscovered?.call(devices);
      });
    } catch (e) {
      print('خطأ في بدء البحث P2P: $e');
    }
  }

  Future<bool> connectToBleDevice(BleDiscoveredDevice device) async {
    try {
      _client ??= FlutterP2pClient();
      await _client!.connectWithDevice(device);
      _isHost = false;
      onDeviceConnected?.call(device.deviceName);
      return true;
    } catch (e) {
      print('فشل الاتصال عبر P2P BLE: $e');
      return false;
    }
  }

  Future<bool> createGroup() async {
    try {
      _host ??= FlutterP2pHost();
      await _host!.createGroup();
      _isHost = true;
      await getLocalIpAddress();
      await startSocketServer();
      onGroupCreated?.call(_localIp ?? '192.168.43.1');
      return true;
    } catch (e) {
      print('تنبيه P2P createGroup: $e');
      final hostIp = _localIp ?? '192.168.43.1';
      onGroupCreated?.call(hostIp);
      return true;
    }
  }

  Future<void> disconnect() async {
    stopPingTimer();
    _activeConnectedIps.clear();
    CryptoHelper.reset();
    try {
      await _serverSocket?.close();
      _serverSocket = null;
      _clientSocket?.destroy();
      _clientSocket = null;
      _connectedSockets.clear();
      await _scanSubscription?.cancel();
      await _clientListSubscription?.cancel();
      await _host?.removeGroup();
      await _client?.disconnect();
    } catch (e) {
      print('خطأ في إنهاء الاتصال: $e');
    }
  }
}