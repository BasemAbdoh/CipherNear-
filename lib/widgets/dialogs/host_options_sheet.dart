import 'package:flutter/material.dart';

class HostOptionsSheet extends StatelessWidget {
  final VoidCallback onShowQRCode;
  final VoidCallback onDisconnect;

  const HostOptionsSheet({
    super.key,
    required this.onShowQRCode,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'خيارات نقطة الاتصال النشطة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          // 1. خيار عرض QR Code للانضمام
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFe94560).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.qr_code_2, color: Color(0xFFe94560), size: 26),
            ),
            title: const Text(
              'عرض QR Code الانضمام',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: const Text(
              'إظهار الباركود ليمسحه جهاز آخر وينضم مباشرة',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(context);
              onShowQRCode();
            },
          ),
          const Divider(color: Colors.white12, height: 16),
          // 2. خيار إنهاء الاتصال
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 26),
            ),
            title: const Text(
              'إنهاء الاتصال',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: const Text(
              'إغلاق نقطة الاتصال وإيقاف المحادثة',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(context);
              onDisconnect();
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
