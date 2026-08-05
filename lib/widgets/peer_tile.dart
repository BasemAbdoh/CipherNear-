import 'dart:io';
import 'package:flutter/material.dart';
import '../models.dart';

class PeerTile extends StatelessWidget {
  final Peer peer;
  final bool isOnline;
  final String formattedTime;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const PeerTile({
    super.key,
    required this.peer,
    required this.isOnline,
    required this.formattedTime,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = peer.avatarPath != null && File(peer.avatarPath!).existsSync();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Stack(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFe94560), Color(0xFF0f3460)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: hasAvatar
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(peer.avatarPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00e676),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF1a1a2e),
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          peer.name,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: peer.lastMessage.isNotEmpty
            ? Text(
                peer.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              )
            : null,
        trailing: peer.lastMessageTime.isNotEmpty
            ? Text(
                formattedTime,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              )
            : null,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
