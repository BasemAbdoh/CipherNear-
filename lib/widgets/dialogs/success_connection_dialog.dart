import 'package:flutter/material.dart';

class SuccessConnectionDialog extends StatefulWidget {
  final String peerName;

  const SuccessConnectionDialog({
    super.key,
    required this.peerName,
  });

  static void show(BuildContext context, String peerName) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SuccessConnectionDialog(peerName: peerName),
    );
  }

  @override
  State<SuccessConnectionDialog> createState() => _SuccessConnectionDialogState();
}

class _SuccessConnectionDialogState extends State<SuccessConnectionDialog> {
  @override
  void initState() {
    super.initState();
    // إغلاق النافذة التلقائي بعد 5 ثوانٍ
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16213e),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF4e54c8), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4e54c8).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF00b4d8),
                size: 48,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'تم الاتصال بنجاح',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'أنت الآن متصل مع ${widget.peerName} ويمكنك البدء في التراسل الأمني مباشرة.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
