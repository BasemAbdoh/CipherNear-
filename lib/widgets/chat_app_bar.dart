import 'dart:io';
import 'package:flutter/material.dart';

class ChatAppBar extends StatefulWidget {
  final String peerDisplayName;
  final String fallbackPeerName;
  final String? peerAvatarPath;
  final bool isPeerConnected;
  final String? lastSeen;
  final VoidCallback onBackPressed;
  final VoidCallback onClearChatPressed;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onSearchClose;
  final int searchResultCount;
  final int currentSearchIndex;
  final VoidCallback? onPrevResult;
  final VoidCallback? onNextResult;
  final VoidCallback? onExportChat;

  const ChatAppBar({
    super.key,
    required this.peerDisplayName,
    required this.fallbackPeerName,
    required this.peerAvatarPath,
    required this.isPeerConnected,
    this.lastSeen,
    required this.onBackPressed,
    required this.onClearChatPressed,
    this.onSearch,
    this.onSearchClose,
    this.searchResultCount = 0,
    this.currentSearchIndex = 0,
    this.onPrevResult,
    this.onNextResult,
    this.onExportChat,
  });

  @override
  State<ChatAppBar> createState() => _ChatAppBarState();
}

class _ChatAppBarState extends State<ChatAppBar> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
    });
    widget.onSearchClose?.call();
  }

  String _formatLastSeen(String? lastSeenStr) {
    if (lastSeenStr == null || lastSeenStr.isEmpty) return 'غير متصل';
    try {
      final dt = DateTime.parse(lastSeenStr).toLocal();
      final now = DateTime.now();
      final difference = now.difference(dt);

      String timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'آخر ظهور $timeStr';
      } else if (difference.inDays < 2 && now.day - dt.day == 1) {
        return 'آخر ظهور أمس $timeStr';
      } else {
        return 'آخر ظهور ${dt.day}/${dt.month} $timeStr';
      }
    } catch (_) {
      return 'آخر ظهور $lastSeenStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleName = widget.peerDisplayName.isNotEmpty
        ? widget.peerDisplayName
        : widget.fallbackPeerName;
    final hasAvatar = widget.peerAvatarPath != null &&
        File(widget.peerAvatarPath!).existsSync();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e).withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _isSearching ? _closeSearch : widget.onBackPressed,
            icon: Icon(
              _isSearching ? Icons.close : Icons.arrow_back_ios,
              color: Colors.white,
            ),
          ),
          if (!_isSearching) ...[
            const SizedBox(width: 8),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFe94560), Color(0xFF0f3460)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: hasAvatar
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(widget.peerAvatarPath!),
                          fit: BoxFit.cover),
                    )
                  : Center(
                      child: Text(
                        titleName.isNotEmpty
                            ? titleName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    titleName,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isPeerConnected
                        ? 'متصل'
                        : _formatLastSeen(widget.lastSeen),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: widget.isPeerConnected
                          ? Colors.greenAccent
                          : Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => setState(() => _isSearching = true),
              icon: const Icon(Icons.search, color: Colors.white70),
              tooltip: 'البحث',
            ),
            if (widget.onExportChat != null)
              IconButton(
                onPressed: widget.onExportChat,
                icon: const Icon(Icons.ios_share_outlined, color: Colors.white70),
                tooltip: 'تصدير المحادثة',
              ),
            IconButton(
              onPressed: widget.onClearChatPressed,
              icon: const Icon(Icons.delete_sweep, color: Colors.white70),
              tooltip: 'مسح/حذف',
            ),
          ] else ...[
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  hintText: 'البحث في المحادثة...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                onChanged: (text) => widget.onSearch?.call(text),
              ),
            ),
            if (widget.searchResultCount > 0) ...[
              Text(
                '${widget.currentSearchIndex + 1}/${widget.searchResultCount}',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up,
                    color: Colors.amberAccent),
                onPressed: widget.onPrevResult,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: Colors.amberAccent),
                onPressed: widget.onNextResult,
              ),
            ] else if (_searchController.text.isNotEmpty) ...[
              const Text(
                '0/0',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
