import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'dart:convert';
import 'dart:io';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool _scanned = false;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller?.pauseCamera();
    }
    controller?.resumeCamera();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (_scanned || scanData.code == null) return;
      _scanned = true;
      controller.pauseCamera();

      try {
        final data = jsonDecode(scanData.code!);
        final ip = data['ip'] as String?;
        final port = data['port'] as int? ?? 8888;

        if (ip != null && ip.isNotEmpty) {
          Navigator.of(context).pop({'ip': ip, 'port': port});
        } else {
          _showError('QR Code غير صالح');
        }
      } catch (e) {
        // تجربة إذا كان الباركود يحتوي فقط على نص الـ IP المباشر
        final rawIp = scanData.code!.trim();
        if (RegExp(r'^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$').hasMatch(rawIp)) {
          Navigator.of(context).pop({'ip': rawIp, 'port': 8888});
        } else {
          _showError('تعذّر قراءة بيانات الـ QR');
        }
      }
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _scanned = false;
        controller?.resumeCamera();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: Stack(
        children: [
          // كاميرا مسح الباركود المباشرة
          QRView(
            key: qrKey,
            onQRViewCreated: _onQRViewCreated,
            overlay: QrScannerOverlayShape(
              borderColor: const Color(0xFFe94560),
              borderRadius: 16,
              borderLength: 30,
              borderWidth: 6,
              cutOutSize: 280,
            ),
          ),

          // شريط العناوين والأزرار
          SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.black54,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text(
                          'مسح الباركود للانضمام',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await controller?.toggleFlash();
                          setState(() {});
                        },
                        icon: const Icon(Icons.flash_on, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // نص توضيحي في الأسفل
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: const Text(
                'وجه الكاميرا نحو باركود الـ QR الخاص بجهاز المضيف للانضمام فوراً تلقائياً',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
