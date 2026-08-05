import 'dart:io';
import 'package:flutter/material.dart';

class ProfileImageDialog extends StatelessWidget {
  final String userName;
  final String? userImagePath;
  final VoidCallback onPickImage;

  const ProfileImageDialog({
    super.key,
    required this.userName,
    required this.userImagePath,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = userImagePath != null && File(userImagePath!).existsSync();

    return Dialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'صورة البروفايل',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFe94560), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFe94560).withOpacity(0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: hasImage
                        ? Image.file(
                            File(userImagePath!),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: const Color(0xFF0f3460),
                            child: const Icon(Icons.person, color: Colors.white, size: 90),
                          ),
                  ),
                ),
                // زر صغير عائم مخصص لاختيار صورة جديدة
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onPickImage();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFe94560),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.photo_camera, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              userName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
