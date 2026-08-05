import 'package:flutter/material.dart';

class QuickReplyDialog extends StatefulWidget {
  final String peerName;
  final String? initialText;
  final Function(String text) onSendReply;

  const QuickReplyDialog({
    super.key,
    required this.peerName,
    this.initialText,
    required this.onSendReply,
  });

  @override
  State<QuickReplyDialog> createState() => _QuickReplyDialogState();
}

class _QuickReplyDialogState extends State<QuickReplyDialog> {
  late final TextEditingController _replyController;

  @override
  void initState() {
    super.initState();
    _replyController = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.reply, color: Color(0xFFe94560), size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'رد سريع على ${widget.peerName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Directionality(
              textDirection: TextDirection.rtl,
              child: TextField(
                controller: _replyController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'اكتب رسالتك السريعة هنا...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFe94560),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  onPressed: () {
                    final text = _replyController.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(context);
                    widget.onSendReply(text);
                  },
                  icon: const Icon(Icons.send, color: Colors.white, size: 16),
                  label: const Text('إرسال', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
