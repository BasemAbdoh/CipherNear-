// models.dart

class Peer {
  final String id;
  final String name;
  String lastMessage;
  String lastMessageTime;

  Peer({
    required this.id,
    required this.name,
    this.lastMessage = '',
    this.lastMessageTime = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime,
    };
  }

  factory Peer.fromMap(Map<String, dynamic> map) {
    return Peer(
      id: map['id'],
      name: map['name'],
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: map['lastMessageTime'] ?? '',
    );
  }
}

class Message {
  final int? id;
  final String peerId;
  final String content;
  final bool isMe;
  final String timestamp;
  final String messageType; // 'text', 'image', 'audio', 'video'
  final bool isRead; // علامة القراءة
  final String? mediaPath; // مسار الملف (للصور والصوت والفيديو)

  Message({
    this.id,
    required this.peerId,
    required this.content,
    required this.isMe,
    required this.timestamp,
    this.messageType = 'text',
    this.isRead = false,
    this.mediaPath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'peerId': peerId,
      'content': content,
      'isMe': isMe ? 1 : 0,
      'timestamp': timestamp,
      'messageType': messageType,
      'isRead': isRead ? 1 : 0,
      'mediaPath': mediaPath,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      peerId: map['peerId'],
      content: map['content'],
      isMe: map['isMe'] == 1,
      timestamp: map['timestamp'],
      messageType: map['messageType'] ?? 'text',
      isRead: map['isRead'] == 1,
      mediaPath: map['mediaPath'],
    );
  }
}
