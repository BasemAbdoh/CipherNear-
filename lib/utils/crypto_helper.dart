import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// طبقة التشفير الكاملة للتطبيق
/// تعتمد على:
///   - X25519 (ECDH) لتبادل المفاتيح بأمان بين الجهازين
///   - AES-256-GCM للتشفير المتماثل المصادق عليه لكل رسالة
class CryptoHelper {
  CryptoHelper._();

  static final _x25519  = X25519();
  static final _aesGcm  = AesGcm.with256bits();

  // زوج مفاتيحي (يُنشأ مرة واحدة لكل جلسة)
  static SimpleKeyPair?  _myKeyPair;

  // المفتاح المشترك المشتق من ECDH — يُستخدم لتشفير/فك الرسائل
  static SecretKey? _sharedKey;

  // ─────────────────────────────────────────────────────────────
  // إنشاء / استرداد زوج المفاتيح الخاص بي
  // ─────────────────────────────────────────────────────────────
  static Future<SimpleKeyPair> _getKeyPair() async {
    _myKeyPair ??= await _x25519.newKeyPair();
    return _myKeyPair!;
  }

  /// يُعيد المفتاح العام بصيغة Base64 ليُرسل في رسالة المصافحة
  static Future<String> getPublicKeyBase64() async {
    final kp = await _getKeyPair();
    final pub = await kp.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  // ─────────────────────────────────────────────────────────────
  // استخلاص المفتاح المشترك عند استقبال مفتاح الطرف الآخر
  // ─────────────────────────────────────────────────────────────
  static Future<void> deriveSharedKey(String peerPublicKeyBase64) async {
    try {
      final kp = await _getKeyPair();
      final peerBytes = base64Decode(peerPublicKeyBase64);
      final peerPublicKey = SimplePublicKey(peerBytes, type: KeyPairType.x25519);
      _sharedKey = await _x25519.sharedSecretKey(
        keyPair: kp,
        remotePublicKey: peerPublicKey,
      );
    } catch (e) {
      _sharedKey = null;
    }
  }

  /// هل تم تأسيس المفتاح المشترك بنجاح؟
  static bool get hasSharedKey => _sharedKey != null;

  /// إعادة تعيين الجلسة عند قطع الاتصال
  static void resetSession() {
    _sharedKey = null;
    _myKeyPair = null;
  }

  // ─────────────────────────────────────────────────────────────
  // تشفير رسالة نصية (JSON) بـ AES-256-GCM
  // يُعيد: Base64( nonce[12] || mac[16] || ciphertext )
  // ─────────────────────────────────────────────────────────────
  static Future<String?> encrypt(String plaintext) async {
    if (_sharedKey == null) return null;
    try {
      final box = await _aesGcm.encrypt(
        utf8.encode(plaintext),
        secretKey: _sharedKey!,
      );
      final combined = Uint8List(
        box.nonce.length + box.mac.bytes.length + box.cipherText.length,
      );
      int offset = 0;
      combined.setRange(offset, offset += box.nonce.length,   box.nonce);
      combined.setRange(offset, offset += box.mac.bytes.length, box.mac.bytes);
      combined.setRange(offset, offset +  box.cipherText.length, box.cipherText);
      return base64Encode(combined);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // فك تشفير رسالة مشفرة
  // ─────────────────────────────────────────────────────────────
  static Future<String?> decrypt(String encryptedBase64) async {
    if (_sharedKey == null) return null;
    try {
      final combined = base64Decode(encryptedBase64);
      // AES-GCM: nonce = 12 bytes، MAC = 16 bytes، باقي = ciphertext
      const nonceLen = 12;
      const macLen   = 16;
      final nonce      = combined.sublist(0, nonceLen);
      final macBytes   = combined.sublist(nonceLen, nonceLen + macLen);
      final cipherText = combined.sublist(nonceLen + macLen);
      final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final plainBytes = await _aesGcm.decrypt(box, secretKey: _sharedKey!);
      return utf8.decode(plainBytes);
    } catch (_) {
      return null;
    }
  }

  static void reset() {
    _sharedKey = null;
    _myKeyPair = null;
  }
}
