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
import '../utils/sound_helper.dart';
import '../utils/chat_exporter.dart';
import '../widgets/chat_app_bar.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';

class GroupChatScreen extends StatefulWidget {
  final Group group;
  final P2PManager p2pManager;

  const GroupChatScreen({
    super.key,
    required this.group,
    required this.p2pManager,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final DBHelper _dbHelper = DBHelper();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  List<Message> _messages = [];
  bool _isLoading = true;

  Message? _repliedMessage;
  Message? _editingMessage;

  String _myUserId = '';
  String _myName = '';

  int _currentTtl = 0;
  String _searchQuery = '';
  int _searchResultIndex = 0;
  List<int> _searchResultIndices = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadGroupMessages();
    _setupP2PCallbacks();
    _messageController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    _myUserId = await ProfileHelper.getUserId();
    _myName = await ProfileHelper.getUserName();
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

  Future<void> _loadGroupMessages() async {
    final maps = await _dbHelper.getGroupMessages(widget.group.id);
    final loaded = maps.map((m) => Message.fromMap(m)).toList();

    if (mounted) {
      setState(() {
        _messages = loaded;
        _isLoading = false;
      });
      _scrollToBottom(animate: false);
    }
  }

  void _setupP2PCallbacks() {
    final originalCallback = widget.p2pManager.onMessageReceived;
    widget.p2pManager.onMessageReceived = (message) {
      originalCallback?.call(message);
      _handleIncomingMessage(message);
    };
  }

  Future<void> _handleIncomingMessage(String rawMessage) async {
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is Map) {
        final type = decoded['type']?.toString();
        final gId = decoded['groupId']?.toString();

        if (type == 'group_message' && gId == widget.group.id) {
          final senderId = decoded['senderId']?.toString() ?? 'unknown';
          final senderName = decoded['senderName']?.toString() ?? 'عضو';
          final content = decoded['content']?.toString() ?? '';
          final ts = decoded['timestamp']?.toString() ??
              DateTime.now().toIso8601String();
          final msgType = decoded['msgType']?.toString() ?? 'text';
          final isMe = senderId == _myUserId;
          String? mediaPath;

          if ((msgType == 'image' || msgType == 'video' || msgType == 'file') &&
              decoded['fileData'] != null) {
            final bytes = base64Decode(decoded['fileData']);
            final dir = await getApplicationDocumentsDirectory();
            final ext = msgType == 'image'
                ? 'jpg'
                : (msgType == 'video' ? 'mp4' : 'bin');
            final fileName = decoded['fileName'] ??
                '${DateTime.now().millisecondsSinceEpoch}.$ext';
            final savedFile = File('${dir.path}/$fileName');
            await savedFile.writeAsBytes(bytes);
            mediaPath = savedFile.path;
          }

          final incomingMsg = Message(
            peerId: senderId,
            content: content,
            isMe: isMe,
            timestamp: ts,
            messageType: msgType,
            mediaPath: mediaPath,
            groupId: gId,
            senderName: senderName,
            status: 2,
          );

          if (!isMe && mounted) {
            setState(() {
              _messages.add(incomingMsg);
            });
            SoundHelper.playReceiveSound();
            _scrollToBottom();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _sendGroupMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final timestamp = DateTime.now().toIso8601String();
    final ttlToSend = _currentTtl;

    final newMsg = Message(
      peerId: _myUserId,
      content: content,
      isMe: true,
      timestamp: timestamp,
      messageType: 'text',
      replyToMessage: _repliedMessage?.content,
      status: 0,
      ttl: ttlToSend,
      groupId: widget.group.id,
      senderName: _myName,
    );

    setState(() {
      _messages.add(newMsg);
      _messageController.clear();
      _currentTtl = 0;
    });

    await _dbHelper.insertGroupMessage(
      widget.group.id,
      _myUserId,
      _myName,
      content,
      true,
      timestamp,
    );

    final payload = jsonEncode({
      'type': 'group_message',
      'groupId': widget.group.id,
      'groupName': widget.group.name,
      'senderId': _myUserId,
      'senderName': _myName,
      'content': content,
      'timestamp': timestamp,
      'ttl': ttlToSend,
      'msgType': 'text',
    });

    await widget.p2pManager.sendMessage(payload);
    SoundHelper.playSendSound();

    setState(() => _repliedMessage = null);
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final XFile? image =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final timestamp = DateTime.now().toIso8601String();

    final newMsg = Message(
      peerId: _myUserId,
      content: 'صورة',
      isMe: true,
      timestamp: timestamp,
      messageType: 'image',
      mediaPath: image.path,
      groupId: widget.group.id,
      senderName: _myName,
    );

    setState(() {
      _messages.add(newMsg);
    });

    await _dbHelper.insertGroupMessage(
      widget.group.id,
      _myUserId,
      _myName,
      'صورة',
      true,
      timestamp,
      messageType: 'image',
      mediaPath: image.path,
    );

    _scrollToBottom();
    try {
      final bytes = await File(image.path).readAsBytes();
      final base64String = base64Encode(bytes);
      await widget.p2pManager.sendMessage(jsonEncode({
        'type': 'group_message',
        'groupId': widget.group.id,
        'groupName': widget.group.name,
        'senderId': _myUserId,
        'senderName': _myName,
        'content': 'صورة',
        'timestamp': timestamp,
        'msgType': 'image',
        'fileName': image.name,
        'fileData': base64String,
      }));
      SoundHelper.playSendSound();
    } catch (_) {}
  }

  Future<void> _pickVideo() async {
    final XFile? video =
        await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;
    final timestamp = DateTime.now().toIso8601String();

    final newMsg = Message(
      peerId: _myUserId,
      content: 'فيديو',
      isMe: true,
      timestamp: timestamp,
      messageType: 'video',
      mediaPath: video.path,
      groupId: widget.group.id,
      senderName: _myName,
    );

    setState(() {
      _messages.add(newMsg);
    });

    await _dbHelper.insertGroupMessage(
      widget.group.id,
      _myUserId,
      _myName,
      'فيديو',
      true,
      timestamp,
      messageType: 'video',
      mediaPath: video.path,
    );

    _scrollToBottom();
    try {
      final bytes = await File(video.path).readAsBytes();
      final base64String = base64Encode(bytes);
      await widget.p2pManager.sendMessage(jsonEncode({
        'type': 'group_message',
        'groupId': widget.group.id,
        'groupName': widget.group.name,
        'senderId': _myUserId,
        'senderName': _myName,
        'content': 'فيديو',
        'timestamp': timestamp,
        'msgType': 'video',
        'fileName': video.name,
        'fileData': base64String,
      }));
      SoundHelper.playSendSound();
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;
    final path = result.files.single.path;
    final filename = result.files.single.name;
    if (path == null) return;

    final timestamp = DateTime.now().toIso8601String();
    final newMsg = Message(
      peerId: _myUserId,
      content: filename,
      isMe: true,
      timestamp: timestamp,
      messageType: 'file',
      mediaPath: path,
      groupId: widget.group.id,
      senderName: _myName,
    );

    setState(() {
      _messages.add(newMsg);
    });

    await _dbHelper.insertGroupMessage(
      widget.group.id,
      _myUserId,
      _myName,
      filename,
      true,
      timestamp,
      messageType: 'file',
      mediaPath: path,
    );

    _scrollToBottom();
    try {
      final bytes = await File(path).readAsBytes();
      final base64String = base64Encode(bytes);
      await widget.p2pManager.sendMessage(jsonEncode({
        'type': 'group_message',
        'groupId': widget.group.id,
        'groupName': widget.group.name,
        'senderId': _myUserId,
        'senderName': _myName,
        'content': filename,
        'timestamp': timestamp,
        'msgType': 'file',
        'fileName': filename,
        'fileData': base64String,
      }));
      SoundHelper.playSendSound();
    } catch (_) {}
  }

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
    if (_searchResultIndices.isEmpty || !_scrollController.hasClients) return;
    final msgIndex = _searchResultIndices[_searchResultIndex];
    final targetPosition = (msgIndex / _messages.length) *
        _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      targetPosition,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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

  Future<void> _exportGroupChat() async {
    final path = await ChatExporter.exportToTxt(
      peerName: widget.group.name,
      myName: _myName,
      messages: _messages,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null
              ? 'تم تصدير محادثة المجموعة في مجلد NearChat/Exports ✅'
              : 'فشل التصدير',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor:
            path != null ? const Color(0xFF00C853) : const Color(0xFFe94560),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showDeleteGroupDialog() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('حذف المجموعة', style: TextStyle(color: Colors.white)),
        content: const Text('هل تريد حذف هذه المجموعة وكافة رسائلها؟',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _dbHelper.deleteGroup(widget.group.id);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = widget.p2pManager.activeConnectedIps.length + 1;

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
                peerDisplayName: widget.group.name,
                fallbackPeerName: 'مجموعة P2P',
                peerAvatarPath: null,
                isPeerConnected: true,
                lastSeen: '$activeCount أعضاء نشطين',
                onBackPressed: () => Navigator.pop(context),
                onClearChatPressed: _showDeleteGroupDialog,
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
                onExportChat: _exportGroupChat,
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFe94560)),
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.group,
                                    size: 80,
                                    color: Colors.white.withValues(alpha: 0.3)),
                                const SizedBox(height: 16),
                                Text(
                                  'أهلاً بك في مجموعة ${widget.group.name}! 👥',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      fontSize: 18),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'أرسل أول رسالة في المجموعة للبدء',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.3),
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              return MessageBubble(
                                message: _messages[index],
                                peerDisplayName: widget.group.name,
                                fallbackPeerName: 'عضو',
                                peerAvatarPath: null,
                                onSelectMessage: (_) {},
                                onReplyToMessage: (_) {},
                                onShowImagePreview: (_, __) {},
                                formatTime: _formatTime,
                                getTextDirection: _getTextDirection,
                                searchQuery: _searchQuery,
                              );
                            },
                          ),
              ),
              ChatInputBar(
                messageController: _messageController,
                editingMessage: _editingMessage,
                repliedMessage: _repliedMessage,
                peerName: widget.group.name,
                onCancelEdit: () => setState(() => _editingMessage = null),
                onCancelReply: () => setState(() => _repliedMessage = null),
                onSendMessage: _sendGroupMessage,
                onPickImage: _pickImage,
                onPickVideo: _pickVideo,
                onPickAudio: () {},
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
}
