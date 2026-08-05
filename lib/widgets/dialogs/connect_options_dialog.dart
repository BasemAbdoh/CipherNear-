import 'package:flutter/material.dart';

class ConnectOptionsDialog extends StatefulWidget {
  final VoidCallback onOpenQRScanner;
  final Function(String ip) onConnectToIp;

  const ConnectOptionsDialog({
    super.key,
    required this.onOpenQRScanner,
    required this.onConnectToIp,
  });

  @override
  State<ConnectOptionsDialog> createState() => _ConnectOptionsDialogState();
}

class _ConnectOptionsDialogState extends State<ConnectOptionsDialog> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.43.1');

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1a2e),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // أيقونة شاشة الانضمام
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFe94560).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  color: Color(0xFFe94560),
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'الانضمام إلى المجموعة / المضيف',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'تأكد من الاتصال بـ Hotspot المضيف، ثم ادخل IP الظاهر في الباركود للانضمام الفوري.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
              ),
              const SizedBox(height: 20),
              // حقل الـ IP الذكي
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _ipController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'IP المضيف',
                    labelStyle: const TextStyle(color: Color(0xFFe94560)),
                    hintText: '192.168.43.1',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.wifi, color: Color(0xFFe94560)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFe94560), width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  // زر الكاميرا لمسح الباركود مباشر
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.12),
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: const Color(0xFFe94560).withOpacity(0.4)),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onOpenQRScanner();
                    },
                    icon: const Icon(Icons.camera_alt, color: Color(0xFFe94560), size: 22),
                    tooltip: 'مسح الباركود بالكاميرا',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe94560),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        final ip = _ipController.text.trim();
                        if (ip.isNotEmpty) {
                          widget.onConnectToIp(ip);
                        }
                      },
                      icon: const Icon(Icons.flash_on, color: Colors.white, size: 18),
                      label: const Text(
                        'اتصال الآن',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
