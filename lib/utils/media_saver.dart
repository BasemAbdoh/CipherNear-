import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

class MediaSaver {
  static const _appFolderName = 'NearChat';

  /// يحفظ الملف في مجلد عام (Pictures/NearChat أو Downloads/NearChat)
  /// ويُعيد مسار الملف المحفوظ، أو null عند الفشل.
  static Future<String?> saveToDevice(String sourcePath) async {
    try {
      // طلب إذن التخزين
      final status = await _requestPermission();
      if (!status) return null;

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return null;

      // تحديد المجلد العام المناسب حسب نوع الملف
      final ext = p.extension(sourcePath).toLowerCase();
      final isVideo = ['.mp4', '.mov', '.avi', '.mkv', '.webm'].contains(ext);
      final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext);

      final baseDir = isVideo
          ? '/storage/emulated/0/Movies/$_appFolderName'
          : isImage
              ? '/storage/emulated/0/Pictures/$_appFolderName'
              : '/storage/emulated/0/Downloads/$_appFolderName';

      final dir = Directory(baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // اسم الملف بناءً على الوقت لمنع التعارض
      final fileName =
          '${_appFolderName}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final destPath = '$baseDir/$fileName';
      await sourceFile.copy(destPath);

      return destPath;
    } catch (e) {
      debugPrint('MediaSaver error: $e');
      return null;
    }
  }

  static Future<bool> _requestPermission() async {
    // Android 13+ يستخدم أذونات منفصلة للصور والفيديو
    if (Platform.isAndroid) {
      final sdkVersion = await _getAndroidSdkVersion();
      if (sdkVersion >= 33) {
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        return photos.isGranted || videos.isGranted;
      } else {
        final storage = await Permission.storage.request();
        return storage.isGranted;
      }
    }
    return true;
  }

  static Future<int> _getAndroidSdkVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 30;
    } catch (_) {
      return 30;
    }
  }
}
