import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import '../database_helper.dart';
import '../p2pmanager.dart';
import '../profile_helper.dart';
import '../notification_helper.dart';
import '../utils/sound_helper.dart';
import '../utils/chat_exporter.dart';
import '../widgets/chat_app_bar.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';
import '../chat_events.dart';

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final P2PManager p2pManager;

  const ChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.p2pManager,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final DBHelper _dbHelper = DBHelper();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  List<Message> _messages = [];
  bool _isLoading = true;
  Message? _selectedMessage;
  bool _showMessageOptions = false;

  Message? _repliedMessage;
  Message? _editingMessage;

  String _peerDisplayName = '';
  String? _peerAvatarPath;
  String? _peerLastSeen;
  bool _isPeerConnected = false;
  late String _activePeerId;

  // الميزات الجديدة: التدمير الذاتي والبحث
  int _currentTtl = 0;
  String _searchQuery = '';
  int _searchResultIndex = 0;
  List<int> _searchResultIndices = [];

  @override
  void initState() {
    super.initState();
    _activePeerId = widget.peerId;
    _peerDisplayName = widget.peerName;
    _isPeerConnected = widget.p2pManager.isConnected();
    _loadPeerInfo();
    _loadMessages(); // يُرسل read_ack_all مرة واحدة فقط هنا
    _setupP2PCallbacks();
    _sendMyProfileInfo(); // مرة واحدة فقط
    _messageController.addListener(() {
      if (mounted) setState(() {});
    });
    _startConnectionMonitor();

    // تسجيل callback لتحديث علامات الصح فوراً عند زر "تمييز كمقروءة" من الإشعار
    ChatEvents.onReadAckAllReceived = _handleReadAckAll;

    // تسجيل callback لإضافة رسائل المُرسلة من زر الرد في الإشعار
    ChatEvents.onNotificationReplySent = _handleNotificationReply;

    // تسجيل callback لتمييز الرسائل كمقروءة عند الضغط على "تمييز كمقروءة" من الإشعار
    ChatEvents.onMarkedReadFromNotification = _handleMarkedReadFromNotification;
  }

  @override
  void dispose() {
    if (ChatEvents.onReadAckAllReceived == _handleReadAckAll) {
      ChatEvents.onReadAckAllReceived = null;
    }
    if (ChatEvents.onNotificationReplySent == _handleNotificationReply) {
      ChatEvents.onNotificationReplySent = null;
    }
    if (ChatEvents.onMarkedReadFromNotification == _handleMarkedReadFromNotification) {
      ChatEvents.onMarkedReadFromNotification = null;
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleReadAckAll() {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m.isMe && m.status < 2) {
          return Message(
            id: m.id,
            peerId: m.peerId,
            content: m.content,
            isMe: m.isMe,
            timestamp: m.timestamp,
            messageType: m.messageType,
            status: 2,
            mediaPath: m.mediaPath,
            replyToMessage: m.replyToMessage,
            isEdited: m.isEdited,
            reaction: m.reaction,
            ttl: m.ttl,
          );
        }
        return m;
      }).toList();
    });
  }

  /// يستقبل رسائل مُرسلة من زر الرد في الإشعار ويضيفها للقائمة فوراً
  void _handleNotificationReply(Message msg) {
    if (!mounted) return;
    // تجاهل الرسالة إن كانت لمحادثة مختلفة
    if (msg.peerId != _activePeerId && msg.peerId != widget.peerId) return;
    setState(() {
      _messages.add(msg);
    });
    _scrollToBottom();
  }

  /// يُحدّث حالة قراءة الرسائل الواردة في الواجهة عند الضغط على "تمييز كمقروءة" من الإشعار
  void _handleMarkedReadFromNotification() {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((m) {
        // تمييز الرسائل الواردة (غير المُرسَلة مني) كمقروءة في الواجهة
        if (!m.isMe && m.status < 2) {
          return Message(
            id: m.id,
            peerId: m.peerId,
            content: m.content,
            isMe: m.isMe,
            timestamp: m.timestamp,
            messageType: m.messageType,
            status: 2,
            mediaPath: m.mediaPath,
            replyToMessage: m.replyToMessage,
            isEdited: m.isEdited,
            reaction: m.reaction,
            ttl: m.ttl,
            groupId: m.groupId,
            senderName: m.senderName,
          );
        }
        return m;
      }).toList();
    });
  }

  void _startConnectionMonitor() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      final connected = widget.p2pManager.isConnected();
      if (connected != _isPeerConnected) {
        setState(() => _isPeerConnected = connected);
      }
      return mounted;
    });
  }

  bool _isArabicText(String text) {
    if (text.trim().isEmpty) return true;
    final arabicRegex = RegExp(
        r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]');
    return arabicRegex.hasMatch(text);
  }

  ui.TextDirection _getTextDirection(String text) {
    return _isArabicText(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr;
  }

  Future<void> _loadPeerInfo() async {
    final peerMap = await _dbHelper.getPeer(_activePeerId);
    if (peerMap != null) {
      final peer = Peer.fromMap(peerMap);
      if (mounted) {
        setState(() {
          if (peer.name.isNotEmpty) _peerDisplayName = peer.name;
          _peerAvatarPath = peer.avatarPath;
          _peerLastSeen = peer.lastSeen;
        });
      }
    }
  }

  // جدولة التدمير الذاتي للرسالة
  void _scheduleDestruct(Message message) {
    if (message.ttl <= 0) return;
    try {
      final created = DateTime.parse(message.timestamp).toLocal();
      final elapsed = DateTime.now().difference(created).inSeconds;
      final remaining = message.ttl - elapsed;

      if (remaining <= 0) {
        _dbHelper.deleteMessageByTimestamp(message.timestamp, message.peerId);
        if (mounted) {
          setState(() =>
              _messages.removeWhere((m) => m.timestamp == message.timestamp));
        }
      } else {
        Future.delayed(Duration(seconds: remaining), () async {
          if (!mounted) return;
          await _dbHelper.deleteMessageByTimestamp(
              message.timestamp, message.peerId);
          setState(() =>
              _messages.removeWhere((m) => m.timestamp == message.timestamp));
        });
      }
    } catch (_) {}
  }

  // تحميل الرسائل مع معالجة الرسائل ذاتية التدمير
  Future<void> _loadMessages() async {
    final messageMaps = await _dbHelper.getMessages(_activePeerId);
    final loadedMessages =
        messageMaps.map((map) => Message.fromMap(map)).toList();

    if (mounted) {
      setState(() {
        _messages = loadedMessages;
        _isLoading = false;
      });
      _scrollToBottom(animate: false);
    }

    // فحص وجدولة الرسائل ذاتية التدمير
    for (final msg in loadedMessages) {
      if (msg.ttl > 0) {
        _scheduleDestruct(msg);
      }
    }

    await _dbHelper.markAllMessagesAsReadByPeer(_activePeerId);
    try {
      await widget.p2pManager
          .sendMessage(jsonEncode({'type': 'read_ack_all'}));
    } catch (_) {}
  }

  Future<void> _refreshMessagesOnly() async {
    final messageMaps = await _dbHelper.getMessages(_activePeerId);
    if (mounted) {
      setState(() {
        _messages = messageMaps.map((map) => Message.fromMap(map)).toList();
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendMyProfileInfo() async {
    try {
      final myId = await ProfileHelper.getUserId();
      final myName = await ProfileHelper.getUserName();
      final myAvatarPath = await ProfileHelper.getAvatarPath();
      String? base64Avatar;
      if (myAvatarPath != null && File(myAvatarPath).existsSync()) {
        final bytes = await File(myAvatarPath).readAsBytes();
        base64Avatar = base64Encode(bytes);
      }
      final payload = jsonEncode({
        'type': 'profile_info',
        'userId': myId,
        'name': myName,
        'avatarData': base64Avatar,
      });
      await widget.p2pManager.sendMessage(payload);
    } catch (e) {
      debugPrint('خطأ في إرسال بيانات البروفايل: $e');
    }
  }

  void _onReplyToMessage(Message message) {
    setState(() {
      _repliedMessage = message;
      _editingMessage = null;
    });
  }

  void _cancelReply() {
    setState(() => _repliedMessage = null);
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _messageController.clear();
    });
  }

  void _setupP2PCallbacks() {
    widget.p2pManager.onMessageReceived = (message) {
      debugPrint('ChatScreen استلم رسالة: $message');
      _handleIncomingMessage(message);
    };
    widget.p2pManager.onDeviceDisconnected = (ipOrUser) {
      if (mounted) setState(() => _isPeerConnected = false);
    };
  }

  // ── ردود الفعل (Emoji Reaction) ─────────────────────────
  Future<void> _sendReaction(Message message, String? emoji) async {
    await _dbHelper.updateMessageReaction(
        message.timestamp, _activePeerId, emoji);
    setState(() {
      final index =
          _messages.indexWhere((m) => m.timestamp == message.timestamp);
      if (index != -1) {
        final old = _messages[index];
        _messages[index] = Message(
          id: old.id,
          peerId: old.peerId,
          content: old.content,
          isMe: old.isMe,
          timestamp: old.timestamp,
          messageType: old.messageType,
          status: old.status,
          mediaPath: old.mediaPath,
          replyToMessage: old.replyToMessage,
          isEdited: old.isEdited,
          reaction: emoji,
          ttl: old.ttl,
        );
      }
    });

    try {
      await widget.p2pManager.sendMessage(jsonEncode({
        'type': 'reaction',
        'timestamp': message.timestamp,
        'reaction': emoji,
      }));
    } catch (_) {}
  }

  // ── البحث في المحادثات ──────────────────────────────
  void _updateSearchResults(String query) {
    setState(() {
      _searchQuery = query;
      if (query.trim().isEmpty) {
        _searchResultIndices = [];
        _searchResultIndex = 0;
      } else {
        _searchResultIndices = [];
        for (int i = 0; i < _messages.length; i++) {
          if (_messages[i]
              .content
              .toLowerCase()
              .contains(query.toLowerCase())) {
            _searchResultIndices.add(i);
          }
        }
        _searchResultIndex = 0;
        _scrollToSearchResult();
      }
    });
  }

  void _scrollToSearchResult() {
    if (_searchResultIndices.isEmpty) return;
    final msgIndex = _searchResultIndices[_searchResultIndex];
    if (!_scrollController.hasClients) return;
    final targetPosition = (msgIndex / _messages.length) *
        _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      targetPosition,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ── معالجة الرسائل الواردة ────────────────────────────
  Future<void> _handleIncomingMessage(String rawMessage) async {
    String messageContent = rawMessage;
    String type = 'text';
    String? timestamp;

    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is Map) {
        type = decoded['type']?.toString() ?? 'text';
        timestamp = decoded['timestamp']?.toString();

        // 1. حدث رد الفعل (Reaction)
        if (type == 'reaction') {
          final targetTs = decoded['timestamp']?.toString();
          final emoji = decoded['reaction']?.toString();
          if (targetTs != null) {
            final validEmoji = (emoji != null && emoji.isNotEmpty) ? emoji : null;
            await _dbHelper.updateMessageReaction(
                targetTs, _activePeerId, validEmoji);
            if (mounted) {
              setState(() {
                final index =
                    _messages.indexWhere((m) => m.timestamp == targetTs);
                if (index != -1) {
                  final old = _messages[index];
                  _messages[index] = Message(
                    id: old.id,
                    peerId: old.peerId,
                    content: old.content,
                    isMe: old.isMe,
                    timestamp: old.timestamp,
                    messageType: old.messageType,
                    status: old.status,
                    mediaPath: old.mediaPath,
                    replyToMessage: old.replyToMessage,
                    isEdited: old.isEdited,
                    reaction: validEmoji,
                    ttl: old.ttl,
                  );
                }
              });
            }
          }
          return;
        }

        // 2. رسالة البروفايل
        if (type == 'profile_info') {
          final peerUserId = decoded['userId']?.toString();
          final peerName = decoded['name']?.toString() ?? widget.peerName;
          final avatarData = decoded['avatarData']?.toString();
          String? peerAvatarPath;
          final targetId = (peerUserId != null && peerUserId.isNotEmpty)
              ? peerUserId
              : _activePeerId;

          if (avatarData != null && avatarData.isNotEmpty) {
            try {
              final bytes = base64Decode(avatarData);
              final dir = await getApplicationDocumentsDirectory();
              final savedFile = File('${dir.path}/${targetId}_avatar.jpg');
              await savedFile.writeAsBytes(bytes);
              peerAvatarPath = savedFile.path;
            } catch (_) {}
          }

          if (peerUserId != null && peerUserId.isNotEmpty) {
            await _dbHelper.migratePeerId(_activePeerId, peerUserId, peerName,
                avatarPath: peerAvatarPath);
            _activePeerId = peerUserId;
          } else {
            await _dbHelper.upsertPeer(_activePeerId, peerName,
                avatarPath: peerAvatarPath);
          }

          final nowIso = DateTime.now().toIso8601String();
          await _dbHelper.updatePeerLastSeen(_activePeerId, nowIso);

          if (mounted) {
            setState(() {
              _peerDisplayName = peerName;
              _peerLastSeen = nowIso;
              if (peerAvatarPath != null) _peerAvatarPath = peerAvatarPath;
            });
            _refreshMessagesOnly();
          }
          return;
        }

        // 3. تأكيد الاستلام
        if (type == 'delivery_ack') {
          final ackTs = decoded['timestamp']?.toString();
          if (ackTs != null) {
            await _dbHelper.updateMessageReadStatusByTimestamp(
                ackTs, widget.peerId, 1);
            if (mounted) {
              setState(() {
                final index =
                    _messages.indexWhere((m) => m.timestamp == ackTs);
                if (index != -1) {
                  final old = _messages[index];
                  _messages[index] = Message(
                    id: old.id,
                    peerId: old.peerId,
                    content: old.content,
                    isMe: old.isMe,
                    timestamp: old.timestamp,
                    messageType: old.messageType,
                    status: 1,
                    mediaPath: old.mediaPath,
                    replyToMessage: old.replyToMessage,
                    isEdited: old.isEdited,
                    reaction: old.reaction,
                    ttl: old.ttl,
                  );
                }
              });
            }
          }
          return;
        }

        // 4. تأكيد القراءة
        if (type == 'read_ack' || type == 'read_ack_all') {
          final ackTs = decoded['timestamp']?.toString();
          if (ackTs != null) {
            await _dbHelper.updateMessageReadStatusByTimestamp(
                ackTs, widget.peerId, 2);
          } else {
            await _dbHelper.markAllMessagesAsReadByPeer(widget.peerId);
          }
          if (mounted) {
            setState(() {
              _messages = _messages.map((m) {
                if (m.isMe && (ackTs == null || m.timestamp == ackTs)) {
                  return Message(
                    id: m.id,
                    peerId: m.peerId,
                    content: m.content,
                    isMe: m.isMe,
                    timestamp: m.timestamp,
                    messageType: m.messageType,
                    status: 2,
                    mediaPath: m.mediaPath,
                    replyToMessage: m.replyToMessage,
                    isEdited: m.isEdited,
                    reaction: m.reaction,
                    ttl: m.ttl,
                  );
                }
                return m;
              }).toList();
            });
          }
          return;
        }

        // 5. حذف رسالة
        if (type == 'delete_message') {
          final targetTs = decoded['timestamp']?.toString();
          if (targetTs != null) {
            await _dbHelper.deleteMessageByTimestamp(targetTs, widget.peerId);
            if (mounted) {
              setState(() =>
                  _messages.removeWhere((m) => m.timestamp == targetTs));
            }
          }
          return;
        }

        // 6. تعديل رسالة
        if (type == 'edit_message') {
          final targetTs = decoded['timestamp']?.toString();
          final newContent = decoded['newContent']?.toString();
          if (targetTs != null && newContent != null) {
            await _dbHelper.updateMessageContentAndEdited(
                targetTs, widget.peerId, newContent);
            if (mounted) {
              setState(() {
                final index =
                    _messages.indexWhere((m) => m.timestamp == targetTs);
                if (index != -1) {
                  final old = _messages[index];
                  _messages[index] = Message(
                    id: old.id,
                    peerId: old.peerId,
                    content: newContent,
                    isMe: old.isMe,
                    timestamp: old.timestamp,
                    messageType: old.messageType,
                    isEdited: true,
                    mediaPath: old.mediaPath,
                    replyToMessage: old.replyToMessage,
                    reaction: old.reaction,
                    ttl: old.ttl,
                  );
                }
              });
            }
          }
          return;
        }

        // 7. رسالة نصية أو وسائط جديدة
        messageContent = decoded['content'] ?? rawMessage;
        final replyTo = decoded['replyTo']?.toString();
        final ttl = (decoded['ttl'] as num?)?.toInt() ?? 0;
        String? mediaPath;

        if ((type == 'image' || type == 'video' || type == 'file') &&
            decoded['fileData'] != null) {
          final bytes = base64Decode(decoded['fileData']);
          final dir = await getApplicationDocumentsDirectory();
          final ext = type == 'image'
              ? 'jpg'
              : (type == 'video' ? 'mp4' : 'bin');
          final fileName = decoded['fileName'] ??
              '${DateTime.now().millisecondsSinceEpoch}.$ext';
          final savedFile = File('${dir.path}/$fileName');
          await savedFile.writeAsBytes(bytes);
          mediaPath = savedFile.path;
        }

        timestamp ??= DateTime.now().toIso8601String();
        final isCurrentChatOpen =
            mounted && ModalRoute.of(context)?.isCurrent == true;
        final statusToSave = isCurrentChatOpen ? 2 : 1;

        final incomingMsg = Message(
          peerId: _activePeerId,
          content: messageContent,
          isMe: false,
          timestamp: timestamp!,
          messageType: type,
          mediaPath: mediaPath,
          replyToMessage: replyTo,
          status: statusToSave,
          ttl: ttl,
        );

        if (mounted) {
          setState(() {
            _messages.add(incomingMsg);
          });
        }

        await _dbHelper.insertMessage(_activePeerId, messageContent, false,
            timestamp,
            messageType: type,
            mediaPath: mediaPath,
            replyToMessage: replyTo,
            ttl: ttl);
        await _dbHelper.updateMessageReadStatusByTimestamp(
            timestamp, _activePeerId, statusToSave);

        // جدولة التدمير الذاتي للرسالة المستلمة إذا كانت ذات مهلة
        if (ttl > 0) {
          _scheduleDestruct(incomingMsg);
        }

        // تشغيل صوت الاستلام
        SoundHelper.playReceiveSound();

        // إرسال تأكيد الاستلام والقراءة
        try {
          await widget.p2pManager.sendMessage(jsonEncode({
            'type': 'delivery_ack',
            'timestamp': timestamp,
          }));
        } catch (_) {}

        if (isCurrentChatOpen) {
          try {
            await widget.p2pManager.sendMessage(jsonEncode({
              'type': 'read_ack',
              'timestamp': timestamp,
            }));
          } catch (_) {}
        } else {
          const supportedNotifTypes = {
            'text',
            'image',
            'video',
            'audio',
            'file'
          };
          if (supportedNotifTypes.contains(type)) {
            final notifBody = type == 'text'
                ? messageContent
                : (type == 'image'
                    ? '📷 صورة'
                    : (type == 'video'
                        ? '🎥 فيديو'
                        : (type == 'audio'
                            ? '🎵 رسالة صوتية'
                            : '📁 ملف: $messageContent')));
            NotificationHelper.showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: _peerDisplayName.isNotEmpty
                  ? _peerDisplayName
                  : widget.peerName,
              body: notifBody,
              payload: jsonEncode({
                'peerId': _activePeerId,
                'peerName': _peerDisplayName.isNotEmpty
                    ? _peerDisplayName
                    : widget.peerName,
              }),
            );
          }
        }

        _scrollToBottom();
        return;
      }
    } catch (_) {
      messageContent = rawMessage;
    }

    // رسالة نصية غير JSON
    timestamp ??= DateTime.now().toIso8601String();
    final plainMsg = Message(
      peerId: _activePeerId,
      content: messageContent,
      isMe: false,
      timestamp: timestamp!,
      messageType: 'text',
    );
    if (mounted) {
      setState(() {
        _messages.add(plainMsg);
      });
    }
    await _dbHelper.insertMessage(
        _activePeerId, messageContent, false, timestamp);
    SoundHelper.playReceiveSound();
    _scrollToBottom();
  }

  // ── الإرسال ──────────────────────────────────────────
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    if (_editingMessage != null) {
      final targetTimestamp = _editingMessage!.timestamp;
      setState(() {
        final index =
            _messages.indexWhere((m) => m.timestamp == targetTimestamp);
        if (index != -1) {
          final oldMsg = _messages[index];
          _messages[index] = Message(
            id: oldMsg.id,
            peerId: oldMsg.peerId,
            content: content,
            isMe: oldMsg.isMe,
            timestamp: oldMsg.timestamp,
            messageType: oldMsg.messageType,
            status: oldMsg.status,
            mediaPath: oldMsg.mediaPath,
            replyToMessage: oldMsg.replyToMessage,
            isEdited: true,
            reaction: oldMsg.reaction,
            ttl: oldMsg.ttl,
          );
        }
        _editingMessage = null;
        _messageController.clear();
      });
      await _dbHelper.updateMessageContentAndEdited(
          targetTimestamp, widget.peerId, content);
      try {
        await widget.p2pManager.sendMessage(jsonEncode({
          'type': 'edit_message',
          'timestamp': targetTimestamp,
          'newContent': content,
        }));
      } catch (e) {
        debugPrint('خطأ في إرسال أمر التعديل: $e');
      }
      return;
    }

    final timestamp = DateTime.now().toIso8601String();
    final ttlToSend = _currentTtl;

    final newMsg = Message(
      peerId: widget.peerId,
      content: content,
      isMe: true,
      timestamp: timestamp,
      messageType: 'text',
      replyToMessage: _repliedMessage?.content,
      status: 0,
      ttl: ttlToSend,
    );

    setState(() {
      _messages.add(newMsg);
      _messageController.clear();
      _currentTtl = 0; // إعادة تعيين الـ TTL بعد الإرسال
    });

    await _dbHelper.insertMessage(widget.peerId, content, true, timestamp,
        replyToMessage: _repliedMessage?.content, ttl: ttlToSend);

    if (ttlToSend > 0) {
      _scheduleDestruct(newMsg);
    }

    final myUserId = await ProfileHelper.getUserId();
    final myName = await ProfileHelper.getUserName();
    final payload = jsonEncode({
      'type': 'text',
      'content': content,
      'timestamp': timestamp,
      'replyTo': _repliedMessage?.content,
      'senderId': myUserId,
      'senderName': myName,
      'ttl': ttlToSend,
    });
    await widget.p2pManager.sendMessage(payload);
    SoundHelper.playSendSound();

    setState(() => _repliedMessage = null);
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery, imageQuality: 75);
    if (image == null) return;
    final timestamp = DateTime.now().toIso8601String();
    final ttlToSend = _currentTtl;

    final newMsg = Message(
      peerId: _activePeerId,
      content: 'صورة',
      isMe: true,
      timestamp: timestamp,
      messageType: 'image',
      mediaPath: image.path,
      ttl: ttlToSend,
    );

    setState(() {
      _messages.add(newMsg);
      _currentTtl = 0;
    });

    await _dbHelper.insertMessage(widget.peerId, 'صورة', true, timestamp,
        messageType: 'image', mediaPath: image.path, ttl: ttlToSend);

    if (ttlToSend > 0) {
      _scheduleDestruct(newMsg);
    }

    _scrollToBottom();
    try {
      final myUserId = await ProfileHelper.getUserId();
      final myName = await ProfileHelper.getUserName();
      final bytes = await File(image.path).readAsBytes();
      final base64String = base64Encode(bytes);
      await widget.p2pManager.sendMessage(jsonEncode({
        'type': 'image',
        'content': 'صورة',
        'timestamp': timestamp,
        'fileName': image.name,
        'fileData': base64String,
        'senderId': myUserId,
        'senderName': myName,
        'replyTo': _repliedMessage?.content,
        'ttl': ttlToSend,
      }));
      SoundHelper.playSendSound();
    } catch (e) {
      debugPrint('خطأ في إرسال الصورة: $e');
    }
    setState(() => _repliedMessage = null);
  }

  Future<void> _pickVideo() async {
    final XFile? video =
        await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;
    final timestamp = DateTime.now().toIso8601String();
    final ttlToSend = _currentTtl;

    final newMsg = Message(
      peerId: widget.peerId,
      content: 'فيديو',
      isMe: true,
      timestamp: timestamp,
      messageType: 'video',
      mediaPath: video.path,
      ttl: ttlToSend,
    );

    setState(() {
      _messages.add(newMsg);
      _currentTtl = 0;
    });

    await _dbHelper.insertMessage(widget.peerId, 'فيديو', true, timestamp,
        messageType: 'video', mediaPath: video.path, ttl: ttlToSend);

    if (ttlToSend > 0) {
      _scheduleDestruct(newMsg);
    }

    _scrollToBottom();
    try {
      final bytes = await File(video.path).readAsBytes();
      final base64String = base64Encode(bytes);
      await widget.p2pManager.sendMessage(jsonEncode({
        'type': 'video',
        'content': 'فيديو',
        'timestamp': timestamp,
        'fileName': video.name,
        'fileData': base64String,
        'replyTo': _repliedMessage?.content,
        'ttl': ttlToSend,
      }));
      SoundHelper.playSendSound();
    } catch (e) {
      debugPrint('خطأ في إرسال الفيديو: $e');
    }
    setState(() => _repliedMessage = null);
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      final path = result.files.single.path;
      final filename = result.files.single.name;
      if (path != null) {
        final timestamp = DateTime.now().toIso8601String();
        final ttlToSend = _currentTtl;

        final newMsg = Message(
          peerId: widget.peerId,
          content: filename,
          isMe: true,
          timestamp: timestamp,
          messageType: 'file',
          mediaPath: path,
          ttl: ttlToSend,
        );

        setState(() {
          _messages.add(newMsg);
          _currentTtl = 0;
        });

        await _dbHelper.insertMessage(widget.peerId, filename, true, timestamp,
            messageType: 'file', mediaPath: path, ttl: ttlToSend);

        if (ttlToSend > 0) {
          _scheduleDestruct(newMsg);
        }

        _scrollToBottom();
        try {
          final bytes = await File(path).readAsBytes();
          final base64String = base64Encode(bytes);
          await widget.p2pManager.sendMessage(jsonEncode({
            'type': 'file',
            'content': filename,
            'timestamp': timestamp,
            'fileName': filename,
            'fileData': base64String,
            'replyTo': _repliedMessage?.content,
            'ttl': ttlToSend,
          }));
          SoundHelper.playSendSound();
        } catch (e) {
          debugPrint('خطأ في إرسال الملف: $e');
        }
        setState(() => _repliedMessage = null);
      }
    }
  }

  Future<void> _pickAudio() async {
    FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null) {
      final path = result.files.single.path;
      if (path != null) {
        final timestamp = DateTime.now().toIso8601String();
        final ttlToSend = _currentTtl;

        final newMsg = Message(
          peerId: widget.peerId,
          content: 'مقطع صوتي',
          isMe: true,
          timestamp: timestamp,
          messageType: 'audio',
          mediaPath: path,
          ttl: ttlToSend,
        );

        setState(() {
          _messages.add(newMsg);
          _currentTtl = 0;
        });

        await _dbHelper.insertMessage(
            widget.peerId, 'مقطع صوتي', true, timestamp,
            messageType: 'audio', mediaPath: path, ttl: ttlToSend);

        if (ttlToSend > 0) {
          _scheduleDestruct(newMsg);
        }

        SoundHelper.playSendSound();
        _scrollToBottom();
      }
    }
  }

  void _selectMessage(Message message) {
    setState(() {
      _selectedMessage = message;
      _showMessageOptions = true;
    });
  }

  void _hideMessageOptions() {
    setState(() {
      _selectedMessage = null;
      _showMessageOptions = false;
    });
  }

  void _copyMessage(Message message) {
    Clipboard.setData(ClipboardData(text: message.content));
    _hideMessageOptions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم نسخ الرسالة',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1a1a2e),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _editMessage(Message message) {
    setState(() {
      _editingMessage = message;
      _repliedMessage = null;
      _messageController.text = message.content;
      _showMessageOptions = false;
    });
  }

  Future<void> _deleteMessage(Message message) async {
    final targetTimestamp = message.timestamp;
    await _dbHelper.deleteMessageByTimestamp(targetTimestamp, widget.peerId);
    setState(() {
      _messages.removeWhere((m) => m.timestamp == targetTimestamp);
      _showMessageOptions = false;
    });
    try {
      await widget.p2pManager.sendMessage(jsonEncode({
        'type': 'delete_message',
        'timestamp': targetTimestamp,
      }));
    } catch (e) {
      debugPrint('خطأ في إرسال أمر الحذف: $e');
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0) return;
      if (animate) {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  String _formatTime(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }

  Future<void> _exportChat() async {
    final myName = await ProfileHelper.getUserName();
    final peerName =
        _peerDisplayName.isNotEmpty ? _peerDisplayName : widget.peerName;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            const Text('تصدير المحادثة', style: TextStyle(color: Colors.white)),
        content: const Text('اختر صيغة التصدير:',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final path = await ChatExporter.exportToTxt(
                peerName: peerName,
                myName: myName,
                messages: _messages,
              );
              _showExportResult(path);
            },
            child: const Text('.txt نص',
                style: TextStyle(color: Colors.amberAccent)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final path = await ChatExporter.exportToJson(
                peerName: peerName,
                myName: myName,
                peerId: widget.peerId,
                messages: _messages,
              );
              _showExportResult(path);
            },
            child: const Text('.json بيانات',
                style: TextStyle(color: Color(0xFF29B6F6))),
          ),
        ],
      ),
    );
  }

  void _showExportResult(String? path) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(path != null ? Icons.check_circle : Icons.error,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              path != null
                  ? 'تم التصدير في مجلد NearChat/Exports ✅'
                  : 'فشل التصدير',
              style: const TextStyle(color: Colors.white),
            )),
          ],
        ),
        backgroundColor:
            path != null ? const Color(0xFF00C853) : const Color(0xFFe94560),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _showClearChatDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('خيارات الحذف', style: TextStyle(color: Colors.white)),
        content: const Text('ما هو الإجراء الذي تريد اتخاذه مع هذه المحادثة؟',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _dbHelper.deleteAllMessages(widget.peerId);
              if (mounted) setState(() => _messages.clear());
            },
            child: const Text('مسح الرسائل فقط',
                style: TextStyle(color: Colors.amberAccent)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _dbHelper.deletePeerAndAllMessages(widget.peerId);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حذف المحادثة بالكامل',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showImagePreview(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image,
                          color: Colors.white54, size: 64),
                      SizedBox(height: 8),
                      Text('تعذر تحميل الصورة',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          image: DecorationImage(
            image: const AssetImage('lib/images/شات سولف.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.45),
              BlendMode.darken,
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              ChatAppBar(
                peerDisplayName: _peerDisplayName,
                fallbackPeerName: widget.peerName,
                peerAvatarPath: _peerAvatarPath,
                isPeerConnected: _isPeerConnected,
                lastSeen: _peerLastSeen,
                onBackPressed: () => Navigator.pop(context),
                onClearChatPressed: _showClearChatDialog,
                onSearch: _updateSearchResults,
                onSearchClose: () => setState(() {
                  _searchQuery = '';
                  _searchResultIndices = [];
                }),
                searchResultCount: _searchResultIndices.length,
                currentSearchIndex: _searchResultIndex,
                onPrevResult: () => setState(() {
                  if (_searchResultIndices.isNotEmpty) {
                    _searchResultIndex = (_searchResultIndex -
                            1 +
                            _searchResultIndices.length) %
                        _searchResultIndices.length;
                    _scrollToSearchResult();
                  }
                }),
                onNextResult: () => setState(() {
                  if (_searchResultIndices.isNotEmpty) {
                    _searchResultIndex =
                        (_searchResultIndex + 1) % _searchResultIndices.length;
                    _scrollToSearchResult();
                  }
                }),
                onExportChat: _exportChat,
              ),
              if (_showMessageOptions) _buildMessageOptionsBar(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFe94560)),
                        ),
                      )
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              return MessageBubble(
                                message: _messages[index],
                                peerDisplayName: _peerDisplayName,
                                fallbackPeerName: widget.peerName,
                                peerAvatarPath: _peerAvatarPath,
                                onSelectMessage: _selectMessage,
                                onReplyToMessage: _onReplyToMessage,
                                onShowImagePreview: _showImagePreview,
                                formatTime: _formatTime,
                                getTextDirection: _getTextDirection,
                                onReaction: _sendReaction,
                                searchQuery: _searchQuery,
                              );
                            },
                          ),
              ),
              ChatInputBar(
                messageController: _messageController,
                editingMessage: _editingMessage,
                repliedMessage: _repliedMessage,
                peerName: widget.peerName,
                onCancelEdit: _cancelEdit,
                onCancelReply: _cancelReply,
                onSendMessage: _sendMessage,
                onPickImage: _pickImage,
                onPickVideo: _pickVideo,
                onPickAudio: _pickAudio,
                onPickFile: _pickFile,
                getTextDirection: _getTextDirection,
                selectedTtl: _currentTtl,
                onTtlChanged: (ttl) => setState(() => _currentTtl = ttl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.waving_hand,
              size: 80, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'أهلاً بك في فرفش free! 👋',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'أرسل أول رسالة للبدء',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageOptionsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFe94560),
        border: Border(
          bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            onPressed: () => _copyMessage(_selectedMessage!),
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'نسخ',
          ),
          if (_selectedMessage!.isMe &&
              _selectedMessage!.messageType == 'text')
            IconButton(
              onPressed: () => _editMessage(_selectedMessage!),
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: 'تعديل',
            ),
          IconButton(
            onPressed: () => _deleteMessage(_selectedMessage!),
            icon: const Icon(Icons.delete, color: Colors.white),
            tooltip: 'حذف',
          ),
          IconButton(
            onPressed: _hideMessageOptions,
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'إلغاء',
          ),
        ],
      ),
    );
  }
}
