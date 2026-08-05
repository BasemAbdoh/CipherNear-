import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController messageController;
  final Message? editingMessage;
  final Message? repliedMessage;
  final String peerName;
  final VoidCallback onCancelEdit;
  final VoidCallback onCancelReply;
  final VoidCallback onSendMessage;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback onPickAudio;
  final VoidCallback onPickFile;
  final ui.TextDirection Function(String) getTextDirection;
  final int selectedTtl;
  final ValueChanged<int>? onTtlChanged;

  const ChatInputBar({
    super.key,
    required this.messageController,
    required this.editingMessage,
    required this.repliedMessage,
    required this.peerName,
    required this.onCancelEdit,
    required this.onCancelReply,
    required this.onSendMessage,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onPickAudio,
    required this.onPickFile,
    required this.getTextDirection,
    this.selectedTtl = 0,
    this.onTtlChanged,
  });

  void _showTtlPicker(BuildContext context) {
    final options = [
      {'label': 'إيقاف (عادي)', 'value': 0},
      {'label': '10 ثوانٍ', 'value': 10},
      {'label': '30 ثانية', 'value': 30},
      {'label': '1 دقيقة', 'value': 60},
      {'label': '5 دقائق', 'value': 300},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.amberAccent),
                const SizedBox(width: 8),
                const Text(
                  'مدة التدمير الذاتي للرسالة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...options.map((opt) {
              final val = opt['value'] as int;
              final isSelected = selectedTtl == val;
              return ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                tileColor: isSelected
                    ? Colors.amberAccent.withValues(alpha: 0.15)
                    : null,
                title: Text(
                  opt['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.amberAccent : Colors.white,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.amberAccent)
                    : null,
                onTap: () {
                  onTtlChanged?.call(val);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (editingMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF16213e),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تعديل الرسالة',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        editingMessage!.content,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: onCancelEdit,
                ),
              ],
            ),
          ),
        if (repliedMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF16213e),
              border: Border(
                left: BorderSide(color: Color(0xFF29B6F6), width: 4),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repliedMessage!.isMe ? 'أنا' : peerName,
                        style: const TextStyle(
                          color: Color(0xFF29B6F6),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        repliedMessage!.content,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: onCancelReply,
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                // زر الإرسال وزر العداد الزمني على اليسار
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF29B6F6), Color(0xFF0288D1)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF29B6F6).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: onSendMessage,
                    icon: Transform.flip(
                      flipX: true,
                      child: const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // زر التوقيت الذاتي للرسالة
                GestureDetector(
                  onTap: () => _showTtlPicker(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selectedTtl > 0
                          ? Colors.amberAccent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selectedTtl > 0
                            ? Colors.amberAccent
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      selectedTtl > 0
                          ? Icons.timer_rounded
                          : Icons.timer_off_outlined,
                      color: selectedTtl > 0
                          ? Colors.amberAccent
                          : Colors.white54,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // حقل كتابة النص في الوسط
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: TextField(
                        controller: messageController,
                        textDirection:
                            getTextDirection(messageController.text),
                        textAlign: TextAlign.right,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'اكتب رسالة...',
                          hintTextDirection: TextDirection.rtl,
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => onSendMessage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // أداة المرفقات على اليمين
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: PopupMenuButton<String>(
                    icon: Icon(
                      Icons.attach_file,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    color: const Color(0xFF1a1a2e),
                    onSelected: (value) {
                      if (value == 'image') {
                        onPickImage();
                      } else if (value == 'video') {
                        onPickVideo();
                      } else if (value == 'audio') {
                        onPickAudio();
                      } else if (value == 'file') {
                        onPickFile();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'image',
                        child: Row(children: [
                          Icon(Icons.image, color: Colors.white),
                          SizedBox(width: 12),
                          Text('صورة', style: TextStyle(color: Colors.white)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'video',
                        child: Row(children: [
                          Icon(Icons.videocam, color: Colors.white),
                          SizedBox(width: 12),
                          Text('فيديو', style: TextStyle(color: Colors.white)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'audio',
                        child: Row(children: [
                          Icon(Icons.audiotrack, color: Colors.white),
                          SizedBox(width: 12),
                          Text('صوت', style: TextStyle(color: Colors.white)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'file',
                        child: Row(children: [
                          Icon(Icons.insert_drive_file, color: Colors.white),
                          SizedBox(width: 12),
                          Text('ملف', style: TextStyle(color: Colors.white)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
