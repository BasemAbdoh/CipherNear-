import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models.dart';
import '../utils/media_saver.dart';
import 'media_player_widgets.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final String peerDisplayName;
  final String fallbackPeerName;
  final String? peerAvatarPath;
  final Function(Message) onSelectMessage;
  final Function(Message) onReplyToMessage;
  final Function(BuildContext, String) onShowImagePreview;
  final String Function(String) formatTime;
  final ui.TextDirection Function(String) getTextDirection;
  final Function(Message, String?)? onReaction;
  final String searchQuery;

  const MessageBubble({
    super.key,
    required this.message,
    required this.peerDisplayName,
    required this.fallbackPeerName,
    required this.peerAvatarPath,
    required this.onSelectMessage,
    required this.onReplyToMessage,
    required this.onShowImagePreview,
    required this.formatTime,
    required this.getTextDirection,
    this.onReaction,
    this.searchQuery = '',
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _saving = false;
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _startSelfDestructTimer();
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.ttl != widget.message.ttl ||
        oldWidget.message.timestamp != widget.message.timestamp) {
      _countdownTimer?.cancel();
      _startSelfDestructTimer();
    }
  }

  void _startSelfDestructTimer() {
    if (widget.message.ttl > 0) {
      try {
        final created = DateTime.parse(widget.message.timestamp).toLocal();
        final elapsed = DateTime.now().difference(created).inSeconds;
        _secondsLeft = (widget.message.ttl - elapsed).clamp(0, widget.message.ttl);
        if (_secondsLeft > 0) {
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            setState(() {
              _secondsLeft--;
              if (_secondsLeft <= 0) t.cancel();
            });
          });
        }
      } catch (_) {
        _secondsLeft = widget.message.ttl;
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveMedia(String path) async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await MediaSaver.saveToDevice(path);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              saved != null ? Icons.check_circle : Icons.error,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                saved != null
                    ? 'تم الحفظ في مجلد NearChat ✅'
                    : 'فشل الحفظ، تحقق من الأذونات',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: saved != null
            ? const Color(0xFF00C853)
            : const Color(0xFFe94560),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSaveButton(String path) {
    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        onTap: () => _saveMedia(path),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                  size: 18,
                ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query, TextStyle baseStyle) {
    if (query.trim().isEmpty) {
      return Text(text, style: baseStyle);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx;
    while ((idx = lowerText.indexOf(lowerQuery, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: baseStyle.copyWith(
          backgroundColor: Colors.amberAccent.withValues(alpha: 0.6),
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = idx + query.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    return RichText(
      text: TextSpan(children: spans),
      textDirection: widget.getTextDirection(text),
    );
  }

  Widget _buildContent(BuildContext context) {
    final isMe = widget.message.isMe;
    final direction = widget.getTextDirection(widget.message.content);

    if (widget.message.messageType == 'text') {
      return Directionality(
        textDirection: direction,
        child: _buildHighlightedText(
          widget.message.content,
          widget.searchQuery,
          const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    } else if (widget.message.messageType == 'image' && widget.message.mediaPath != null) {
      return GestureDetector(
        onTap: () => widget.onShowImagePreview(context, widget.message.mediaPath!),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Image.file(
                    File(widget.message.mediaPath!),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 150,
                      color: Colors.black26,
                      child: const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white54, size: 48),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.fullscreen,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  if (!isMe) _buildSaveButton(widget.message.mediaPath!),
                ],
              ),
            ),
            if (widget.message.content.isNotEmpty && widget.message.content != 'صورة')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Directionality(
                  textDirection: direction,
                  child: _buildHighlightedText(
                    widget.message.content,
                    widget.searchQuery,
                    const TextStyle(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      );
    } else if (widget.message.messageType == 'video' && widget.message.mediaPath != null) {
      if (!isMe) {
        return Stack(
          children: [
            VideoPlayerWidget(path: widget.message.mediaPath!),
            _buildSaveButton(widget.message.mediaPath!),
          ],
        );
      }
      return VideoPlayerWidget(path: widget.message.mediaPath!);
    } else if (widget.message.messageType == 'audio' && widget.message.mediaPath != null) {
      return AudioPlayerWidget(path: widget.message.mediaPath!);
    } else if (widget.message.messageType == 'file' && widget.message.mediaPath != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Directionality(
              textDirection: direction,
              child: _buildHighlightedText(
                widget.message.content,
                widget.searchQuery,
                const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    return Directionality(
      textDirection: direction,
      child: _buildHighlightedText(
        widget.message.content,
        widget.searchQuery,
        const TextStyle(color: Colors.white),
      ),
    );
  }

  void _showReactionPicker(BuildContext context) {
    const reactions = ['❤️', '👍', '😂', '😮', '😢', '🙏'];
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: reactions.map((emoji) {
            final isSelected = widget.message.reaction == emoji;
            return GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                final newReaction = isSelected ? null : emoji;
                widget.onReaction?.call(widget.message, newReaction);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.message.isMe;
    final titleName = widget.peerDisplayName.isNotEmpty
        ? widget.peerDisplayName
        : widget.fallbackPeerName;
    final hasAvatar =
        widget.peerAvatarPath != null && File(widget.peerAvatarPath!).existsSync();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(widget.message.timestamp),
        direction: DismissDirection.startToEnd,
        confirmDismiss: (direction) async {
          widget.onReplyToMessage(widget.message);
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.transparent,
          child: const Icon(Icons.reply, color: Color(0xFF29B6F6), size: 28),
        ),
        child: GestureDetector(
          onLongPress: () {
            _showReactionPicker(context);
            widget.onSelectMessage(widget.message);
          },
          child: Container(
            margin: EdgeInsets.only(
              left: isMe ? 48 : 0,
              right: isMe ? 0 : 48,
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      mainAxisAlignment:
                          isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isMe) ...[
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFe94560), Color(0xFF0f3460)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: hasAvatar
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      File(widget.peerAvatarPath!),
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      titleName.isNotEmpty
                                          ? titleName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.7,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: isMe
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF29B6F6),
                                        Color(0xFF0288D1)
                                      ],
                                    )
                                  : LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0.15),
                                        Colors.white.withValues(alpha: 0.1),
                                      ],
                                    ),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(20),
                                topRight: const Radius.circular(20),
                                bottomLeft: isMe
                                    ? const Radius.circular(20)
                                    : const Radius.circular(4),
                                bottomRight: isMe
                                    ? const Radius.circular(4)
                                    : const Radius.circular(20),
                              ),
                              border: Border.all(
                                color: isMe
                                    ? Colors.transparent
                                    : Colors.white.withValues(alpha: 0.1),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMe && widget.message.groupId != null) ...[
                                  Text(
                                    widget.message.senderName ?? titleName,
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                if (widget.message.replyToMessage != null)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                          color: isMe
                                              ? Colors.white
                                              : const Color(0xFF29B6F6),
                                          width: 4,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      widget.message.replyToMessage!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                _buildContent(context),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.message.ttl > 0 &&
                                        _secondsLeft > 0) ...[
                                      Icon(
                                        Icons.timer_outlined,
                                        size: 13,
                                        color: _secondsLeft < 10
                                            ? Colors.redAccent
                                            : Colors.amberAccent,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        _secondsLeft >= 60
                                            ? '${(_secondsLeft / 60).floor()}د ${_secondsLeft % 60}ث'
                                            : '$_secondsLeftث',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _secondsLeft < 10
                                              ? Colors.redAccent
                                              : Colors.amberAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    if (widget.message.isEdited) ...[
                                      Text(
                                        'تم تعديلها • ',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.6),
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                    Text(
                                      widget.formatTime(widget.message.timestamp),
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.5),
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      if (widget.message.status == 0)
                                        const Icon(Icons.check,
                                            color: Colors.white70, size: 14)
                                      else if (widget.message.status == 1)
                                        const Icon(Icons.done_all,
                                            color: Colors.white70, size: 14)
                                      else
                                        const Icon(Icons.done_all,
                                            color: Colors.greenAccent, size: 14),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0f3460), Color(0xFF16213e)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(Icons.person,
                                  color: Colors.white70, size: 18),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // شارة رد الفعل بالإيموجي أسفل فقاعة الرسالة
                    if (widget.message.reaction != null &&
                        widget.message.reaction!.isNotEmpty)
                      Positioned(
                        bottom: -10,
                        right: isMe ? 48 : null,
                        left: isMe ? null : 48,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16213e),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              )
                            ],
                          ),
                          child: Text(
                            widget.message.reaction!,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
