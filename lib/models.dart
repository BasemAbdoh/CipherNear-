// models.dart

class Peer {
  final String id;
  final String name;
  String lastMessage;
  String lastMessageTime;
  String? avatarPath;
  String? lastSeen;

  Peer({
    required this.id,
    required this.name,
    this.lastMessage = '',
    this.lastMessageTime = '',
    this.avatarPath,
    this.lastSeen,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime,
      'avatarPath': avatarPath,
      'lastSeen': lastSeen,
    };
  }

  factory Peer.fromMap(Map<String, dynamic> map) {
    return Peer(
      id: map['id'],
      name: map['name'],
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: map['lastMessageTime'] ?? '',
      avatarPath: map['avatarPath'],
      lastSeen: map['lastSeen'],
    );
  }
}

class Group {
  final String id;
  String name;
  final String createdTime;
  final List<String> memberIds;

  Group({
    required this.id,
    required this.name,
    required this.createdTime,
    this.memberIds = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdTime': createdTime,
      };

  factory Group.fromMap(Map<String, dynamic> map) => Group(
        id: map['id'],
        name: map['name'],
        createdTime: map['createdTime'] ?? '',
      );
}

class Message {
  final int? id;
  final String peerId;
  final String content;
  final bool isMe;
  final String timestamp;
  final String messageType; // 'text', 'image', 'audio', 'video'
  final int status; // 0 = Sent (✓), 1 = Delivered (✓✓), 2 = Read (✓✓ Green)
  final String? mediaPath; // مسار الملف (للصور والصوت والفيديو)
  final String? replyToMessage; // نص محتوى الرسالة المُرد عليها
  final bool isEdited; // هل تم تعديل الرسالة
  final String? reaction; // رد الفعل بالإيموجي (❤️ 👍 😂 😮 😢 🙏)
  final int ttl; // Time-To-Live بالثواني، 0 = لا تنتهي (رسالة ذاتية التدمير)
  final String? groupId; // معرف المجموعة (null للرسائل الفردية)
  final String? senderName; // اسم المرسل في المجموعات والرسائل الفردية

  Message({
    this.id,
    required this.peerId,
    required this.content,
    required this.isMe,
    required this.timestamp,
    this.messageType = 'text',
    this.status = 0,
    this.mediaPath,
    this.replyToMessage,
    this.isEdited = false,
    this.reaction,
    this.ttl = 0,
    this.groupId,
    this.senderName,
  });

  bool get isRead => status == 2;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'peerId': peerId,
      'content': content,
      'isMe': isMe ? 1 : 0,
      'timestamp': timestamp,
      'messageType': messageType,
      'isRead': status,
      'mediaPath': mediaPath,
      'replyToMessage': replyToMessage,
      'isEdited': isEdited ? 1 : 0,
      'reaction': reaction,
      'ttl': ttl,
      'groupId': groupId,
      'senderName': senderName,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    int readVal = 0;
    if (map['isRead'] is int) {
      readVal = map['isRead'];
    } else if (map['isRead'] == true || map['isRead'] == 1) {
      readVal = 2;
    }
    return Message(
      id: map['id'],
      peerId: map['peerId'],
      content: map['content'],
      isMe: map['isMe'] == 1,
      timestamp: map['timestamp'],
      messageType: map['messageType'] ?? 'text',
      status: readVal,
      mediaPath: map['mediaPath'],
      replyToMessage: map['replyToMessage'],
      isEdited: map['isEdited'] == 1,
      reaction: map['reaction'],
      ttl: (map['ttl'] as num?)?.toInt() ?? 0,
      groupId: map['groupId'],
      senderName: map['senderName'],
    );
  }
}
