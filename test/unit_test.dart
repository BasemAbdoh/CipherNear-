import 'package:flutter_test/flutter_test.dart';
import 'package:near_chat_app/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Models & Core Logic Tests', () {
    test('Peer serialization test', () {
      final peer = Peer(id: 'peer_1', name: 'Ahmed', lastMessage: 'Hello');
      final map = peer.toMap();
      expect(map['id'], 'peer_1');
      expect(map['name'], 'Ahmed');

      final fromMap = Peer.fromMap(map);
      expect(fromMap.id, 'peer_1');
      expect(fromMap.name, 'Ahmed');
    });

    test('Group serialization test', () {
      final group = Group(
        id: 'grp_123',
        name: 'Friends Group',
        createdTime: '2026-08-05T12:00:00Z',
      );
      final map = group.toMap();
      expect(map['id'], 'grp_123');
      expect(map['name'], 'Friends Group');

      final fromMap = Group.fromMap(map);
      expect(fromMap.id, 'grp_123');
      expect(fromMap.name, 'Friends Group');
    });

    test('Message serialization with senderName and groupId test', () {
      final msg = Message(
        peerId: 'user_1',
        content: 'Hello World',
        isMe: false,
        timestamp: '2026-08-05T12:00:00Z',
        senderName: 'Sami',
        groupId: 'grp_123',
      );

      final map = msg.toMap();
      expect(map['peerId'], 'user_1');
      expect(map['senderName'], 'Sami');
      expect(map['groupId'], 'grp_123');

      final fromMap = Message.fromMap(map);
      expect(fromMap.senderName, 'Sami');
      expect(fromMap.groupId, 'grp_123');
    });
  });
}
