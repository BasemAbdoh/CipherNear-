import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'screens/peers_list_screen.dart';
import 'notification_helper.dart';

void main() async {
  // الاحتفاظ بالشاشة الترحيبية حتى يكتمل تحميل التطبيق
  final WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await NotificationHelper.initNotification();

  // إزالة الشاشة الترحيبية بعد اكتمال التحضير
  FlutterNativeSplash.remove();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'فرفش free',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(0xFFe94560),
        ),
        scaffoldBackgroundColor: Color(0xFF1a1a2e),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const PeersListScreen(),
    );
  }
}
