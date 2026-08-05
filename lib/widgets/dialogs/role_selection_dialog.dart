import 'package:flutter/material.dart';

class RoleSelectionDialog extends StatelessWidget {
  final VoidCallback onSelectHost;
  final VoidCallback onSelectClient;

  const RoleSelectionDialog({
    super.key,
    required this.onSelectHost,
    required this.onSelectClient,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text(
        'اختر دور الجهاز',
        style: TextStyle(color: Colors.white, fontSize: 20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Host: ينشئ نقطة اتصال وينتظر الأجهزة الأخرى',
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Client: يبحث عن الأجهزة ويتصل بها',
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onSelectHost();
          },
          child: const Text(
            'Host (مضيف)',
            style: TextStyle(color: Color(0xFFe94560)),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onSelectClient();
          },
          child: const Text(
            'Client (عميل)',
            style: TextStyle(color: Color(0xFFe94560)),
          ),
        ),
      ],
    );
  }
}
