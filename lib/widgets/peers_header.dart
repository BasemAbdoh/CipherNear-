import 'dart:io';
import 'package:flutter/material.dart';

class PeersHeader extends StatelessWidget {
  final String userName;
  final String? userImagePath;
  final bool isConnected;
  final String? selectedRole;
  final VoidCallback onEditNameTap;
  final VoidCallback onProfileImageTap;

  const PeersHeader({
    super.key,
    required this.userName,
    required this.userImagePath,
    required this.isConnected,
    required this.selectedRole,
    required this.onEditNameTap,
    required this.onProfileImageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFff758c),
                          Color(0xFFff7eb3),
                          Color(0xFFffffff),
                        ],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ).createShader(bounds),
                      child: const Text(
                        'فرفش free',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.5,
                          shadows: [
                            Shadow(
                              color: Color(0xFFe94560),
                              blurRadius: 15,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          isConnected ? 'متصل' : 'غير متصل',
                          style: TextStyle(
                            fontSize: 13,
                            color: isConnected ? Colors.greenAccent : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (selectedRole != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFe94560).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              selectedRole == 'host' ? 'HOST' : 'CLIENT',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFe94560),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFe94560).withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'lib/images/شات سولف.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // بطاقة البروفايل الشخصي
          Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              onPressed: onEditNameTap,
                              icon: const Icon(Icons.edit, color: Colors.white70, size: 16),
                              tooltip: 'تعديل الاسم',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // صورة البروفايل على اليسار (عند النقر عليها تستعرض المكبرة مع زر الكاميرا)
                  GestureDetector(
                    onTap: onProfileImageTap,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFFe94560), Color(0xFF0f3460)],
                            ),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: userImagePath != null && File(userImagePath!).existsSync()
                              ? ClipOval(
                                  child: Image.file(
                                    File(userImagePath!),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const Icon(Icons.person, color: Colors.white, size: 26),
                        ),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFFe94560),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.search, color: Colors.white, size: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
