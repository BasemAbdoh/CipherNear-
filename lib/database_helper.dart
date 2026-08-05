// database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  initDB() async {
    String path = join(await getDatabasesPath(), 'local_chat.db');
    return await openDatabase(path, version: 2, onCreate: (db, version) async {
      // جدول الأصدقاء لحفظ المعرف والاسم
      await db.execute('CREATE TABLE Peers (id TEXT PRIMARY KEY, name TEXT, lastMessage TEXT, lastMessageTime TEXT)');
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
          mediaPath TEXT
        )''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        // إضافة الأعمدة الجديدة للإصدارات القديمة
        await db.execute('ALTER TABLE Messages ADD COLUMN messageType TEXT DEFAULT "text"');
        await db.execute('ALTER TABLE Messages ADD COLUMN isRead INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE Messages ADD COLUMN mediaPath TEXT');
      }
    });
  }

  // دوال CRUD للأجهزة (Peers)
  Future<int> insertPeer(String id, String name) async {
    final dbClient = await db;
    return await dbClient.insert('Peers', {'id': id, 'name': name, 'lastMessage': '', 'lastMessageTime': ''});
  }

  Future<List<Map<String, dynamic>>> getPeers() async {
    final dbClient = await db;
    return await dbClient.query('Peers', orderBy: 'lastMessageTime DESC');
  }

  Future<Map<String, dynamic>?> getPeer(String id) async {
    final dbClient = await db;
    final results = await dbClient.query('Peers', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updatePeer(String id, String? lastMessage, String? lastMessageTime) async {
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
    // حذف الرسائل المرتبطة بالجهاز أولاً
    await dbClient.delete('Messages', where: 'peerId = ?', whereArgs: [id]);
    return await dbClient.delete('Peers', where: 'id = ?', whereArgs: [id]);
  }

  // دوال CRUD للرسائل
  Future<int> insertMessage(
    String peerId, 
    String content, 
    bool isMe, 
    String timestamp, 
    {String messageType = 'text', 
    String? mediaPath}
  ) async {
    final dbClient = await db;
    final result = await dbClient.insert('Messages', {
      'peerId': peerId,
      'content': content,
      'isMe': isMe ? 1 : 0,
      'timestamp': timestamp,
      'messageType': messageType,
      'isRead': 0,
      'mediaPath': mediaPath,
    });
    
    // تحديث آخر رسالة للجهاز
    await updatePeer(peerId, content, timestamp);
    
    return result;
  }

  Future<List<Map<String, dynamic>>> getMessages(String peerId) async {
    final dbClient = await db;
    return await dbClient.query(
      'Messages',
      where: 'peerId = ?',
      whereArgs: [peerId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> updateMessageReadStatus(int messageId, bool isRead) async {
    final dbClient = await db;
    return await dbClient.update(
      'Messages',
      {'isRead': isRead ? 1 : 0},
      where: 'id = ?',
      whereArgs: [messageId],
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

  Future<int> deleteMessage(int id) async {
    final dbClient = await db;
    return await dbClient.delete('Messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllMessages(String peerId) async {
    final dbClient = await db;
    return await dbClient.delete('Messages', where: 'peerId = ?', whereArgs: [peerId]);
  }
}