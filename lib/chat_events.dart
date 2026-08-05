import 'package:flutter/foundation.dart';
import 'models.dart';

/// حافلة أحداث مشتركة بين PeersListScreen و ChatScreen
/// تتجنب الاستيراد الدائري بين الشاشتين.
class ChatEvents {
  ChatEvents._();

  /// يُسجّله ChatScreen عند الفتح ويمسحه عند الإغلاق.
  /// يُستدعى عند استقبال رسالة read_ack_all لتحديث علامات الصح فوراً.
  static VoidCallback? onReadAckAllReceived;

  /// يُسجّله ChatScreen عند الفتح.
  /// يُستدعى عند إرسال رسالة من زر الرد في الإشعار (background reply)
  /// حتى تُحدِّث ChatScreen نفسها فوراً.
  static void Function(Message msg)? onNotificationReplySent;

  /// يُسجّله ChatScreen عند الفتح.
  /// يُستدعى عند الضغط على "تمييز كمقروءة" من الإشعار
  /// حتى تُحدِّث ChatScreen حالة القراءة في واجهتها فوراً.
  static VoidCallback? onMarkedReadFromNotification;
}

