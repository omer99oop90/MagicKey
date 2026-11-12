import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magickey/l10n/app_localizations.dart';
import 'package:magickey/models/detection_result.dart';
import 'package:magickey/models/file_source.dart';
import 'package:magickey/models/pdf_document.dart';
import 'package:magickey/screens/viewer_screen.dart';
import 'package:magickey/services/pdf_service.dart';
import 'package:magickey/viewers/pdf_viewer.dart';
import 'package:magickey/viewers/unsupported_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel pdfChannel = MethodChannel('com.magickey/pdf');

  group('PDF Models & Deserialization Tests', () {
    test('PdfPageInfo correctly calculates aspect ratio', () {
      const pageLetter = PdfPageInfo(pageIndex: 0, width: 612, height: 792);
      expect(pageLetter.aspectRatio, closeTo(612 / 792, 0.001));

      const pageA4 = PdfPageInfo(pageIndex: 1, width: 595, height: 842);
      expect(pageA4.aspectRatio, closeTo(595 / 842, 0.001));

      const pageZeroHeight = PdfPageInfo(pageIndex: 2, width: 600, height: 0);
      expect(pageZeroHeight.aspectRatio, 1.0);
    });

    test('PdfDocument deserialization from JSON', () {
      final json = {
        'sessionId': 'session_123',
        'pageCount': 2,
        'pages': [
          {'pageIndex': 0, 'width': 612, 'height': 792},
          {'pageIndex': 1, 'width': 612, 'height': 792},
        ],
      };

      final doc = PdfDocument.fromJson(json);
      expect(doc.sessionId, 'session_123');
      expect(doc.pageCount, 2);
      expect(doc.pages.length, 2);
      expect(doc.pages[0].pageIndex, 0);
      expect(doc.pages[0].width, 612);
      expect(doc.pages[0].height, 792);
      expect(doc.pages[1].pageIndex, 1);
    });
  });

  group('PdfService Channel & Exception Tests', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, null);
    });

    test('openPdf invokes native openPdf and returns PdfDocument', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, (MethodCall call) async {
        if (call.method == 'openPdf') {
          return {
            'sessionId': 'mock_session_456',
            'pageCount': 1,
            'pages': [
              {'pageIndex': 0, 'width': 612, 'height': 792},
            ],
          };
        }
        return null;
      });

      final service = PdfService.instance;
      final source = LocalPathFileSource(path: '/storage/sample.pdf', name: 'sample.pdf', size: 1024);
      final doc = await service.openPdf(source);

      expect(doc.sessionId, 'mock_session_456');
      expect(doc.pageCount, 1);
      expect(doc.pages.first.width, 612);
    });

    test('openPdf converts ENCRYPTED_PDF PlatformException to PdfException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, (MethodCall call) async {
        if (call.method == 'openPdf') {
          throw PlatformException(code: 'ENCRYPTED_PDF', message: 'Document is password-protected');
        }
        return null;
      });

      final service = PdfService.instance;
      final source = LocalPathFileSource(path: '/storage/locked.pdf', name: 'locked.pdf', size: 1024);

      try {
        await service.openPdf(source);
        fail('Should throw PdfException');
      } on PdfException catch (e) {
        expect(e.isEncrypted, isTrue);
        expect(e.isMalformed, isFalse);
        expect(e.code, 'ENCRYPTED_PDF');
      }
    });

    test('openPdf converts MALFORMED_PDF PlatformException to PdfException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, (MethodCall call) async {
        if (call.method == 'openPdf') {
          throw PlatformException(code: 'MALFORMED_PDF', message: 'Document structure corrupted');
        }
        return null;
      });

      final service = PdfService.instance;
      final source = LocalPathFileSource(path: '/storage/broken.pdf', name: 'broken.pdf', size: 100);

      try {
        await service.openPdf(source);
        fail('Should throw PdfException');
      } on PdfException catch (e) {
        expect(e.isMalformed, isTrue);
        expect(e.isEncrypted, isFalse);
        expect(e.code, 'MALFORMED_PDF');
      }
    });

    test('renderPage returns byte array and handles render errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, (MethodCall call) async {
        if (call.method == 'renderPage') {
          return Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
        }
        return null;
      });

      final service = PdfService.instance;
      final bytes = await service.renderPage(sessionId: 'mock_session_456', pageIndex: 0);
      expect(bytes.length, 4);
      expect(bytes[0], 0x89);
    });

    test('closePdf invokes native channel without throwing', () async {
      bool closed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, (MethodCall call) async {
        if (call.method == 'closePdf') {
          closed = true;
          return null;
        }
        return null;
      });

      final service = PdfService.instance;
      await service.closePdf('mock_session_456');
      expect(closed, isTrue);
    });
  });

  group('ViewerScreen Routing Tests for Document Formats', () {
    testWidgets('Routes PDF format to PdfViewer', (WidgetTester tester) async {
      final source = LocalPathFileSource(path: '/storage/sample.pdf', name: 'sample.pdf', size: 1024);
      const detection = DetectionResult(
        formatId: 'pdf',
        displayName: 'Portable Document Format',
        mimeType: 'application/pdf',
        category: 'document',
        confidence: 'high',
        detectionMethod: 'magic_bytes',
        suggestedViewer: 'document',
        details: 'Valid PDF',
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: ViewerScreen(
            fileSource: source,
            detectionResult: detection,
          ),
        ),
      );

      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.byType(UnsupportedViewer), findsNothing);
    });

    testWidgets('Routes DOCX or other document formats to UnsupportedViewer', (WidgetTester tester) async {
      final source = LocalPathFileSource(path: '/storage/report.docx', name: 'report.docx', size: 2048);
      const detection = DetectionResult(
        formatId: 'docx',
        displayName: 'Microsoft Word Document',
        mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        category: 'document',
        confidence: 'high',
        detectionMethod: 'magic_bytes',
        suggestedViewer: 'document',
        details: 'Valid DOCX',
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: ViewerScreen(
            fileSource: source,
            detectionResult: detection,
          ),
        ),
      );

      expect(find.byType(UnsupportedViewer), findsOneWidget);
      expect(find.byType(PdfViewer), findsNothing);
    });
  });

  group('PdfViewer Widget State Tests', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, null);
    });

    testWidgets('Displays malformed error state with hex button when PDF is corrupt', (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, (MethodCall call) async {
        if (call.method == 'openPdf') {
          throw PlatformException(code: 'MALFORMED_PDF', message: 'Broken PDF header');
        }
        return null;
      });

      final source = LocalPathFileSource(path: '/storage/corrupt.pdf', name: 'corrupt.pdf', size: 50);
      const detection = DetectionResult(
        formatId: 'pdf',
        displayName: 'Portable Document Format',
        mimeType: 'application/pdf',
        category: 'document',
        confidence: 'high',
        detectionMethod: 'magic_bytes',
        suggestedViewer: 'document',
        details: 'Malformed PDF',
      );

      bool hexClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: Scaffold(
            body: PdfViewer(
              fileSource: source,
              detectionResult: detection,
              onOpenInHex: () {
                hexClicked = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Corrupted PDF Document'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.text('Open in Hex Viewer'), findsOneWidget);

      await tester.tap(find.text('Open in Hex Viewer'));
      expect(hexClicked, isTrue);
    });

    testWidgets('Displays encrypted error state when PDF is password protected', (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, (MethodCall call) async {
        if (call.method == 'openPdf') {
          throw PlatformException(code: 'ENCRYPTED_PDF', message: 'Password required');
        }
        return null;
      });

      final source = LocalPathFileSource(path: '/storage/protected.pdf', name: 'protected.pdf', size: 50);
      const detection = DetectionResult(
        formatId: 'pdf',
        displayName: 'Portable Document Format',
        mimeType: 'application/pdf',
        category: 'document',
        confidence: 'high',
        detectionMethod: 'magic_bytes',
        suggestedViewer: 'document',
        details: 'Protected PDF',
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: Scaffold(
            body: PdfViewer(
              fileSource: source,
              detectionResult: detection,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Encrypted PDF Document'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('Renders pages and shows floating page indicator on success', (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pdfChannel, (MethodCall call) async {
        if (call.method == 'openPdf') {
          return {
            'sessionId': 'session_valid',
            'pageCount': 3,
            'pages': [
              {'pageIndex': 0, 'width': 612, 'height': 792},
              {'pageIndex': 1, 'width': 612, 'height': 792},
              {'pageIndex': 2, 'width': 612, 'height': 792},
            ],
          };
        }
        if (call.method == 'renderPage') {
          return Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
        }
        if (call.method == 'closePdf') {
          return null;
        }
        return null;
      });

      final source = LocalPathFileSource(path: '/storage/valid.pdf', name: 'valid.pdf', size: 1024);
      const detection = DetectionResult(
        formatId: 'pdf',
        displayName: 'Portable Document Format',
        mimeType: 'application/pdf',
        category: 'document',
        confidence: 'high',
        detectionMethod: 'magic_bytes',
        suggestedViewer: 'document',
        details: 'Valid PDF',
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: Scaffold(
            body: PdfViewer(
              fileSource: source,
              detectionResult: detection,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Floating indicator should display Page 1 of 3
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
}
