import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../database_helper.dart';
import '../p2pmanager.dart';

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
  Message? _selectedMessage; // الرسالة المحددة للتعديل/الحذف
  bool _showMessageOptions = false; // إظهار شريط الخيارات

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupP2PCallbacks();
  }

  void _setupP2PCallbacks() {
    widget.p2pManager.onMessageReceived = (message) {
      print('ChatScreen استلم رسالة: $message');
      _handleIncomingMessage(message);
    };
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });
    
    final messagesData = await _dbHelper.getMessages(widget.peerId);
    setState(() {
      _messages = messagesData.map((map) => Message.fromMap(map)).toList();
      _isLoading = false;
    });
    
    _scrollToBottom();
  }

  void _handleIncomingMessage(String message) {
    // تحليل الرسالة (يمكن أن تكون JSON أو نص عادي)
    final timestamp = DateTime.now().toIso8601String();
    
    setState(() {
      _messages.add(Message(
        peerId: widget.peerId,
        content: message,
        isMe: false,
        timestamp: timestamp,
        messageType: 'text',
      ));
    });
    
    // حفظ الرسالة في قاعدة البيانات
    _dbHelper.insertMessage(widget.peerId, message, false, timestamp).then((_) {
      print('تم حفظ الرسالة المستلمة في قاعدة البيانات');
    }).catchError((error) {
      print('خطأ في حفظ الرسالة المستلمة: $error');
    });
    
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final timestamp = DateTime.now().toIso8601String();
    
    setState(() {
      _messages.add(Message(
        peerId: widget.peerId,
        content: content,
        isMe: true,
        timestamp: timestamp,
        messageType: 'text',
      ));
      _messageController.clear();
    });

    // حفظ الرسالة في قاعدة البيانات
    await _dbHelper.insertMessage(widget.peerId, content, true, timestamp);
    
    // إرسال الرسالة عبر P2P
    await widget.p2pManager.sendMessage(content);
    
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    // TODO: إرسال الصورة عبر P2P (يتطلب تحويلها إلى base64 أو رفعها)
    // حالياً سنعرضها فقط محلياً
    final timestamp = DateTime.now().toIso8601String();
    
    setState(() {
      _messages.add(Message(
        peerId: widget.peerId,
        content: 'صورة',
        isMe: true,
        timestamp: timestamp,
        messageType: 'image',
        mediaPath: image.path,
      ));
    });

    await _dbHelper.insertMessage(
      widget.peerId, 
      'صورة', 
      true, 
      timestamp,
      messageType: 'image',
      mediaPath: image.path,
    );
    
    _scrollToBottom();
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    final timestamp = DateTime.now().toIso8601String();
    
    setState(() {
      _messages.add(Message(
        peerId: widget.peerId,
        content: 'فيديو',
        isMe: true,
        timestamp: timestamp,
        messageType: 'video',
        mediaPath: video.path,
      ));
    });

    await _dbHelper.insertMessage(
      widget.peerId, 
      'فيديو', 
      true, 
      timestamp,
      messageType: 'video',
      mediaPath: video.path,
    );
    
    _scrollToBottom();
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

  Future<void> _copyMessage(Message message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    _hideMessageOptions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ الرسالة')),
    );
  }

  Future<void> _editMessage(Message message) async {
    _messageController.text = message.content;
    _hideMessageOptions();
    
    // حذف الرسالة القديمة
    if (message.id != null) {
      await _dbHelper.deleteMessage(message.id!);
      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
      });
    }
  }

  Future<void> _deleteMessage(Message message) async {
    if (message.id != null) {
      await _dbHelper.deleteMessage(message.id!);
      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
      });
    }
    _hideMessageOptions();
  }

  Future<void> _markAsRead(Message message) async {
    if (message.id != null && !message.isRead) {
      await _dbHelper.updateMessageReadStatus(message.id!, true);
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          _messages[index] = Message(
            id: message.id,
            peerId: message.peerId,
            content: message.content,
            isMe: message.isMe,
            timestamp: message.timestamp,
            messageType: message.messageType,
            isRead: true,
            mediaPath: message.mediaPath,
          );
        }
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
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
              _buildAppBar(),
              if (_showMessageOptions) _buildMessageOptionsBar(),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFe94560)),
                        ),
                      )
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : _buildMessagesList(),
              ),
              _buildMessageInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFe94560), Color(0xFF0f3460)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.peerName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'متصل',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showClearChatDialog(),
            icon: Icon(
              Icons.delete_outline,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          SizedBox(height: 16),
          Text(
            'ابدأ المحادثة',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'أرسل رسالة للتواصل مع ${widget.peerName}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isMe = message.isMe;
    
    return GestureDetector(
      onLongPress: () => _selectMessage(message),
      onTap: () {
        if (!isMe && !message.isRead) {
          _markAsRead(message);
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMe) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFe94560), Color(0xFF0f3460)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                 constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isMe
                        ? LinearGradient(
                            colors: [Color(0xFFe94560), Color(0xFFc73e54)],
                          )
                        : LinearGradient(
                            colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.1)],
                          ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: isMe ? Radius.circular(20) : Radius.circular(4),
                      bottomRight: isMe ? Radius.circular(4) : Radius.circular(20),
                    ),
                    border: Border.all(
                      color: isMe ? Colors.transparent : Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(message.timestamp),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11,
                            ),
                          ),
                          if (isMe && message.isRead) ...[
                            SizedBox(width: 4),
                            Icon(
                              Icons.done_all,
                              color: Colors.greenAccent,
                              size: 12,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isMe) ...[
                SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0f3460), Color(0xFF16213e)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.check,
                      color: message.isRead ? Colors.greenAccent : Colors.white.withOpacity(0.5),
                      size: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageOptionsBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFFe94560),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            onPressed: () => _copyMessage(_selectedMessage!),
            icon: Icon(Icons.copy, color: Colors.white),
            tooltip: 'نسخ',
          ),
          IconButton(
            onPressed: () => _editMessage(_selectedMessage!),
            icon: Icon(Icons.edit, color: Colors.white),
            tooltip: 'تعديل',
          ),
          IconButton(
            onPressed: () => _deleteMessage(_selectedMessage!),
            icon: Icon(Icons.delete, color: Colors.white),
            tooltip: 'حذف',
          ),
          IconButton(
            onPressed: _hideMessageOptions,
            icon: Icon(Icons.close, color: Colors.white),
            tooltip: 'إلغاء',
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: PopupMenuButton<String>(
              icon: Icon(
                Icons.attach_file,
                color: Colors.white.withOpacity(0.7),
              ),
              color: Color(0xFF1a1a2e),
              onSelected: (value) {
                if (value == 'image') {
                  _pickImage();
                } else if (value == 'video') {
                  _pickVideo();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'image',
                  child: Row(
                    children: [
                      Icon(Icons.image, color: Colors.white),
                      SizedBox(width: 12),
                      Text('صورة', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'video',
                  child: Row(
                    children: [
                      Icon(Icons.videocam, color: Colors.white),
                      SizedBox(width: 12),
                      Text('فيديو', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _messageController,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'اكتب رسالة...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFe94560), Color(0xFFc73e54)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFFe94560).withOpacity(0.3),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _sendMessage,
              icon: Icon(
                Icons.send,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'مسح المحادثة',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'هل تريد مسح جميع الرسائل؟',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: TextStyle(color: Color(0xFFe94560)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _dbHelper.deleteAllMessages(widget.peerId);
              await _loadMessages();
            },
            child: Text(
              'مسح',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
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
        return DateFormat('HH:mm').format(dateTime);
      } else {
        return DateFormat('dd/MM HH:mm').format(dateTime);
      }
    } catch (e) {
      return timestamp;
    }
  }
}
