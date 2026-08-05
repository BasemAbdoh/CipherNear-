import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'dart:convert';
import 'dart:async';

class P2PManager {
  FlutterP2pHost? _host;
  FlutterP2pClient? _client;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _clientListSubscription;
  
  Function(String)? onMessageReceived;
  Function(String)? onDeviceConnected;
  Function(List<BleDiscoveredDevice>)? onPeersDiscovered;
  Function(String)? onGroupCreated;
  Function(List<dynamic>)? onClientsChanged;
  
  bool _isHost = false;

  // تهيئة كـ Host (مجموعة P2P)
  Future<void> initAsHost() async {
    _host = FlutterP2pHost();
    await _host!.initialize();
    _isHost = true;
    
    // الاستماع للرسائل الواردة
    _messageSubscription = _host!.streamReceivedTexts().listen((message) {
      print('Host استلم رسالة: $message');
      onMessageReceived?.call(message);
    }, onError: (error) {
      print('خطأ في استقبال الرسائل للـ Host: $error');
    });
    
    // الاستماع لتغييرات قائمة العملاء المتصلين
    _clientListSubscription = _host!.streamClientList().listen((clients) {
      print('Host: تغيير في قائمة العملاء: $clients');
      onClientsChanged?.call(clients);
    }, onError: (error) {
      print('خطأ في استماع قائمة العملاء: $error');
    });
  }

  // تهيئة كـ Client (للبحث والاتصال)
  Future<void> initAsClient() async {
    _client = FlutterP2pClient();
    await _client!.initialize();
    _isHost = false;
    
    // الاستماع للرسائل الواردة
    _messageSubscription = _client!.streamReceivedTexts().listen((message) {
      print('Client استلم رسالة: $message');
      onMessageReceived?.call(message);
    }, onError: (error) {
      print('خطأ في استقبال الرسائل للـ Client: $error');
    });
  }

  // بدء اكتشاف الأجهزة القريبة (Client فقط)
  Future<void> startDiscovery() async {
    if (_client == null) {
      await initAsClient();
    }
    
    _scanSubscription = await _client!.startScan((devices) {
      onPeersDiscovered?.call(devices);
    });
  }

  // إيقاف البحث
  Future<void> stopDiscovery() async {
    await _client?.stopScan();
    await _scanSubscription?.cancel();
  }

  // إنشاء مجموعة P2P (Host فقط)
  Future<bool> createGroup() async {
    if (_host == null) {
      await initAsHost();
    }
    
    try {
      await _host!.createGroup();
      onGroupCreated?.call("192.168.49.1"); // عنوان الـ Group Owner الافتراضي
      return true;
    } catch (e) {
      print("فشل إنشاء المجموعة: $e");
      return false;
    }
  }

  // الاتصال بجهاز (Client فقط)
  Future<bool> connectToDevice(BleDiscoveredDevice device) async {
    if (_client == null) {
      await initAsClient();
    }
    
    try {
      await _client!.connectWithDevice(device);
      onDeviceConnected?.call(device.deviceName);
      return true;
    } catch (e) {
      print("فشل الاتصال: $e");
      return false;
    }
  }

  // بدء خادم Socket (للتوافق مع الكود القديم)
  Future<void> startSocketServer() async {
    // في API الجديد، لا نحتاج لبدء socket منفصل
    // يتم التعامل معه تلقائياً عند الاتصال
    print("Socket server جاهز للاتصال");
  }

  // إرسال رسالة (للتوافق مع الكود القديم)
  Future<void> sendMessage(String message) async {
    await broadcastMessage(message);
  }

  // إرسال رسالة نصية للجميع
  Future<void> broadcastMessage(String message) async {
    try {
      if (_isHost && _host != null) {
        await _host!.broadcastText(message);
      } else if (!_isHost && _client != null) {
        await _client!.broadcastText(message);
      }
    } catch (e) {
      print("فشل إرسال الرسالة: $e");
    }
  }

  // إرسال رسالة منسقة (JSON)
  Future<void> sendStructuredMessage(Map<String, dynamic> data) async {
    try {
      final jsonMessage = jsonEncode(data);
      await broadcastMessage(jsonMessage);
    } catch (e) {
      print("فشل إرسال الرسالة المنسقة: $e");
    }
  }

  // إرسال رسالة لعميل محدد
  Future<void> sendMessageToClient(String message, String clientId) async {
    try {
      if (_isHost && _host != null) {
        await _host!.sendTextToClient(message, clientId);
      } else if (!_isHost && _client != null) {
        await _client!.sendTextToClient(message, clientId);
      }
    } catch (e) {
      print("فشل إرسال الرسالة للعميل: $e");
    }
  }

  // إيقاف الاتصال
  Future<void> disconnect() async {
    if (_isHost) {
      await _host?.removeGroup();
    } else {
      await _client?.disconnect();
    }
  }

  // الحصول على قائمة الأجهزة المتصلة
  Future<List<dynamic>> getConnectedDevices() async {
    if (_isHost && _host != null) {
      return _host!.clientList;
    } else if (!_isHost && _client != null) {
      return _client!.clientList;
    }
    return [];
  }

  // التحقق من حالة الاتصال
  bool isConnected() {
    if (_isHost && _host != null) {
      return _host!.clientList.isNotEmpty;
    } else if (!_isHost && _client != null) {
      return _client!.isConnected;
    }
    return false;
  }

  // تنظيف الموارد
  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _clientListSubscription?.cancel();
    await _host?.dispose();
    await _client?.dispose();
  }
}