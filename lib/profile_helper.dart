import 'package:shared_preferences/shared_preferences.dart';

class ProfileHelper {
  static const String keyUserName = 'user_name';
  static const String keyAvatarPath = 'user_image_path';
  static const String keyUserId = 'user_device_id';

  static Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(keyUserId);
    if (id == null || id.isEmpty) {
      id = 'usr_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(keyUserId, id);
    }
    return id;
  }

  static Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyUserName) ??
        prefs.getString('user_profile_name') ??
        'مستخدم';
  }

  static Future<String?> getAvatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyAvatarPath) ??
        prefs.getString('user_profile_avatar');
  }

  static Future<void> saveProfile(String name, String? avatarPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyUserName, name);
    await prefs.setString('user_profile_name', name);
    if (avatarPath != null) {
      await prefs.setString(keyAvatarPath, avatarPath);
      await prefs.setString('user_profile_avatar', avatarPath);
    } else {
      await prefs.remove(keyAvatarPath);
      await prefs.remove('user_profile_avatar');
    }
  }
}
