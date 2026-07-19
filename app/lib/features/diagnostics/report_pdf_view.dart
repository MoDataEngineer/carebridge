import 'dart:typed_data';

import 'package:flutter/widgets.dart';

// Platform split (mirrors shared/sound/notification_sound.dart): the web build
// renders a report PDF in a native browser <iframe> from the signed URL — which
// keeps us off a CDN-hosted pdf.js under our CSP — while mobile/desktop use
// pdfx (native pdfium) fed the raw bytes.
import 'report_pdf_view_io.dart'
    if (dart.library.js_interop) 'report_pdf_view_web.dart';

/// An inline, in-app PDF viewer for a report file.
///
/// [signedUrl] is a short-lived grant-gated link (used by the web iframe);
/// [loadBytes] lazily fetches the file bytes (used by the mobile renderer).
/// Callers give both so the same widget works on every platform.
class ReportPdfView extends StatelessWidget {
  const ReportPdfView({
    super.key,
    required this.signedUrl,
    required this.loadBytes,
  });

  final String signedUrl;
  final Future<Uint8List> Function() loadBytes;

  @override
  Widget build(BuildContext context) =>
      buildReportPdfView(signedUrl: signedUrl, loadBytes: loadBytes);
}
