import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A real, scannable QR for a share/order code (audit gap: codes were text
/// only). Always drawn dark-on-white inside a white card — a QR must keep its
/// contrast in dark mode or scanners fail on it.
class CodeQr extends StatelessWidget {
  const CodeQr({super.key, required this.code, this.size = 180});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: code,
        version: QrVersions.auto,
        size: size,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square, color: Colors.black),
        dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square, color: Colors.black),
      ),
    );
  }
}
