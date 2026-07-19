import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

// Tracks which iframe view types we've already registered (registering the same
// type twice throws). Keyed by the signed URL.
final Set<String> _registered = <String>{};

/// Web PDF rendering: a native browser <iframe> pointed at the grant-gated
/// signed URL. Browsers render PDFs inline, so we avoid loading pdf.js from a
/// CDN (which our Content-Security-Policy blocks). The page CSP must allow
/// `frame-src https://*.supabase.co` for the embed (see web/index.html).
Widget buildReportPdfView({
  required String signedUrl,
  required Future<Uint8List> Function() loadBytes,
}) {
  final viewType = 'report-pdf-${signedUrl.hashCode}';
  if (!_registered.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final iframe = web.HTMLIFrameElement()
        ..src = signedUrl
        ..title = 'Report PDF'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
    _registered.add(viewType);
  }
  return HtmlElementView(viewType: viewType);
}
