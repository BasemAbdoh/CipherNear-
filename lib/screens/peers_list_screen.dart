import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../database_helper.dart';
import '../p2pmanager.dart';
import '../profile_helper.dart';
import '../notification_helper.dart';
import '../chat_events.dart';
import '../utils/crypto_helper.dart';
import '../utils/sound_helper.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'qr_scanner_screen.dart';

// Standalone Widgets
import '../widgets/app_drawer.dart';
import '../widgets/peers_header.dart';
import '../widgets/peer_tile.dart';
import '../widgets/connected_client_tile.dart';
import '../widgets/discovered_device_tile.dart';

// Standalone Dialogs & Sheets
import '../widgets/dialogs/quick_reply_dialog.dart';
import '../widgets/dialogs/success_connection_dialog.dart';
import '../widgets/dialogs/profile_image_dialog.dart';
import '../widgets/dialogs/edit_name_dialog.dart';
import '../widgets/dialogs/role_selection_dialog.dart';
import '../widgets/dialogs/connect_options_dialog.dart';
import '../widgets/dialogs/qr_code_dialog.dart';
import '../widgets/dialogs/delete_peer_dialog.dart';
import '../widgets/dialogs/host_options_sheet.dart';

class PeersListScreen extends StatefulWidget {
  const PeersListScreen({super.key});

  @override
  State<PeersListScreen> createState() => _PeersListScreenState();
}

class _PeersListScreenState extends State<PeersListScreen> {
  final P2PManager _p2pManager = P2PManager();
  final DBHelper _dbHelper = DBHelper();
  final ImagePicker _imagePicker = ImagePicker();

  List<Peer> _savedPeers = [];
  List<Group> _groups = [];
  List<BleDiscoveredDevice> _discoveredPeers = [];
  List<dynamic> _connectedClients = []; // قائمة العملاء المتصلين بالـ Host
  final Set<String> _connectedClientUserIds = {}; // userId الحقيقي لكل عميل متصل (للعلامة الخضراء)
  bool _isDiscovering = false;
  bool _isConnected = false;
  String? _selectedRole; // 'host' or 'client'
  String? _connectedHostId; // IP/Id المضيف المتصل به العميل حالياً

  // بيانات البروفايل
  String _userName = 'مستخدم';
  String? _userImagePath;

  @override
  void initState() {
    super.initState();
    _loadSavedPeers();
    _loadGroups();
    _setupP2PCallbacks();
    _requestPermissions();
    _loadUserProfile();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    NotificationHelper.onNotificationAction = (actionId, input, payload) async {
      String peerId = '';
      String peerName = 'الصديق';
      if (payload != null && payload.isNotEmpty) {
        try {
          final data = jsonDecode(payload);
          peerId = data['peerId'] ?? '';
          peerName = data['peerName'] ?? peerName;
        } catch (_) {}
      }

      if (actionId == 'mark_read') {
        // 1. تحديث قاعدة البيانات: تمييز رسائل هذا الشخص كمقروءة
        if (peerId.isNotEmpty) {
          await _dbHelper.markAllMessagesAsReadByPeer(peerId);
        }

        // 2. إرسال تأكيد القراءة للمرسل عبر P2P حتى يرى ✓✓ أزرق
        try {
          await _p2pManager.sendMessage(jsonEncode({'type': 'read_ack_all'}));
        } catch (e) {
          debugPrint('خطأ في إرسال read_ack_all من الإشعار: $e');
        }

        // 3. إخطار ChatScreen المفتوحة لتُحدِّث واجهتها فوراً دون إعادة تحميل
        ChatEvents.onMarkedReadFromNotification?.call();

      } else if (actionId == 'reply_action') {
        if (input != null && input.trim().isNotEmpty) {
          final text = input.trim();
          final timestamp = DateTime.now().toIso8601String();

          // جلب userId الخاص بنا لإرفاقه مع الرسالة
          final myId = await ProfileHelper.getUserId();
          final myName = await ProfileHelper.getUserName();

          final payloadData = jsonEncode({
            'type': 'text',
            'content': text,
            'timestamp': timestamp,
            'senderId': myId,
            'senderName': myName,
          });

          // 1. إرسال الرسالة عبر P2P مباشرة
          try {
            await _p2pManager.sendMessage(payloadData);
          } catch (e) {
            debugPrint('خطأ في إرسال الرد المباشر: $e');
          }

          // 2. تخزينها في قاعدة البيانات المحلية
          final targetPeerId = peerId.isNotEmpty
              ? peerId
              : (_savedPeers.isNotEmpty ? _savedPeers.last.id : 'unknown');
          await _dbHelper.insertMessage(
            targetPeerId,
            text,
            true,
            timestamp,
            messageType: 'text',
          );

          // 3. تحديث آخر رسالة في قائمة الأصدقاء
          await _dbHelper.updatePeer(targetPeerId, text, timestamp);
          await _loadSavedPeers();

          // 4. إخطار ChatScreen المفتوحة لتُضيف الرسالة فوراً
          final sentMsg = Message(
            peerId: targetPeerId,
            content: text,
            isMe: true,
            timestamp: timestamp,
            messageType: 'text',
            status: 0,
          );
          ChatEvents.onNotificationReplySent?.call(sentMsg);
        }
      }
    };
  }

  void _showQuickReplyDialog({
    required String peerId,
    required String peerName,
    String? initialText,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => QuickReplyDialog(
        peerName: peerName,
        initialText: initialText,
        onSendReply: (text) async {
          final timestamp = DateTime.now().toIso8601String();
          final payload = jsonEncode({
            'type': 'text',
            'content': text,
            'timestamp': timestamp,
          });

          // 1. إرسال الرسالة عبر الشبكة مباشرة
          await _p2pManager.sendMessage(payload);

          // 2. تخزينها في قاعدة البيانات المحلية
          await _dbHelper.insertMessage(
            peerId,
            text,
            true,
            timestamp,
            messageType: 'text',
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم إرسال الرد إلى $peerName بنجاح ⚡'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ];

    final statuses = await permissions.request();

    // طلب أذونات P2P من المكتبة مباشرة (مهم لعمل Wi-Fi Direct بشكل صحيح)
    try {
      final p2pHost = FlutterP2pHost();
      final p2pGranted = await p2pHost.askP2pPermissions();
      if (!p2pGranted) {
        debugPrint('فشل منح أذونات P2P عبر المكتبة');
      }
    } catch (e) {
      debugPrint('خطأ في طلب أذونات P2P: $e');
    }

    bool allGranted = statuses.values.every((status) => status.isGranted);
    if (!allGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('قد لا تعمل بعض الميزات لأنه تم رفض بعض الأذونات'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _setupP2PCallbacks() {
    _p2pManager.onPeersDiscovered = (peers) {
      if (mounted) {
        setState(() {
          _discoveredPeers = peers;
        });
      }
    };

    _p2pManager.onDeviceConnected = (deviceAddress) async {
      // لا ننشئ أي سجل بالـ IP هنا — نكتفي بإرسال المصافحة
      // وسيتولى onMessageReceived إنشاء/تحديث الـ Peer بالـ userId الحقيقي الثابت
      _sendHandshake();
    };

    _p2pManager.onGroupCreated = (address) {
      if (mounted) {
        setState(() {
          _isConnected = true;
          _isDiscovering = false;
        });
      }
    };

    _p2pManager.onClientsChanged = (clients) async {
      final previousCount = _connectedClients.length;
      if (mounted) {
        setState(() {
          _connectedClients = clients;
        });
      }

      // توجيه المضيف تلقائياً لشاشة الدردشة عند اتصال عميل جديد
      if (clients.isNotEmpty && clients.length > previousCount && _selectedRole == 'host') {
        final lastClient = clients.last;
        String clientId = '';
        String clientName = 'عميل متصل';

        if (lastClient is Map) {
          clientId = lastClient['id']?.toString() ?? lastClient['address']?.toString() ?? '';
          clientName = lastClient['name']?.toString() ?? clientName;
        } else if (lastClient is String) {
          clientId = lastClient;
          clientName = 'عميل ($lastClient)';
        }

        if (clientId.isNotEmpty) {
          // إرسال مصافحة الهوية الثابتة فور الاتصال بدون إنشاء peer مؤقت بالـ IP
          _sendHandshake();

          final existingPeerMap = await _dbHelper.getPeer(clientId);
          if (existingPeerMap != null && existingPeerMap['name'] != null) {
            clientName = existingPeerMap['name'];
          }

          if (mounted) {
            _showSuccessConnectionDialog(clientName);
          }
        }
      }
    };

    // معالجة تأكيدات القراءة/الاستلام والبروفايل والمصافحة في الخلفية
    _p2pManager.onMessageReceived = (rawMessage) async {
      try {
        final decoded = jsonDecode(rawMessage);
        if (decoded is! Map) return;
        final type = decoded['type']?.toString() ?? '';

        if (type == 'handshake' || type == 'profile_info') {
          final peerUserId = decoded['userId']?.toString();
          final peerName = decoded['name']?.toString() ?? 'صديق';
          final avatarData = decoded['avatarData']?.toString();
          String? peerAvatarPath;

          // ── تأسيس التشفير: استخلاص المفتاح المشترك من مفتاح المقابل العام ──
          if (type == 'handshake') {
            final peerPublicKey = decoded['publicKey']?.toString();
            if (peerPublicKey != null && peerPublicKey.isNotEmpty) {
              await CryptoHelper.deriveSharedKey(peerPublicKey);
              // أرسل مصافحة إن لم نكن المبادرين (الطرف الذي استقبل الاتصال)
              if (!CryptoHelper.hasSharedKey) {
                // لا مفتاح بعد — أرسل مصافحتي حتى يشتق الطرف الآخر
                _sendHandshake();
              }
            }
          }
          // ─────────────────────────────────────────────────────────────────────

          if (peerUserId != null && peerUserId.isNotEmpty) {
            if (avatarData != null && avatarData.isNotEmpty) {
              try {
                final bytes = base64Decode(avatarData);
                final dir = await getApplicationDocumentsDirectory();
                final savedFile = File('${dir.path}/${peerUserId}_avatar.jpg');
                await savedFile.writeAsBytes(bytes);
                peerAvatarPath = savedFile.path;
              } catch (_) {}
            }

            if (_connectedHostId != null && _connectedHostId != peerUserId) {
              await _dbHelper.migratePeerId(_connectedHostId!, peerUserId, peerName, avatarPath: peerAvatarPath);
            }
            _connectedHostId = peerUserId;

            // تسجيل userId الحقيقي لتشغيل العلامة الخضراء لدى المضيف
            if (_selectedRole == 'host') {
              if (mounted) setState(() => _connectedClientUserIds.add(peerUserId));
            }

            final nowIso = DateTime.now().toIso8601String();
            await _dbHelper.updatePeerLastSeen(peerUserId, nowIso);

            await _dbHelper.upsertPeer(peerUserId, peerName, avatarPath: peerAvatarPath);
            await _loadSavedPeers();
          }
          return;
        } else if (type == 'delivery_ack') {
          final ts = decoded['timestamp']?.toString();
          if (ts != null) {
            await _dbHelper.updateDeliveryStatusByTimestamp(ts, 1);
          }
        } else if (type == 'read_ack') {
          final ts = decoded['timestamp']?.toString();
          if (ts != null) {
            await _dbHelper.updateDeliveryStatusByTimestamp(ts, 2);
          }
        } else if (type == 'read_ack_all') {
          await _dbHelper.markAllSentMessagesAsRead();
          // إخبار ChatScreen المفتوحة لتحديث علامات الصح فوراً
          ChatEvents.onReadAckAllReceived?.call();
        } else if (type == 'reaction') {
          final ts = decoded['timestamp']?.toString();
          final emoji = decoded['reaction']?.toString();
          if (ts != null) {
            final validEmoji = (emoji != null && emoji.isNotEmpty) ? emoji : null;
            await _dbHelper.updateMessageReaction(ts, _connectedHostId ?? 'unknown', validEmoji);
          }
        } else if (type == 'create_group') {
          final gId = decoded['groupId']?.toString();
          final gName = decoded['groupName']?.toString();
          if (gId != null && gName != null) {
            final group = Group(
                id: gId,
                name: gName,
                createdTime: DateTime.now().toIso8601String());
            await _dbHelper.insertGroup(group);
            await _loadGroups();
          }
        } else if (type == 'group_message') {
          final gId = decoded['groupId']?.toString();
          final senderId = decoded['senderId']?.toString() ?? 'unknown';
          final senderName = decoded['senderName']?.toString() ?? 'عضو';
          final content = decoded['content']?.toString() ?? '';
          final ts = decoded['timestamp']?.toString() ??
              DateTime.now().toIso8601String();
          if (gId != null) {
            await _dbHelper.insertGroupMessage(
                gId, senderId, senderName, content, false, ts);
            SoundHelper.playReceiveSound();
            final groupName = decoded['groupName']?.toString() ?? 'مجموعة';
            NotificationHelper.showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: groupName,
              body: '$senderName: $content',
              payload: jsonEncode({'groupId': gId, 'groupName': groupName}),
            );
          }
        } else if (type == 'text' || type == 'image' || type == 'video' ||
            type == 'audio' || type == 'file') {
          // رسالة محادثة حقيقية - احفظها وأظهر إشعاراً
          final content = decoded['content']?.toString() ?? rawMessage;
          final ts = decoded['timestamp']?.toString() ??
              DateTime.now().toIso8601String();
          final replyTo = decoded['replyTo']?.toString();

          // استخراج معرّف المرسل الحقيقي المرفق في حمولة الرسالة (payload)
          String peerId = decoded['senderId']?.toString() ?? '';
          String peerName = 'صديق';

          if (peerId.isNotEmpty) {
            final peerMap = await _dbHelper.getPeer(peerId);
            if (peerMap != null && peerMap['name'] != null && (peerMap['name'] as String).isNotEmpty) {
              peerName = peerMap['name'];
            }
          } else if (_connectedClients.isNotEmpty) {
            final lastClient = _connectedClients.last;
            if (lastClient is Map) {
              peerId = lastClient['id']?.toString() ?? lastClient['address']?.toString() ?? 'unknown_peer';
              peerName = lastClient['name']?.toString() ?? peerName;
            } else if (lastClient is String) {
              peerId = lastClient;
            }
          } else if (_savedPeers.isNotEmpty) {
            peerId = _savedPeers.last.id;
            peerName = _savedPeers.last.name;
          }

          if (peerId.isEmpty) peerId = 'unknown_peer';

          final ttl = (decoded['ttl'] as num?)?.toInt() ?? 0;

          await _dbHelper.insertMessage(peerId, content, false, ts,
              messageType: type, replyToMessage: replyTo, ttl: ttl);
          await _dbHelper.updateDeliveryStatusByTimestamp(ts, 1);

          // تشغيل صوت الاستلام في الخلفية
          SoundHelper.playReceiveSound();

          // إرسال تأكيد الاستلام
          try {
            await _p2pManager.sendMessage(jsonEncode({
              'type': 'delivery_ack',
              'timestamp': ts,
            }));
          } catch (_) {}

          // إشعار المستخدم
          final notifBody = type == 'text'
              ? content
              : (type == 'image'
                  ? '📷 صورة'
                  : (type == 'video'
                      ? '🎥 فيديو'
                      : (type == 'audio'
                          ? '🎵 رسالة صوتية'
                          : '📁 ملف: $content')));
          NotificationHelper.showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: peerName,
            body: notifBody,
            payload: jsonEncode({'peerId': peerId, 'peerName': peerName}),
          );
        }
      } catch (_) {}
    };
  }

  void _showSuccessConnectionDialog(String peerName) {
    if (!mounted) return;
    SuccessConnectionDialog.show(context, peerName);
  }

  Future<void> _loadSavedPeers() async {
    final peersData = await _dbHelper.getPeers();
    if (mounted) {
      setState(() {
        _savedPeers = peersData.map((map) => Peer.fromMap(map)).toList();
      });
    }
  }

  Future<void> _loadGroups() async {
    final groups = await _dbHelper.getGroups();
    if (mounted) {
      setState(() {
        _groups = groups;
      });
    }
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('إنشاء مجموعة جديدة',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'اسم المجموعة...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              await _createGroup(name);
            },
            child: const Text('إنشاء',
                style: TextStyle(color: Colors.amberAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroup(String groupName) async {
    final groupId = 'grp_${DateTime.now().millisecondsSinceEpoch}';
    final group = Group(
      id: groupId,
      name: groupName,
      createdTime: DateTime.now().toIso8601String(),
    );
    await _dbHelper.insertGroup(group);

    try {
      await _p2pManager.sendMessage(jsonEncode({
        'type': 'create_group',
        'groupId': groupId,
        'groupName': groupName,
        'createdBy': _userName,
      }));
    } catch (_) {}
    await _loadGroups();
  }

  Future<void> _loadUserProfile() async {
    final name = await ProfileHelper.getUserName();
    final avatar = await ProfileHelper.getAvatarPath();
    if (mounted) {
      setState(() {
        _userName = name;
        _userImagePath = avatar;
      });
    }
  }

  Future<void> _saveUserProfile() async {
    await ProfileHelper.saveProfile(_userName, _userImagePath);
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() {
          _userImagePath = image.path;
        });
        await _saveUserProfile();
      }
    } catch (e) {
      debugPrint('خطأ في اختيار الصورة: $e');
    }
  }

  void _showProfileImagePreview() {
    showDialog(
      context: context,
      builder: (context) => ProfileImageDialog(
        userName: _userName,
        userImagePath: _userImagePath,
        onPickImage: _pickImage,
      ),
    );
  }

  void _showEditNameDialog() {
    showDialog(
      context: context,
      builder: (context) => EditNameDialog(
        currentName: _userName,
        onSave: (newName) {
          setState(() {
            _userName = newName;
          });
          _saveUserProfile();
        },
      ),
    );
  }

  Future<void> _startDiscovery() async {
    _showRoleSelectionDialog();
  }

  void _showRoleSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => RoleSelectionDialog(
        onSelectHost: _startAsHost,
        onSelectClient: _startAsClient,
      ),
    );
  }

  Future<void> _startAsHost() async {
    setState(() {
      _isDiscovering = true;
      _selectedRole = 'host';
    });

    await _openHotspotSettings();
    await _p2pManager.createGroup();
    final hostIp = await _p2pManager.getLocalIpAddress() ?? '192.168.43.1';

    setState(() {
      _isConnected = true;
      _isDiscovering = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تشغيل المضيف! عنوان IP الخاص بك: $hostIp'),
          duration: const Duration(seconds: 3),
        ),
      );
      _showQRCode();
    }
  }

  Future<void> _startAsClient() async {
    setState(() {
      _isDiscovering = true;
      _selectedRole = 'client';
    });

    await _openWifiSettings();
    _showConnectOptionsDialog();
    await _p2pManager.startDiscovery();
  }

  void _showConnectOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => ConnectOptionsDialog(
        onOpenQRScanner: _openQRScanner,
        onConnectToIp: _connectToHostIp,
      ),
    );
  }

  Future<void> _connectToHostIp(String hostIp) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('جاري الاتصال بالمضيف $hostIp...')),
    );

    final success = await _p2pManager.connectToHostIp(hostIp);
    if (success) {
      _connectedHostId = hostIp;
      final existingPeer = await _dbHelper.getPeer(hostIp);
      String targetPeerName = 'مضيف متصل';
      if (existingPeer != null && existingPeer['name'] != null) {
        targetPeerName = existingPeer['name'];
      }

      setState(() {
        _isConnected = true;
        _isDiscovering = false;
      });

      _sendHandshake();

      if (mounted) {
        _showSuccessConnectionDialog(targetPeerName);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الاتصال بالـ IP: $hostIp. تأكد من تفعيل Hotspot على المضيف وأنهما على نفس الشبكة.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _connectToDevice(BleDiscoveredDevice device) async {
    final success = await _p2pManager.connectToBleDevice(device);
    if (success) {
      setState(() {
        _isConnected = true;
        _isDiscovering = false;
      });

      final existingPeer = await _dbHelper.getPeer(device.deviceAddress);
      String targetName = device.deviceName;
      if (existingPeer != null && existingPeer['name'] != null) {
        targetName = existingPeer['name'];
      }

      _sendHandshake();

      if (mounted) {
        _showSuccessConnectionDialog(targetName);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل الاتصال بالجهاز')),
      );
    }
  }

  Future<void> _sendHandshake() async {
    try {
      final myId = await ProfileHelper.getUserId();
      final myName = await ProfileHelper.getUserName();
      final avatarPath = await ProfileHelper.getAvatarPath();
      String? avatarData;
      if (avatarPath != null && File(avatarPath).existsSync()) {
        final bytes = await File(avatarPath).readAsBytes();
        avatarData = base64Encode(bytes);
      }
      // إرفاق مفتاحي العام لتأسيس التشفير بين الجهازين (ECDH)
      final myPublicKey = await CryptoHelper.getPublicKeyBase64();
      await _p2pManager.sendMessage(jsonEncode({
        'type': 'handshake',
        'userId': myId,
        'name': myName,
        'avatarData': avatarData,
        'publicKey': myPublicKey,
      }));
    } catch (e) {
      debugPrint('خطأ في إرسال المصافحة: $e');
    }
  }

  void _navigateToChat(String peerId, String peerName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          peerId: peerId,
          peerName: peerName,
          p2pManager: _p2pManager,
        ),
      ),
    ).then((_) {
      _setupP2PCallbacks();
      _loadSavedPeers();
    });
  }

  void _showDeleteDialog(Peer peer) {
    showDialog(
      context: context,
      builder: (_) => DeletePeerDialog(
        peer: peer,
        onClearMessagesOnly: () async {
          await _dbHelper.deleteAllMessages(peer.id);
          await _loadSavedPeers();
        },
        onDelete: () async {
          await _dbHelper.deletePeerAndAllMessages(peer.id);
          await _loadSavedPeers();
        },
      ),
    );
  }

  void _showQRCode() {
    final ip = _p2pManager.localIp;
    if (ip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم تحديد عنوان IP بعد')),
      );
      return;
    }

    final qrData = jsonEncode({'ip': ip, 'port': P2PManager.port});

    showDialog(
      context: context,
      builder: (ctx) => QRCodeDialog(
        ip: ip,
        qrData: qrData,
      ),
    );
  }

  Future<void> _openQRScanner() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى السماح بالوصول إلى الكاميرا لمسح الباركود')),
        );
      }
      return;
    }

    if (!mounted) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );

    if (result == null || !mounted) return;

    final ip = result['ip'] as String;
    _connectToHostIp(ip);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(
        userName: _userName,
        userImagePath: _userImagePath,
        onPickImage: _pickImage,
        onEditNameTap: _showEditNameDialog,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1a1a2e),
              Color(0xFF16213e),
              Color(0xFF0f3460),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              PeersHeader(
                userName: _userName,
                userImagePath: _userImagePath,
                isConnected: _isConnected,
                selectedRole: _selectedRole,
                onEditNameTap: _showEditNameDialog,
                onProfileImageTap: _showProfileImagePreview,
              ),
              Expanded(
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      _buildTabBar(),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildSavedPeersList(),
                            _buildGroupsList(),
                            _buildDiscoveredPeersList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        indicator: BoxDecoration(
          color: const Color(0xFFe94560),
          borderRadius: BorderRadius.circular(16),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey,
        tabs: const [
          Tab(text: 'المحادثات'),
          Tab(text: 'المجموعات'),
          Tab(text: 'الأجهزة القريبة'),
        ],
      ),
    );
  }

  Widget _buildSavedPeersList() {
    if (_savedPeers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد محادثات محفوظة',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _savedPeers.length,
      itemBuilder: (context, index) {
        final peer = _savedPeers[index];
        return PeerTile(
          peer: peer,
          isOnline: _isPeerOnline(peer),
          formattedTime: _formatTime(peer.lastMessageTime),
          onTap: () => _navigateToChat(peer.id, peer.name),
          onLongPress: () => _showDeleteDialog(peer),
        );
      },
    );
  }

  Widget _buildGroupsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF29B6F6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _showCreateGroupDialog,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('إنشاء مجموعة جديدة',
                style: TextStyle(color: Colors.white)),
          ),
        ),
        Expanded(
          child: _groups.isEmpty
              ? Center(
                  child: Text(
                    'لا توجد مجموعات حالياً',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 16,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    return Card(
                      color: Colors.white.withValues(alpha: 0.08),
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFe94560),
                          child: Icon(Icons.group, color: Colors.white),
                        ),
                        title: Text(group.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        subtitle: const Text('مجموعة P2P محلية',
                            style: TextStyle(color: Colors.white54)),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupChatScreen(
                                group: group,
                                p2pManager: _p2pManager,
                              ),
                            ),
                          ).then((_) => _loadGroups());
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  bool _isPeerOnline(Peer peer) {
    if (!_isConnected) return false;

    if (_p2pManager.activeConnectedIps.contains(peer.id) ||
        _connectedClientUserIds.contains(peer.id)) {
      return true;
    }

    if (_selectedRole == 'client') {
      return _p2pManager.isConnected() &&
          (_connectedHostId != null && peer.id == _connectedHostId);
    }

    if (_connectedClients.isEmpty) return false;
    return _connectedClients.any((client) {
      if (client is Map) {
        final id =
            client['id']?.toString() ?? client['address']?.toString() ?? '';
        return id == peer.id;
      } else if (client is String) {
        return client == peer.id;
      }
      return false;
    });
  }

  Widget _buildDiscoveredPeersList() {
    if (_selectedRole == 'host' && _isConnected) {
      final hostIp = _p2pManager.localIp ?? '192.168.43.1';
      if (_connectedClients.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.wifi_tethering,
                size: 80,
                color: Color(0xFFe94560),
              ),
              const SizedBox(height: 16),
              Text(
                'بانتظار اتصال الأجهزة بالـ Hotspot...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'عنوان IP الخاص بك: $hostIp',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFe94560),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: _showQRCode,
                icon: const Icon(Icons.qr_code, color: Colors.white, size: 22),
                label: const Text(
                  'عرض QR Code للاتصال',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      } else {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'الأجهزة المتصلة (${_connectedClients.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _connectedClients.length,
              itemBuilder: (context, index) {
                final client = _connectedClients[index];
                return ConnectedClientTile(
                  client: client,
                  index: index,
                  dbHelper: _dbHelper,
                  onNavigateToChat: _navigateToChat,
                );
              },
            ),
          ],
        );
      }
    }

    if (_selectedRole == 'client' && !_isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi,
              size: 80,
              color: Color(0xFFe94560),
            ),
            const SizedBox(height: 16),
            Text(
              'اتصل بالـ Hotspot للمضيف ثم اضغط اتصال',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFe94560),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: _openQRScanner,
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
              label: const Text(
                'مسح QR Code للاتصال',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _showConnectOptionsDialog,
              icon: const Icon(Icons.link, color: Colors.white54),
              label: const Text(
                'إدخال IP يدوياً',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isDiscovering) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'اضغط على الزر للبحث عن الأجهزة',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_discoveredPeers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFe94560)),
            ),
            const SizedBox(height: 16),
            Text(
              'جاري البحث عن الأجهزة...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _discoveredPeers.length,
      itemBuilder: (context, index) {
        final device = _discoveredPeers[index];
        return DiscoveredDeviceTile(
          device: device,
          onTap: () => _connectToDevice(device),
        );
      },
    );
  }

  void _showHostConnectedOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => HostOptionsSheet(
        onShowQRCode: _showQRCode,
        onDisconnect: () async {
          await _p2pManager.disconnect();
          final nowIso = DateTime.now().toIso8601String();
          if (_connectedHostId != null) {
            await _dbHelper.updatePeerLastSeen(_connectedHostId!, nowIso);
          }
          for (var clientId in _connectedClientUserIds) {
            await _dbHelper.updatePeerLastSeen(clientId, nowIso);
          }

          setState(() {
            _isConnected = false;
            _selectedRole = null;
            _connectedClientUserIds.clear();
            _connectedHostId = null;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم إنهاء الاتصال بنجاح')),
            );
          }
        },
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    if (_selectedRole == 'host' && _isConnected) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: FloatingActionButton(
          onPressed: _showHostConnectedOptions,
          backgroundColor: const Color(0xFFe94560),
          elevation: 8,
          child: const Icon(Icons.qr_code, color: Colors.white, size: 28),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: FloatingActionButton.extended(
        onPressed: _isDiscovering ? null : _startDiscovery,
        backgroundColor: const Color(0xFFe94560),
        icon: Icon(_isDiscovering ? Icons.hourglass_empty : Icons.search),
        label: Text(_isDiscovering ? 'جاري البحث...' : 'بحث عن أجهزة'),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }


  String _formatTime(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'الآن';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} د';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} س';
      } else {
        return '${dateTime.day}/${dateTime.month}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  Future<void> _openHotspotSettings() async {
    try {
      final hotspotUri = Uri.parse('android.settings.TETHER_SETTINGS');
      final locationUri = Uri.parse('android.settings.LOCATION_SOURCE_SETTINGS');

      if (await canLaunchUrl(hotspotUri)) {
        await launchUrl(hotspotUri);
      } else {
        final wifiUri = Uri.parse('android.settings.WIFI_SETTINGS');
        if (await canLaunchUrl(wifiUri)) {
          await launchUrl(wifiUri);
        }
      }

      await Future.delayed(const Duration(seconds: 1));
      if (await canLaunchUrl(locationUri)) {
        await launchUrl(locationUri);
      }
    } catch (e) {
      debugPrint('خطأ في فتح إعدادات Hotspot: $e');
    }
  }

  Future<void> _openWifiSettings() async {
    try {
      final wifiUri = Uri.parse('android.settings.WIFI_SETTINGS');
      final locationUri = Uri.parse('android.settings.LOCATION_SOURCE_SETTINGS');

      if (await canLaunchUrl(wifiUri)) {
        await launchUrl(wifiUri);
      }

      await Future.delayed(const Duration(seconds: 1));
      if (await canLaunchUrl(locationUri)) {
        await launchUrl(locationUri);
      }
    } catch (e) {
      debugPrint('خطأ في فتح إعدادات WiFi: $e');
    }
  }
}
