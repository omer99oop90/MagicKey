import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../models/file_source.dart';
import '../models/pdf_document.dart';

/// Exception thrown when native PDF processing encounters an error.
class PdfException implements Exception {
  final String code;
  final String message;

  const PdfException(this.code, this.message);

  bool get isEncrypted => code == 'ENCRYPTED_PDF';
  bool get isMalformed => code == 'MALFORMED_PDF';

  @override
  String toString() => 'PdfException($code): $message';
}

/// Central service communicating with the native Android PdfRenderer engine via MethodChannel.
class PdfService {
  static const MethodChannel _pdfChannel = MethodChannel('com.magickey/pdf');

  static final PdfService instance = PdfService._();
  PdfService._();
  factory PdfService() => instance;

  /// Opens a PDF document through native PdfRenderer, returning page counts and dimensions.
  Future<PdfDocument> openPdf(FileSource source) async {
    try {
      final res = await _pdfChannel.invokeMapMethod<String, dynamic>(
        'openPdf',
        {
          'uri': source.uri,
          'path': source.path,
        },
      );

      if (res == null) {
        throw const PdfException('OPEN_FAILED', 'Native PDF renderer returned empty session');
      }

      return PdfDocument.fromJson(res);
    } on PlatformException catch (e) {
      throw PdfException(e.code, e.message ?? 'Platform exception opening PDF');
    }
  }

  /// Renders a single page to a lossless PNG byte buffer.
  Future<Uint8List> renderPage({
    required String sessionId,
    required int pageIndex,
    int targetWidth = 1080,
  }) async {
    try {
      final bytes = await _pdfChannel.invokeMethod<Uint8List>(
        'renderPage',
        {
          'sessionId': sessionId,
          'pageIndex': pageIndex,
          'targetWidth': targetWidth,
        },
      );

      if (bytes == null || bytes.isEmpty) {
        throw PdfException('RENDER_EMPTY', 'Page $pageIndex rendered 0 bytes');
      }

      return bytes;
    } on PlatformException catch (e) {
      throw PdfException(e.code, e.message ?? 'Failed to render page $pageIndex');
    }
  }

  /// Releases the native PdfRenderer session, parcel file descriptors, and temporary files.
  Future<void> closePdf(String sessionId) async {
    if (sessionId.isEmpty) return;
    try {
      await _pdfChannel.invokeMethod('closePdf', {'sessionId': sessionId});
    } catch (_) {}
  }
}
