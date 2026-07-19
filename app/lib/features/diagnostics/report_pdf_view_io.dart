import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Mobile/desktop PDF rendering via pdfx (native pdfium) — no pdf.js, no CDN.
Widget buildReportPdfView({
  required String signedUrl,
  required Future<Uint8List> Function() loadBytes,
}) {
  return _PdfxReportView(loadBytes: loadBytes);
}

class _PdfxReportView extends StatefulWidget {
  const _PdfxReportView({required this.loadBytes});
  final Future<Uint8List> Function() loadBytes;

  @override
  State<_PdfxReportView> createState() => _PdfxReportViewState();
}

class _PdfxReportViewState extends State<_PdfxReportView> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.loadBytes()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewPinch(controller: _controller);
  }
}
