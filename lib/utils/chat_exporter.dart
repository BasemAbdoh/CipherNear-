import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models.dart';

class ChatExporter {
  ChatExporter._();

  static Future<String?> exportToTxt({
    required String peerName,
    required String myName,
    required List<Message> messages,
  }) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('═══════════════════════════════════');
      buffer.writeln('  محادثة مع: $peerName');
      buffer.writeln('  تصدير بتاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}');
      buffer.writeln('  عدد الرسائل: ${messages.length}');
      buffer.writeln('═══════════════════════════════════\n');

      for (final msg in messages) {
        final sender = msg.isMe ? myName : peerName;
        String timeStr = '';
        try {
          final dt = DateTime.parse(msg.timestamp).toLocal();
          timeStr = DateFormat('yyyy/MM/dd HH:mm').format(dt);
        } catch (_) {
          timeStr = msg.timestamp;
        }
        buffer.writeln('[$timeStr] $sender:');
        if (msg.messageType == 'text') {
          buffer.writeln('  ${msg.content}');
        } else {
          buffer.writeln('  [${_mediaTypeAr(msg.messageType)}]');
        }
        if (msg.reaction != null && msg.reaction!.isNotEmpty) {
          buffer.writeln('  تفاعل: ${msg.reaction}');
        }
        buffer.writeln();
      }

      final dir = await _getNearChatDir();
      final fileName =
          'NearChat_${peerName}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.txt';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buffer.toString(), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> exportToJson({
    required String peerName,
    required String myName,
    required String peerId,
    required List<Message> messages,
  }) async {
    try {
      final data = {
        'exportedAt': DateTime.now().toIso8601String(),
        'peer': {'id': peerId, 'name': peerName},
        'myName': myName,
        'messageCount': messages.length,
        'messages': messages
            .map((m) => {
                  'timestamp': m.timestamp,
                  'sender': m.isMe ? myName : peerName,
                  'isMe': m.isMe,
                  'type': m.messageType,
                  'content': m.messageType == 'text'
                      ? m.content
                      : '[${_mediaTypeAr(m.messageType)}]',
                  'reaction': m.reaction,
                  'isEdited': m.isEdited,
                })
            .toList(),
      };

      final dir = await _getNearChatDir();
      final fileName =
          'NearChat_${peerName}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(data),
          flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _getNearChatDir() async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/NearChat/Exports');
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}/NearChat/Exports');
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _mediaTypeAr(String type) {
    switch (type) {
      case 'image':
        return 'صورة';
      case 'video':
        return 'فيديو';
      case 'audio':
        return 'مقطع صوتي';
      case 'file':
        return 'ملف';
      default:
        return type;
    }
  }
}
