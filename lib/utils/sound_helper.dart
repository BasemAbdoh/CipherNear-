import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class SoundHelper {
  SoundHelper._();
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playSendSound() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/send.mp3'), volume: 0.6);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  static Future<void> playReceiveSound() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/receive.mp3'), volume: 0.8);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }
}
