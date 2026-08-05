import 'dart:io';
import 'package:flutter/material.dart';
import '../database_helper.dart';

class ConnectedClientTile extends StatelessWidget {
  final dynamic client;
  final int index;
  final DBHelper dbHelper;
  final void Function(String peerId, String peerName) onNavigateToChat;

  const ConnectedClientTile({
    super.key,
    required this.client,
    required this.index,
    required this.dbHelper,
    required this.onNavigateToChat,
  });

  @override
  Widget build(BuildContext context) {
    String clientAddress = 'client_$index';
    String clientName = 'صديق متصل (${index + 1})';

    try {
      if (client is Map) {
        clientAddress = client['id']?.toString() ?? client['name']?.toString() ?? clientAddress;
        clientName = client['name']?.toString() ?? clientName;
      }
    } catch (e) {
      debugPrint('خطأ في قراءة بيانات العميل: $e');
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: dbHelper.getPeer(clientAddress),
      builder: (context, snapshot) {
        final peerMap = snapshot.data;
        final peerName = peerMap?['name']?.toString();
        final avatarPath = peerMap?['avatarPath']?.toString();

        final displayName = (peerName != null && peerName.isNotEmpty && !peerName.startsWith('192.'))
            ? peerName
            : clientName;
        final hasAvatar = avatarPath != null && File(avatarPath).existsSync();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.green.withOpacity(0.4),
              width: 1.5,
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFe94560), Color(0xFF0f3460)],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: hasAvatar
                    ? ClipOval(
                        child: Image.file(
                          File(avatarPath),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
              title: Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'متصل الآن بالقرب منك',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.chat_bubble, color: Color(0xFFe94560)),
                onPressed: () => onNavigateToChat(clientAddress, displayName),
              ),
              onTap: () => onNavigateToChat(clientAddress, displayName),
            ),
          ),
        );
      },
    );
  }
}
