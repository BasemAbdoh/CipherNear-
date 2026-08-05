import 'package:flutter/material.dart';
import '../../models.dart';

class DeletePeerDialog extends StatelessWidget {
  final Peer peer;
  final VoidCallback onDelete;
  final VoidCallback? onClearMessagesOnly;

  const DeletePeerDialog({
    super.key,
    required this.peer,
    required this.onDelete,
    this.onClearMessagesOnly,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text(
        'خيارات الحذف',
        style: TextStyle(color: Colors.white),
      ),
      content: Text(
        'حدد إجراء الحذف لمحادثة ${peer.name}:',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'إلغاء',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onClearMessagesOnly?.call();
          },
          child: const Text(
            'مسح الرسائل فقط',
            style: TextStyle(color: Colors.amberAccent),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onDelete();
          },
          child: const Text(
            'حذف الصديق والرسائل',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}
