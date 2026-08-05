// database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models.dart';

class DBHelper {
  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  initDB() async {
    String path = join(await getDatabasesPath(), 'local_chat.db');
    return await openDatabase(path, version: 10, onCreate: (db, version) async {
      // جدول الأصدقاء لحفظ المعرف والاسم وصورة البروفايل وآخر ظهور
      await db.execute(
          'CREATE TABLE Peers (id TEXT PRIMARY KEY, name TEXT, avatarPath TEXT, lastMessage TEXT, lastMessageTime TEXT, lastSeen TEXT)');
      // جدول الرسائل مع الأعمدة الجديدة
      await db.execute('''
        CREATE TABLE Messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          peerId TEXT,
          content TEXT,
          isMe INTEGER,
          timestamp TEXT,
          messageType TEXT DEFAULT 'text',
          isRead INTEGER DEFAULT 0,
          mediaPath TEXT,
          replyToMessage TEXT,
          isEdited INTEGER DEFAULT 0,
          reaction TEXT,
          ttl INTEGER DEFAULT 0,
          groupId TEXT,
          senderName TEXT
        )''');
      // جدول المجموعات
      await db.execute('''
        CREATE TABLE Groups (
          id TEXT PRIMARY KEY,
          name TEXT,
          createdTime TEXT
        )''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute(
            'ALTER TABLE Messages ADD COLUMN messageType TEXT DEFAULT "text"');
        await db.execute(
            'ALTER TABLE Messages ADD COLUMN isRead INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE Messages ADD COLUMN mediaPath TEXT');
      }
      if (oldVersion < 3) {
        await db.execute('ALTER TABLE Messages ADD COLUMN replyToMessage TEXT');
      }
      if (oldVersion < 4) {
        await db.execute('ALTER TABLE Messages ADD COLUMN isEdited INTEGER DEFAULT 0');
      }
      if (oldVersion < 5) {
        await db.execute('ALTER TABLE Peers ADD COLUMN avatarPath TEXT');
      }
      if (oldVersion < 6) {
        await db.execute('ALTER TABLE Peers ADD COLUMN lastSeen TEXT');
      }
      if (oldVersion < 7) {
        await db.execute('ALTER TABLE Messages ADD COLUMN reaction TEXT');
      }
      if (oldVersion < 8) {
        await db.execute('ALTER TABLE Messages ADD COLUMN ttl INTEGER DEFAULT 0');
      }
      if (oldVersion < 9) {
        await db.execute(
            'CREATE TABLE IF NOT EXISTS Groups (id TEXT PRIMARY KEY, name TEXT, createdTime TEXT)');
        await db.execute('ALTER TABLE Messages ADD COLUMN groupId TEXT');
      }
      if (oldVersion < 10) {
        await db.execute('ALTER TABLE Messages ADD COLUMN senderName TEXT');
      }
    });
  }

  // دوال CRUD للأجهزة (Peers)
  Future<int> insertPeer(String id, String name, {String? avatarPath}) async {
    final dbClient = await db;
    return await dbClient.insert(
      'Peers',
      {
        'id': id,
        'name': name,
        'avatarPath': avatarPath,
        'lastMessage': '',
        'lastMessageTime': ''
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> upsertPeer(String id, String name, {String? avatarPath}) async {
    final dbClient = await db;
    final existing = await getPeer(id);
    if (existing == null) {
      return await insertPeer(id, name, avatarPath: avatarPath);
    } else {
      final Map<String, dynamic> updateData = {'name': name};
      if (avatarPath != null) {
        updateData['avatarPath'] = avatarPath;
      }
      return await dbClient.update(
        'Peers',
        updateData,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> migratePeerId(String oldPeerId, String newPeerId, String newName,
      {String? avatarPath}) async {
    if (oldPeerId == newPeerId) {
      await upsertPeer(newPeerId, newName, avatarPath: avatarPath);
      return;
    }
    final dbClient = await db;

    await dbClient.update(
      'Messages',
      {'peerId': newPeerId},
      where: 'peerId = ?',
      whereArgs: [oldPeerId],
    );

    await dbClient.delete('Peers', where: 'id = ?', whereArgs: [oldPeerId]);
    await upsertPeer(newPeerId, newName, avatarPath: avatarPath);
  }

  Future<List<Map<String, dynamic>>> getPeers() async {
    final dbClient = await db;
    return await dbClient.query('Peers', orderBy: 'lastMessageTime DESC');
  }

  Future<Map<String, dynamic>?> getPeer(String id) async {
    final dbClient = await db;
    final results =
        await dbClient.query('Peers', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updatePeerLastSeen(String id, String lastSeen) async {
    final dbClient = await db;
    return await dbClient.update(
      'Peers',
      {'lastSeen': lastSeen},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePeer(
      String id, String? lastMessage, String? lastMessageTime) async {
    final dbClient = await db;
    return await dbClient.update(
      'Peers',
      {'lastMessage': lastMessage, 'lastMessageTime': lastMessageTime},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePeer(String id) async {
    final dbClient = await db;
    await dbClient.delete('Messages', where: 'peerId = ?', whereArgs: [id]);
    return await dbClient.delete('Peers', where: 'id = ?', whereArgs: [id]);
  }

  // حذف المحادثة بالكامل (الرسائل والصديق معاً)
  Future<void> deletePeerAndAllMessages(String peerId) async {
    final dbClient = await db;
    await dbClient.transaction((txn) async {
      await txn.delete('Messages', where: 'peerId = ?', whereArgs: [peerId]);
      await txn.delete('Peers', where: 'id = ?', whereArgs: [peerId]);
    });
  }

  // دوال CRUD للمجموعات (Groups)
  Future<void> insertGroup(Group group) async {
    final dbClient = await db;
    await dbClient.insert('Groups', group.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Group>> getGroups() async {
    final dbClient = await db;
    final maps = await dbClient.query('Groups', orderBy: 'createdTime DESC');
    return maps.map((m) => Group.fromMap(m)).toList();
  }

  Future<List<Map<String, dynamic>>> getGroupMessages(String groupId) async {
    final dbClient = await db;
    return await dbClient.query(
      'Messages',
      where: 'groupId = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> insertGroupMessage(String groupId, String senderId,
      String senderName, String content, bool isMe, String timestamp,
      {String messageType = 'text', String? mediaPath}) async {
    final dbClient = await db;
    return await dbClient.insert('Messages', {
      'peerId': senderId,
      'content': content,
      'isMe': isMe ? 1 : 0,
      'timestamp': timestamp,
      'messageType': messageType,
      'isRead': isMe ? 2 : 0,
      'mediaPath': mediaPath,
      'groupId': groupId,
      'ttl': 0,
      'senderName': senderName,
    });
  }

  Future<void> deleteGroup(String groupId) async {
    final dbClient = await db;
    await dbClient.transaction((txn) async {
      await txn.delete('Messages', where: 'groupId = ?', whereArgs: [groupId]);
      await txn.delete('Groups', where: 'id = ?', whereArgs: [groupId]);
    });
  }

  // دوال CRUD للرسائل
  Future<int> insertMessage(
      String peerId, String content, bool isMe, String timestamp,
      {String messageType = 'text',
      String? mediaPath,
      String? replyToMessage,
      String? reaction,
      int ttl = 0,
      String? groupId,
      String? senderName}) async {
    final dbClient = await db;
    final result = await dbClient.insert('Messages', {
      'peerId': peerId,
      'content': content,
      'isMe': isMe ? 1 : 0,
      'timestamp': timestamp,
      'messageType': messageType,
      'isRead': 0,
      'mediaPath': mediaPath,
      'replyToMessage': replyToMessage,
      'reaction': reaction,
      'ttl': ttl,
      'groupId': groupId,
      'senderName': senderName,
    });

    if (groupId == null) {
      await updatePeer(peerId, content, timestamp);
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> getMessages(String peerId) async {
    final dbClient = await db;
    return await dbClient.query(
      'Messages',
      where: 'peerId = ? AND groupId IS NULL',
      whereArgs: [peerId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> updateMessageReaction(
      String timestamp, String peerId, String? reaction) async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {'reaction': reaction},
      where: 'timestamp = ? AND peerId = ?',
      whereArgs: [timestamp, peerId],
    );
  }

  Future<int> updateMessageReadStatus(int messageId, int isRead) async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {'isRead': isRead},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<int> updateMessageReadStatusByTimestamp(
      String timestamp, String peerId, int status) async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {'isRead': status},
      where: 'timestamp = ? AND peerId = ?',
      whereArgs: [timestamp, peerId],
    );
  }

  Future<int> markAllMessagesAsReadByPeer(String peerId) async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {'isRead': 2},
      where: 'peerId = ? AND isMe = 0 AND isRead < 2',
      whereArgs: [peerId],
    );
  }

  Future<int> updateMessage(int messageId, String newContent) async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {'content': newContent},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<int> updateMessageContentAndEdited(
      String timestamp, String peerId, String newContent) async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {
        'content': newContent,
        'isEdited': 1,
      },
      where: 'timestamp = ? AND peerId = ?',
      whereArgs: [timestamp, peerId],
    );
  }

  Future<int> deleteMessage(int id) async {
    final dbClient = await db;
    return await dbClient.delete('Messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteMessageByTimestamp(String timestamp, String peerId) async {
    final dbClient = await db;
    return await dbClient.delete(
      'Messages',
      where: 'timestamp = ? AND peerId = ?',
      whereArgs: [timestamp, peerId],
    );
  }

  Future<int> deleteAllMessages(String peerId) async {
    final dbClient = await db;
    return await dbClient
        .delete('Messages', where: 'peerId = ?', whereArgs: [peerId]);
  }

  Future<int> updateDeliveryStatusByTimestamp(
      String timestamp, int status) async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {'isRead': status},
      where: 'timestamp = ? AND isMe = 1 AND isRead < ?',
      whereArgs: [timestamp, status],
    );
  }

  Future<int> markAllSentMessagesAsRead() async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {'isRead': 2},
      where: 'isMe = 1 AND isRead < 2',
    );
  }
}
